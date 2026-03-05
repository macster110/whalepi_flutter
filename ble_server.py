#!/usr/bin/env python3
"""
BLE Peripheral Server for WhalePiDog

This script creates a Bluetooth Low Energy (BLE) peripheral that implements
the Nordic UART Service (NUS), which is widely supported by Flutter BLE
libraries on both iOS and Android.

The server communicates with the Java application via stdin/stdout.

Requirements:
    sudo apt-get install python3-dbus python3-gi
    pip3 install bluezero

Or install manually:
    https://github.com/ukBaz/python-bluezero
"""

import sys
import signal
import argparse
from threading import Thread, Lock

# Check if bluezero is available
try:
    from bluezero import peripheral
    from bluezero import adapter
    BLUEZERO_AVAILABLE = True
except ImportError:
    BLUEZERO_AVAILABLE = False
    print("ERROR: bluezero not installed. Install with: pip3 install bluezero", file=sys.stderr)
    sys.exit(1)

# Nordic UART Service UUIDs
NUS_SERVICE_UUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
NUS_RX_CHAR_UUID = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"  # Write (receive from client)
NUS_TX_CHAR_UUID = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"  # Notify (send to client)


class BLEPeripheral:
    """BLE Peripheral implementing Nordic UART Service"""

    def __init__(self, device_name: str = "whalepi", verbose: bool = False):
        self.device_name = device_name
        self.verbose = verbose
        self.is_connected = False
        self.peripheral_app = None
        self.tx_characteristic = None   # set during start(), NOT by callback
        self.tx_notifying = False
        self.write_lock = Lock()
        self.running = True
        # Buffer holding the latest response so read-based clients can poll it
        self.last_tx_value = []

        self.log(f"Initializing BLE peripheral: {device_name}")

    def log(self, msg):
        """Log to stderr so it doesn't interfere with stdout protocol"""
        print(f"[BLE] {msg}", file=sys.stderr, flush=True)

    # ── GATT callbacks ────────────────────────────────────────────────────

    def on_connect(self, dev=None):
        """Called when a client connects.

        bluezero passes a device parameter to the connect callback.
        """
        self.is_connected = True
        self.log(f"Client connected{f': {dev}' if dev else ''}")
        print("CONNECTED", flush=True)

    def on_disconnect(self, dev=None):
        """Called when a client disconnects.

        bluezero passes a device parameter to the disconnect callback.
        """
        self.is_connected = False
        self.tx_notifying = False
        self.log(f"Client disconnected{f': {dev}' if dev else ''}")
        print("DISCONNECTED", flush=True)

    def rx_write_callback(self, value, options):
        """Called when data is written to RX characteristic.

        bluezero invokes write callbacks with two arguments:
            value   – python list of integers (decoded from dbus)
            options – dict of write options (usually empty)
        """
        try:
            message = bytes(value).decode('utf-8').strip()
            if message:
                # Forward to Java app via stdout
                print(f"RX:{message}", flush=True)
                if self.verbose:
                    self.log(f"Received: {message}")
        except Exception as e:
            self.log(f"RX error: {e}")

    def tx_read_callback(self):
        """Called when the client reads the TX characteristic value.

        Returns the last value that was sent, so polling-based clients
        (like Serial Bluetooth Terminal) can retrieve data without
        subscribing to notifications.
        """
        if self.verbose:
            self.log("TX read requested by client")
        return self.last_tx_value

    def tx_notify_callback(self, notifying, characteristic):
        """Called when the client subscribes/unsubscribes to TX notifications.

        bluezero invokes notify callbacks with two arguments:
            notifying      – True when client subscribes, False when it unsubscribes
            characteristic – the localGATT.Characteristic instance
        """
        self.tx_notifying = notifying
        # Also update our reference (should already be set from start())
        if notifying and characteristic is not None:
            self.tx_characteristic = characteristic
        self.log(f"TX notifications {'enabled' if notifying else 'disabled'}")

    # ── Sending data ──────────────────────────────────────────────────────

    def send_notification(self, data: str):
        """Send data to connected client via TX characteristic.

        Each call sends one line.  A newline is appended so the receiving
        app (Serial Bluetooth Terminal or Flutter) can detect line boundaries.
        If the resulting bytes exceed the BLE MTU the payload is chunked.

        The data is sent via set_value() which emits a D-Bus PropertiesChanged
        signal.  BlueZ will deliver this as a notification to any client that
        has subscribed (written to the CCCD).  We do NOT gate on tx_notifying
        because some clients (like Serial Bluetooth Terminal) subscribe at the
        BlueZ/CCCD level without triggering bluezero's StartNotify callback.
        """
        if not self.is_connected:
            if self.verbose:
                self.log("Cannot send - no client connected")
            return False

        if self.tx_characteristic is None:
            self.log("Cannot send - TX characteristic not initialised")
            return False

        try:
            import time
            with self.write_lock:
                # Ensure the line ends with exactly one newline
                if not data.endswith('\n'):
                    data += '\n'
                byte_data = list(data.encode('utf-8'))
                # Keep a copy for read-based polling clients
                self.last_tx_value = byte_data[:]
                # BLE has a max MTU, typically 20 bytes for default, up to 512.
                # Chunk if necessary (most NUS implementations handle up to 240).
                MAX_CHUNK = 240
                for i in range(0, len(byte_data), MAX_CHUNK):
                    chunk = byte_data[i:i + MAX_CHUNK]
                    self.tx_characteristic.set_value(chunk)
                    # Small delay between chunks to let the BLE stack process
                    if i + MAX_CHUNK < len(byte_data):
                        time.sleep(0.02)

                if self.verbose:
                    preview = data.strip()
                    if len(preview) > 60:
                        preview = preview[:60] + "..."
                    self.log(f"Sent: {preview}")
                return True
        except Exception as e:
            self.log(f"TX error: {e}")
            return False

    # ── Start / Stop ──────────────────────────────────────────────────────

    def start(self):
        """Start the BLE peripheral (blocks – runs the GLib main loop)."""
        try:
            self.log("Setting up BLE GATT service...")

            # --- Discover the local Bluetooth adapter address ---------------
            try:
                adapters = list(adapter.Adapter.available())
                if not adapters:
                    self.log("ERROR: No Bluetooth adapters found")
                    return False
                adapter_address = str(adapters[0].address)
                self.log(f"Using Bluetooth adapter: {adapter_address}")
            except Exception as e:
                self.log(f"ERROR: Could not discover Bluetooth adapter: {e}")
                return False

            # --- Create the peripheral with the correct adapter address -----
            self.peripheral_app = peripheral.Peripheral(
                adapter_address,
                local_name=self.device_name
            )

            # --- Add Nordic UART Service -----------------------------------
            self.peripheral_app.add_service(
                srv_id=1,
                uuid=NUS_SERVICE_UUID,
                primary=True
            )

            # RX characteristic – client writes commands here
            self.peripheral_app.add_characteristic(
                srv_id=1,
                chr_id=1,
                uuid=NUS_RX_CHAR_UUID,
                value=[],
                notifying=False,
                flags=['write', 'write-without-response'],
                write_callback=self.rx_write_callback,
                read_callback=None,
                notify_callback=None
            )

            # TX characteristic – we notify the client from here
            self.peripheral_app.add_characteristic(
                srv_id=1,
                chr_id=2,
                uuid=NUS_TX_CHAR_UUID,
                value=[],
                notifying=False,
                flags=['notify', 'read'],
                write_callback=None,
                read_callback=self.tx_read_callback,
                notify_callback=self.tx_notify_callback
            )

            # Grab a reference to the TX characteristic object so we can
            # call set_value() on it later.  This is the last characteristic
            # we added, so it is at the end of the list.
            self.tx_characteristic = self.peripheral_app.characteristics[-1]
            self.log("TX characteristic reference acquired")

            # --- Wire up connect / disconnect callbacks --------------------
            self.peripheral_app.on_connect = self.on_connect
            self.peripheral_app.on_disconnect = self.on_disconnect

            self.log(f"Publishing BLE service...")
            self.log(f"  Device name : {self.device_name}")
            self.log(f"  Service UUID: {NUS_SERVICE_UUID}")
            self.log(f"  RX UUID     : {NUS_RX_CHAR_UUID}")
            self.log(f"  TX UUID     : {NUS_TX_CHAR_UUID}")

            # publish() runs the GLib/D-Bus main loop and blocks.
            # stdin reading happens in a daemon thread started before this.
            self.peripheral_app.publish()

            # publish() only returns when the main loop is quit
            return True

        except Exception as e:
            self.log(f"Failed to start BLE peripheral: {e}")
            import traceback
            traceback.print_exc(file=sys.stderr)
            return False

    def stop(self):
        """Request a clean shutdown."""
        self.running = False
        if self.peripheral_app:
            try:
                # quit the GLib main loop so publish() returns
                self.peripheral_app.quit()
            except Exception:
                pass


