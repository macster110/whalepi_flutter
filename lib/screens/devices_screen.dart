import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';
import '../services/bluetooth_le_service.dart';
import '../services/mock_bluetooth_service.dart';
import 'device_screen.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final BluetoothLeService _bluetoothService = BluetoothLeService();

  List<BluetoothDevice> _bondedDevices = [];
  List<ScanResult> _scanResults = [];

  bool _isBluetoothOn = false;
  bool _isScanning = false;
  bool _isLoading = true;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initBluetooth() async {
    setState(() => _isLoading = true);

    // Request permissions
    await _requestPermissions();

    // Check if Bluetooth is supported
    final isSupported = await _bluetoothService.isSupported;
    if (!isSupported) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth is not supported on this device'),
          ),
        );
      }
      setState(() => _isLoading = false);
      return;
    }

    // Listen for adapter state changes
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (mounted) {
        setState(() {
          _isBluetoothOn = state == BluetoothAdapterState.on;
        });
        if (_isBluetoothOn) {
          _loadBondedDevices();
        }
      }
    });

    _isBluetoothOn = await _bluetoothService.isOn;

    if (_isBluetoothOn) {
      await _loadBondedDevices();
    }

    setState(() => _isLoading = false);
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      // Request Bluetooth permissions for Android 12+
      await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
    } else if (Platform.isIOS) {
      // iOS permissions via permission_handler
      await Permission.bluetooth.request();
    }
    // macOS: permissions handled via entitlements, no runtime request needed
  }

  Future<void> _loadBondedDevices() async {
    if (Platform.isAndroid) {
      final devices = await _bluetoothService.getBondedDevices();
      setState(() {
        _bondedDevices = devices;
      });
    }
  }

  Future<void> _enableBluetooth() async {
    if (Platform.isAndroid) {
      try {
        await _bluetoothService.turnOn();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to enable Bluetooth: $e')),
          );
        }
      }
    } else {
      // On iOS/macOS, direct user to settings
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enable Bluetooth in System Settings'),
          ),
        );
      }
    }
  }

  void _startScan() {
    setState(() {
      _isScanning = true;
      _scanResults.clear();
    });

    _scanSubscription = _bluetoothService
        .startScan(timeout: const Duration(seconds: 15))
        .listen(
          (results) {
            setState(() {
              _scanResults = results;
            });
          },
          onDone: () {
            setState(() => _isScanning = false);
          },
          onError: (error) {
            setState(() => _isScanning = false);
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Scan error: $error')));
            }
          },
        );

    // Listen for scan status
    FlutterBluePlus.isScanning.listen((scanning) {
      if (mounted && !scanning && _isScanning) {
        setState(() => _isScanning = false);
      }
    });
  }

  void _stopScan() async {
    await _scanSubscription?.cancel();
    await _bluetoothService.stopScan();
    setState(() => _isScanning = false);
  }

  void _connectToDevice(BluetoothDevice device) {
    _stopScan();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DeviceScreen(device: device)),
    );
  }

  void _openBluetoothSettings() {
    if (Platform.isAndroid) {
      // Open Android Bluetooth settings
      openAppSettings();
    } else {
      // On iOS/macOS, show message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open System Preferences > Bluetooth')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('> BLE_DEVICES'),
            if (TestMode.isEnabled) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: TerminalColors.yellow,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'TEST',
                  style: TextStyle(
                    fontSize: 10,
                    color: TerminalColors.background,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.science,
              color: TestMode.isEnabled ? TerminalColors.yellow : null,
            ),
            onPressed: () {
              setState(() => TestMode.toggle());
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    TestMode.isEnabled
                        ? 'Test mode enabled - connect to "WhalePi Simulator"'
                        : 'Test mode disabled',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            tooltip: 'Toggle Test Mode',
          ),
          if (_isScanning)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: _stopScan,
              tooltip: 'Stop Scan',
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _isBluetoothOn || TestMode.isEnabled
                  ? _startScan
                  : null,
              tooltip: 'Scan for Devices',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isBluetoothOn ? _loadBondedDevices : null,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openBluetoothSettings,
            tooltip: 'Bluetooth Settings',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && !TestMode.isEnabled) {
      return const Center(child: CircularProgressIndicator());
    }

    // In test mode, show test device even if Bluetooth is off
    if (TestMode.isEnabled) {
      return _buildTestModeBody();
    }

    if (!_isBluetoothOn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.bluetooth_disabled,
              size: 64,
              color: TerminalColors.red,
            ),
            const SizedBox(height: 16),
            const Text(
              '[ERROR] Bluetooth disabled',
              style: TextStyle(
                fontSize: 16,
                fontFamily: 'monospace',
                color: TerminalColors.red,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _enableBluetooth,
              icon: const Icon(Icons.bluetooth),
              label: const Text('ENABLE'),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => setState(() => TestMode.enable()),
              icon: const Icon(Icons.science, size: 16),
              label: const Text(
                'Use Test Mode',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    if (_bondedDevices.isEmpty && _scanResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.bluetooth_searching,
              size: 64,
              color: TerminalColors.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              '> No devices found',
              style: TextStyle(fontSize: 16, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            const Text(
              '  Run scan to discover\n  nearby BLE devices...',
              textAlign: TextAlign.left,
              style: TextStyle(
                fontFamily: 'monospace',
                color: TerminalColors.grey,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _startScan,
              icon: const Icon(Icons.search),
              label: const Text('SCAN'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _loadBondedDevices();
        _startScan();
      },
      child: ListView(
        children: [
          if (_bondedDevices.isNotEmpty) ...[
            _buildSectionHeader('Paired Devices'),
            ..._bondedDevices.map((device) => _buildBondedDeviceTile(device)),
          ],
          if (_scanResults.isNotEmpty) ...[
            _buildSectionHeader('Discovered Devices'),
            ..._scanResults.map((result) => _buildScanResultTile(result)),
          ],
          if (_isScanning) ...[
            const SizedBox(height: 16),
            const Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text(
                    '> Scanning...',
                    style: TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      color: TerminalColors.surfaceLight,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        '# $title',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
          color: TerminalColors.cyan,
        ),
      ),
    );
  }

  Widget _buildBondedDeviceTile(BluetoothDevice device) {
    return ListTile(
      leading: const Text(
        '>',
        style: TextStyle(
          fontFamily: 'monospace',
          color: TerminalColors.primary,
        ),
      ),
      title: Text(
        device.platformName.isNotEmpty ? device.platformName : 'Unknown',
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      subtitle: Text(
        device.remoteId.str,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: TerminalColors.grey,
        ),
      ),
      trailing: const Text(
        '[PAIRED]',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          color: TerminalColors.cyan,
        ),
      ),
      onTap: () => _connectToDevice(device),
    );
  }

  Widget _buildScanResultTile(ScanResult result) {
    final device = result.device;
    final rssi = result.rssi;
    final advertisementName = result.advertisementData.advName;
    final displayName = advertisementName.isNotEmpty
        ? advertisementName
        : (device.platformName.isNotEmpty ? device.platformName : 'Unknown');

    return ListTile(
      leading: const Text(
        '>',
        style: TextStyle(
          fontFamily: 'monospace',
          color: TerminalColors.primary,
        ),
      ),
      title: Text(displayName, style: const TextStyle(fontFamily: 'monospace')),
      subtitle: Text(
        device.remoteId.str,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: TerminalColors.grey,
        ),
      ),
      trailing: Text(
        '${rssi}dBm',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: _getRssiColor(rssi),
        ),
      ),
      onTap: () => _connectToDevice(device),
    );
  }

  Color _getRssiColor(int rssi) {
    if (rssi >= -50) return TerminalColors.accent;
    if (rssi >= -70) return TerminalColors.yellow;
    return TerminalColors.red;
  }

  Widget _buildTestModeBody() {
    return ListView(
      children: [
        _buildSectionHeader('Test Mode'),
        _buildTestDeviceTile(),
        const SizedBox(height: 16),
        if (_isBluetoothOn &&
            (_bondedDevices.isNotEmpty || _scanResults.isNotEmpty)) ...[
          if (_bondedDevices.isNotEmpty) ...[
            _buildSectionHeader('Paired Devices'),
            ..._bondedDevices.map((device) => _buildBondedDeviceTile(device)),
          ],
          if (_scanResults.isNotEmpty) ...[
            _buildSectionHeader('Discovered Devices'),
            ..._scanResults.map((result) => _buildScanResultTile(result)),
          ],
        ],
      ],
    );
  }

  Widget _buildTestDeviceTile() {
    return ListTile(
      leading: const Icon(Icons.science, color: TerminalColors.yellow),
      title: const Text(
        'WhalePi Simulator',
        style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
      ),
      subtitle: const Text(
        'TEST-MODE-DEVICE',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: TerminalColors.grey,
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: TerminalColors.yellow),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'SIMULATOR',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: TerminalColors.yellow,
          ),
        ),
      ),
      onTap: _connectToTestDevice,
    );
  }

  void _connectToTestDevice() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            const DeviceScreen(device: null, isTestMode: true),
      ),
    );
  }
}
