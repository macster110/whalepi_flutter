import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Callback types matching BluetoothLeService
typedef OnDataReceived = void Function(Uint8List data);
typedef OnConnectionStateChanged = void Function(bool connected);
typedef OnError = void Function(String error);

/// Mock Bluetooth service for testing without hardware
class MockBluetoothService {
  static final MockBluetoothService _instance =
      MockBluetoothService._internal();
  factory MockBluetoothService() => _instance;
  MockBluetoothService._internal();

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // Mock device state
  bool _isRecording = false;
  double _piTemperature = 45.0;
  double _fileSize = 0.0;
  double _freeSpace = 128000.0; // 128 GB in MB
  final Random _random = Random();

  // Callbacks
  OnDataReceived? onDataReceived;
  OnConnectionStateChanged? onConnectionStateChanged;
  OnError? onError;

  Timer? _dataSimulationTimer;

  Future<bool> get isSupported async => true;
  Future<bool> get isOn async => true;
  Future<void> turnOn() async {}

  /// Simulate "connecting" to the test device
  Future<bool> connect(BluetoothDevice device) async {
    // Simulate connection delay
    await Future.delayed(const Duration(milliseconds: 800));

    _isConnected = true;
    _isRecording = false;
    _fileSize = 0.0;
    onConnectionStateChanged?.call(true);

    // Start simulating periodic data changes if recording
    _startDataSimulation();

    return true;
  }

  Future<void> disconnect() async {
    _stopDataSimulation();
    _isConnected = false;
    _isRecording = false;
    onConnectionStateChanged?.call(false);
  }

  void dispose() {
    _stopDataSimulation();
    _isConnected = false;
  }

  void _startDataSimulation() {
    _dataSimulationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isRecording) {
        // Simulate file growing
        _fileSize += 0.5 + _random.nextDouble() * 0.5; // ~0.5-1 MB/sec
        _freeSpace -= 0.5 + _random.nextDouble() * 0.5;

        // Temperature fluctuation
        _piTemperature += (_random.nextDouble() - 0.5) * 0.5;
        _piTemperature = _piTemperature.clamp(40.0, 75.0);
      }
    });
  }

  void _stopDataSimulation() {
    _dataSimulationTimer?.cancel();
    _dataSimulationTimer = null;
  }

  /// Send command to mock device
  Future<bool> sendString(String data) async {
    if (!_isConnected) return false;

    final command = data.trim().toLowerCase();

    // Simulate processing delay
    await Future.delayed(Duration(milliseconds: 100 + _random.nextInt(200)));

    String response;
    switch (command) {
      case 'ping':
        response = 'pong';
        break;
      case 'status':
        response = _generateStatusResponse();
        break;
      case 'summary':
        response = _generateSummaryXml();
        break;
      case 'start':
        _isRecording = true;
        _fileSize = 0.0;
        response = 'Recording started';
        break;
      case 'stop':
        _isRecording = false;
        response = 'Recording stopped';
        break;
      default:
        response = 'Unknown command: $command';
    }

    // Simulate response
    _sendMockResponse(response);
    return true;
  }

  Future<bool> sendBytes(Uint8List data) async {
    return sendString(utf8.decode(data));
  }

  void _sendMockResponse(String response) {
    // Send response with slight delay to simulate real BLE
    Future.delayed(Duration(milliseconds: 50 + _random.nextInt(100)), () {
      onDataReceived?.call(Uint8List.fromList(utf8.encode(response)));
    });
  }

  String _generateStatusResponse() {
    return '''Status Report
=============
Recording: ${_isRecording ? 'YES' : 'NO'}
Temperature: ${_piTemperature.toStringAsFixed(1)}°C
Free Space: ${(_freeSpace / 1024).toStringAsFixed(1)} GB
File Size: ${_fileSize.toStringAsFixed(1)} MB
Uptime: ${DateTime.now().difference(DateTime.now().subtract(const Duration(hours: 2))).inMinutes} min
''';
  }

  String _generateSummaryXml() {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    // Generate realistic audio levels
    final ch0Rms = -60.0 + _random.nextDouble() * 30; // -60 to -30 dB
    final ch0Peak = ch0Rms + 6 + _random.nextDouble() * 10;
    final ch1Rms = -65.0 + _random.nextDouble() * 35;
    final ch1Peak = ch1Rms + 5 + _random.nextDouble() * 12;

    // GPS position (somewhere in the ocean)
    final lat = 34.0 + _random.nextDouble() * 0.01;
    final lon = -119.0 + _random.nextDouble() * 0.01;
    final heading = _random.nextDouble() * 360;

    return '''<?xml version="1.0" encoding="UTF-8"?>
<WhalePiSummary>
  <RawDataSummary>
    <channel index="0">
      <mean>${(_random.nextDouble() * 0.001).toStringAsFixed(6)}</mean>
      <peakdB>${ch0Peak.toStringAsFixed(1)}</peakdB>
      <rmsdB>${ch0Rms.toStringAsFixed(1)}</rmsdB>
    </channel>
    <channel index="1">
      <mean>${(_random.nextDouble() * 0.001).toStringAsFixed(6)}</mean>
      <peakdB>${ch1Peak.toStringAsFixed(1)}</peakdB>
      <rmsdB>${ch1Rms.toStringAsFixed(1)}</rmsdB>
    </channel>
  </RawDataSummary>
  <GPSSummary>
    <status>ok</status>
    <timestamp>${now.toIso8601String()}</timestamp>
    <latitude>$lat</latitude>
    <longitude>$lon</longitude>
    <headingDeg>$heading</headingDeg>
  </GPSSummary>
  <RecorderSummary>
    <button>${_isRecording ? 'ON' : 'OFF'}</button>
    <state>${_isRecording ? 'Recording' : 'Idle'}</state>
    <freeSpaceMB>${_freeSpace.toStringAsFixed(1)}</freeSpaceMB>
    <fileSizeMB>${_fileSize.toStringAsFixed(1)}</fileSizeMB>
    <channel index="0">${ch0Rms.toStringAsFixed(1)}</channel>
    <channel index="1">${ch1Rms.toStringAsFixed(1)}</channel>
  </RecorderSummary>
  <AnalogSensorsSummary>
    <Depth>
      <calVal>${(50.0 + _random.nextDouble() * 10).toStringAsFixed(4)}</calVal>
      <voltage>${(2.5 + _random.nextDouble() * 0.1).toStringAsFixed(4)}</voltage>
    </Depth>
  </AnalogSensorsSummary>
  <NMEA Data>GPS:\$GPRMC,$timeStr,A,${lat.toStringAsFixed(4)},N,${lon.abs().toStringAsFixed(4)},W,0.0,${heading.toStringAsFixed(1)},${now.day.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.year % 100},,,A*00<\\NMEA Data>
  temp=${_piTemperature.toStringAsFixed(1)}
</WhalePiSummary>''';
  }
}

/// Static flag to enable test mode globally
class TestMode {
  static bool _enabled = false;

  static bool get isEnabled => _enabled;

  static void enable() {
    _enabled = true;
  }

  static void disable() {
    _enabled = false;
  }

  static void toggle() {
    _enabled = !_enabled;
  }
}
