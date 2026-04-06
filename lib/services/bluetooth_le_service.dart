import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Callback types for BLE events
typedef OnDataReceived = void Function(Uint8List data);
typedef OnConnectionStateChanged = void Function(bool connected);
typedef OnError = void Function(String error);
typedef OnLog = void Function(String message);

/// Common BLE UART Service UUIDs (Nordic UART Service)
class BleUartUuids {
  // Nordic UART Service
  static final Guid nordicUart = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
  static final Guid nordicUartTx = Guid(
    '6E400002-B5A3-F393-E0A9-E50E24DCCA9E',
  ); // Write
  static final Guid nordicUartRx = Guid(
    '6E400003-B5A3-F393-E0A9-E50E24DCCA9E',
  ); // Notify

  // TI CC254x UART
  static final Guid tiUart = Guid('0000FFE0-0000-1000-8000-00805F9B34FB');
  static final Guid tiUartRxTx = Guid('0000FFE1-0000-1000-8000-00805F9B34FB');

  // HM-10/HM-19 modules
  static final Guid hm10Uart = Guid('0000FFE0-0000-1000-8000-00805F9B34FB');
  static final Guid hm10RxTx = Guid('0000FFE1-0000-1000-8000-00805F9B34FB');

  // List of known UART service UUIDs
  static List<Guid> get knownServices => [nordicUart, tiUart, hm10Uart];
}

/// Represents a discovered UART characteristic pair
class UartCharacteristics {
  final BluetoothCharacteristic? txCharacteristic; // For writing
  final BluetoothCharacteristic? rxCharacteristic; // For reading/notifications

  UartCharacteristics({this.txCharacteristic, this.rxCharacteristic});

  bool get isValid => txCharacteristic != null || rxCharacteristic != null;
}

/// Service for managing Bluetooth Low Energy connections with UART-like communication
class BluetoothLeService {
  static final BluetoothLeService _instance = BluetoothLeService._internal();
  factory BluetoothLeService() => _instance;
  BluetoothLeService._internal();

  BluetoothDevice? _connectedDevice;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  BluetoothCharacteristic? _txCharacteristic;
  BluetoothCharacteristic? _rxCharacteristic;

  StreamSubscription<List<int>>? _rxSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // Callbacks
  OnDataReceived? onDataReceived;
  OnConnectionStateChanged? onConnectionStateChanged;
  OnError? onError;
  OnLog? onLog;

  void _log(String message) {
    debugPrint('[BLE] $message');
    onLog?.call(message);
  }

  /// Check if Bluetooth is supported
  Future<bool> get isSupported async {
    return await FlutterBluePlus.isSupported;
  }

  /// Check if Bluetooth adapter is on
  Future<bool> get isOn async {
    final state = await FlutterBluePlus.adapterState.first;
    return state == BluetoothAdapterState.on;
  }

  /// Turn on Bluetooth (Android only)
  Future<void> turnOn() async {
    await FlutterBluePlus.turnOn();
  }