def stdin_reader(ble_peripheral: BLEPeripheral):
    """Read commands from stdin (from Java app) in a separate thread."""
    while ble_peripheral.running:
        try:
            line = sys.stdin.readline()
            if not line:
                # stdin closed – Java process gone
                ble_peripheral.log("stdin closed – shutting down")
                ble_peripheral.stop()
                break

            line = line.strip()
            if not line:
                continue

            if line.startswith("TX:"):
                message = line[3:]
                ble_peripheral.send_notification(message)
                # Small delay between successive notifications so BlueZ
                # doesn't coalesce PropertiesChanged D-Bus signals.
                import time
                time.sleep(0.05)
            elif line == "SHUTDOWN":
                ble_peripheral.log("Received shutdown command")
                ble_peripheral.stop()
                break

        except Exception as e:
            ble_peripheral.log(f"stdin error: {e}")
            break


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description='BLE Peripheral for WhalePiDog')
    parser.add_argument('--name', default='whalepi', help='Device name')
    parser.add_argument('--verbose', action='store_true', help='Verbose logging')

    args = parser.parse_args()

    # Create peripheral
    ble = BLEPeripheral(device_name=args.name, verbose=args.verbose)

    # Handle signals
    def signal_handler(sig, frame):
        ble.log("Interrupt received, shutting down...")
        ble.stop()
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Start stdin reader in a daemon thread BEFORE publish() (which blocks)
    stdin_thread = Thread(target=stdin_reader, args=(ble,), daemon=True)
    stdin_thread.start()

    ble.log("Starting BLE peripheral (publish)...")

    # start() calls publish() which blocks until quit
    if not ble.start():
        ble.log("Failed to start BLE peripheral")
        sys.exit(1)

    ble.log("BLE peripheral stopped")


if __name__ == "__main__":
    if not BLUEZERO_AVAILABLE:
        sys.exit(1)
    main()