  /// Start scanning for BLE devices
  Stream<List<ScanResult>> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) {
    FlutterBluePlus.startScan(timeout: timeout, androidUsesFineLocation: true);
    return FlutterBluePlus.scanResults;
  }

  /// Stop scanning
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  /// Get bonded/paired devices (Android only)
  Future<List<BluetoothDevice>> getBondedDevices() async {
    return await FlutterBluePlus.bondedDevices;
  }

  /// Connect to a BLE device
  Future<bool> connect(BluetoothDevice device) async {
    if (_isConnected) {
      await disconnect();
    }

    try {
      // Stop any ongoing scan
      await FlutterBluePlus.stopScan();

      // Connect to the device
      await device.connect(
        license: License.free,
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      _connectedDevice = device;

      // Listen for connection state changes
      _connectionSubscription = device.connectionState.listen((state) {
        final connected = state == BluetoothConnectionState.connected;
        if (_isConnected != connected) {
          _isConnected = connected;
          onConnectionStateChanged?.call(connected);
          if (!connected) {
            _cleanup();
          }
        }
      });

      // Discover services and find UART characteristics
      final success = await _discoverUartService(device);
      if (!success) {
        onError?.call('No compatible UART service found');
        await disconnect();
        return false;
      }

      _isConnected = true;
      onConnectionStateChanged?.call(true);
      return true;
    } catch (e) {
      onError?.call('Failed to connect: $e');
      _cleanup();
      return false;
    }
  }

  /// Discover UART service and characteristics
  Future<bool> _discoverUartService(BluetoothDevice device) async {
    try {
      // Request higher MTU for better throughput (important for some devices)
      try {
        await device.requestMtu(512);
      } catch (e) {
        // MTU request may fail on some platforms, ignore
      }

      // Clear macOS/iOS GATT cache to avoid stale handles
      try {
        await device.clearGattCache();
        _log('GATT cache cleared');
      } catch (e) {
        _log('clearGattCache not supported: $e');
      }

      await device.discoverServices();

      // Wait for iOS/macOS to finish setting up all handles/descriptors
      await Future.delayed(const Duration(milliseconds: 500));

      // Use servicesList to get fresh references after discovery completes
      final services = device.servicesList;

      // Log discovered services for debugging
      _log('Discovered ${services.length} services');
      for (final service in services) {
        _log('Service: ${service.uuid}');
        for (final char in service.characteristics) {
          _log(
            '  Char: ${char.uuid} '
            'W=${char.properties.write} '
            'WnR=${char.properties.writeWithoutResponse} '
            'N=${char.properties.notify} '
            'I=${char.properties.indicate}',
          );
        }
      }

      // Find all matching UART services and try each until setNotifyValue works
      BluetoothCharacteristic? workingTx;
      BluetoothCharacteristic? workingRx;

      for (final service in services) {
        final uartChars = _findUartCharacteristics(service);
        if (uartChars.isValid) {
          _log('Found UART service candidate: ${service.uuid}');

          // Try to enable notifications on this service's RX characteristic
          if (uartChars.rxCharacteristic != null) {
            try {
              await Future.delayed(const Duration(milliseconds: 100));
              await uartChars.rxCharacteristic!.setNotifyValue(true);
              _log(
                'setNotifyValue SUCCEEDED for ${uartChars.rxCharacteristic!.uuid} on service ${service.uuid}',
              );
              workingTx = uartChars.txCharacteristic;
              workingRx = uartChars.rxCharacteristic;
              break; // Found a working one, stop looking
            } catch (e) {
              _log('setNotifyValue failed for service ${service.uuid}: $e');
              // Try the next matching service
            }
          } else {
            // No RX, but TX-only might still be useful
            workingTx ??= uartChars.txCharacteristic;
          }
        }
      }

      // If none succeeded with setNotifyValue, fall back to last match
      if (workingRx == null) {
        _log('No service accepted setNotifyValue, using last match');
        for (final service in services) {
          final uartChars = _findUartCharacteristics(service);
          if (uartChars.isValid) {
            workingTx = uartChars.txCharacteristic;
            workingRx = uartChars.rxCharacteristic;
          }
        }
      }

      if (workingTx != null || workingRx != null) {
        _txCharacteristic = workingTx;
        _rxCharacteristic = workingRx;
        _log('Using TX: ${_txCharacteristic?.uuid}');
        _log('Using RX: ${_rxCharacteristic?.uuid}');

        // Enable notifications on RX characteristic (if not already done above)
        if (_rxCharacteristic != null) {
          try {
            // Check if already notifying (from the loop above)
            if (!_rxCharacteristic!.isNotifying) {
              await Future.delayed(const Duration(milliseconds: 100));
              await _rxCharacteristic!.setNotifyValue(true);
              _log('Notifications enabled (fallback path)');
            }
          } catch (e) {
            _log('setNotifyValue failed (continuing): $e');
          }

          // Wait a moment for the subscription to register on the peripheral
          await Future.delayed(const Duration(milliseconds: 200));

          _rxSubscription = _rxCharacteristic!.onValueReceived.listen(
            (data) {
              if (data.isNotEmpty) {
                onDataReceived?.call(Uint8List.fromList(data));
              }
            },
            onError: (error) {
              onError?.call('RX error: $error');
            },
          );
        }

        return true;
      }

      // If no known UART service found, try to find any writable/notify characteristics
      for (final service in services) {
        BluetoothCharacteristic? writeChar;
        BluetoothCharacteristic? notifyChar;

        for (final char in service.characteristics) {
          if (char.properties.write || char.properties.writeWithoutResponse) {
            writeChar ??= char;
          }
          if (char.properties.notify || char.properties.indicate) {
            notifyChar ??= char;
          }
        }

        if (writeChar != null || notifyChar != null) {
          _txCharacteristic = writeChar;
          _rxCharacteristic = notifyChar;

          _log('Using fallback characteristics');
          _log('TX: ${_txCharacteristic?.uuid}');
          _log('RX: ${_rxCharacteristic?.uuid}');

          if (_rxCharacteristic != null) {
            await Future.delayed(const Duration(milliseconds: 100));
            try {
              await _rxCharacteristic!.setNotifyValue(true);
              _log('Notifications enabled (fallback)');
            } catch (e) {
              _log('setNotifyValue failed (fallback, continuing): $e');
            }
            await Future.delayed(const Duration(milliseconds: 200));

            _rxSubscription = _rxCharacteristic!.onValueReceived.listen(
              (data) {
                if (data.isNotEmpty) {
                  onDataReceived?.call(Uint8List.fromList(data));
                }
              },
              onError: (error) {
                onError?.call('RX error: $error');
              },
            );
          }

          return true;
        }
      }

      return false;
    } catch (e) {
      onError?.call('Service discovery failed: $e');
      return false;
    }
  }

  /// Find UART characteristics in a service
  UartCharacteristics _findUartCharacteristics(BluetoothService service) {
    BluetoothCharacteristic? txChar;
    BluetoothCharacteristic? rxChar;

    // Check for Nordic UART Service
    if (service.uuid == BleUartUuids.nordicUart) {
      for (final char in service.characteristics) {
        if (char.uuid == BleUartUuids.nordicUartTx) {
          txChar = char;
        } else if (char.uuid == BleUartUuids.nordicUartRx) {
          rxChar = char;
        }
      }
    }
    // Check for TI/HM-10 style UART (single characteristic for both)
    else if (service.uuid == BleUartUuids.tiUart ||
        service.uuid == BleUartUuids.hm10Uart) {
      for (final char in service.characteristics) {
        if (char.uuid == BleUartUuids.tiUartRxTx ||
            char.uuid == BleUartUuids.hm10RxTx) {
          txChar = char;
          rxChar = char;
        }
      }
    }

    return UartCharacteristics(
      txCharacteristic: txChar,
      rxCharacteristic: rxChar,
    );
  }

  /// Disconnect from the current device
  Future<void> disconnect() async {
    _cleanup();

    try {
      await _connectedDevice?.disconnect();
    } catch (e) {
      // Ignore disconnect errors
    }

    _connectedDevice = null;
    _isConnected = false;
    onConnectionStateChanged?.call(false);
  }

  void _cleanup() {
    _rxSubscription?.cancel();
    _rxSubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _txCharacteristic = null;
    _rxCharacteristic = null;
  }

  /// Send data as bytes
  Future<bool> sendBytes(Uint8List data) async {
    if (!_isConnected || _txCharacteristic == null) {
      onError?.call('Not connected or no TX characteristic');
      return false;
    }

    try {
      // BLE has MTU limits, typically 20 bytes for older devices, up to 512 for newer
      // Split data if necessary
      final mtu = await _connectedDevice?.mtu.first ?? 20;
      final chunkSize = mtu - 3; // Account for ATT overhead

      if (data.length <= chunkSize) {
        await _txCharacteristic!.write(
          data.toList(),
          withoutResponse: true, // Use writeWithoutResponse
        );
      } else {
        // Send in chunks
        for (int i = 0; i < data.length; i += chunkSize) {
          final end = (i + chunkSize > data.length)
              ? data.length
              : i + chunkSize;
          final chunk = data.sublist(i, end);
          await _txCharacteristic!.write(
            chunk.toList(),
            withoutResponse: true, // Use writeWithoutResponse
          );
          // Small delay between chunks to prevent buffer overflow
          await Future.delayed(const Duration(milliseconds: 20));
        }
      }
      return true;
    } catch (e) {
      onError?.call('Failed to send data: $e');
      return false;
    }
  }

  /// Send string data with optional line ending
  Future<bool> sendString(String text, {String lineEnding = '\r\n'}) async {
    final data = utf8.encode(text + lineEnding);
    return sendBytes(Uint8List.fromList(data));
  }

  /// Convert bytes to hex string for display
  static String bytesToHex(Uint8List bytes) {
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }

  /// Convert hex string to bytes
  static Uint8List hexToBytes(String hex) {
    hex = hex.replaceAll(' ', '');
    final bytes = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      if (i + 2 <= hex.length) {
        bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
    }
    return Uint8List.fromList(bytes);
  }

  /// Dispose resources
  void dispose() {
    disconnect();
  }
}
