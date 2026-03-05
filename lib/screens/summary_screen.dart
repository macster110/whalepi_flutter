import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../main.dart';
import '../models/pamguard_summary.dart';
import '../services/bluetooth_le_service.dart';
import '../services/mock_bluetooth_service.dart';

class SummaryScreen extends StatefulWidget {
  final BluetoothDevice? device;
  final BluetoothLeService? bluetoothService;
  final MockBluetoothService? mockService;
  final bool isTestMode;
  final Stream<PamGuardSummary> summaryStream;
  final PamGuardSummary? initialSummary;

  const SummaryScreen({
    super.key,
    this.device,
    this.bluetoothService,
    this.mockService,
    this.isTestMode = false,
    required this.summaryStream,
    this.initialSummary,
  });

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  PamGuardSummary? _summary;
  StreamSubscription<PamGuardSummary>? _summarySubscription;
  bool _isSending = false;
  DateTime? _lastUpdate;

  bool get _isConnected => widget.isTestMode
      ? (widget.mockService?.isConnected ?? false)
      : (widget.bluetoothService?.isConnected ?? false);

  @override
  void initState() {
    super.initState();
    _summary = widget.initialSummary;
    if (_summary != null) {
      _lastUpdate = DateTime.now();
    }
    _summarySubscription = widget.summaryStream.listen((summary) {
      setState(() {
        _summary = summary;
        _lastUpdate = DateTime.now();
      });
    });
  }

  @override
  void didUpdateWidget(covariant SummaryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If parent rebuilds with a newer initialSummary, pick it up
    if (widget.initialSummary != null && widget.initialSummary != _summary) {
      setState(() {
        _summary = widget.initialSummary;
        _lastUpdate = DateTime.now();
      });
    }
  }

  @override
  void dispose() {
    _summarySubscription?.cancel();
    super.dispose();
  }

  Future<void> _sendCommand(String command) async {
    if (_isSending || !_isConnected) return;

    setState(() => _isSending = true);
    if (widget.isTestMode) {
      await widget.mockService?.sendString(command);
    } else {
      await widget.bluetoothService?.sendString(command);
    }
    setState(() => _isSending = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: TerminalColors.background,
      child: Column(
        children: [
          // Status header
          _buildHeader(),

          // Main content
          Expanded(
            child: _summary == null
                ? _buildWaitingView()
                : _buildSummaryContent(),
          ),

          // Command buttons
          _buildCommandBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final deviceName = widget.isTestMode
        ? 'WhalePi Simulator'
        : (widget.device?.platformName.isNotEmpty == true
              ? widget.device!.platformName
              : 'WhalePi');
    final isConnected = _isConnected;
    final timeStr = _lastUpdate != null
        ? '${_lastUpdate!.hour.toString().padLeft(2, '0')}:${_lastUpdate!.minute.toString().padLeft(2, '0')}:${_lastUpdate!.second.toString().padLeft(2, '0')}'
        : '--:--:--';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TerminalColors.surface,
        border: Border(
          bottom: BorderSide(
            color: TerminalColors.primary.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.radio_button_checked,
            color: isConnected ? TerminalColors.accent : TerminalColors.grey,
            size: 14,
          ),
          const SizedBox(width: 8),
          Text(
            deviceName,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              color: TerminalColors.text,
            ),
          ),
          if (widget.isTestMode) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: TerminalColors.yellow,
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                'TEST',
                style: TextStyle(
                  fontSize: 8,
                  color: TerminalColors.background,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
          const Spacer(),
          Text(
            isConnected ? 'CONNECTED' : 'DISCONNECTED',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: isConnected ? TerminalColors.accent : TerminalColors.red,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'Last: $timeStr',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: TerminalColors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.sensors, size: 64, color: TerminalColors.primary),
          const SizedBox(height: 16),
          const Text(
            '> Waiting for data...',
            style: TextStyle(
              fontFamily: 'monospace',
              color: TerminalColors.textDim,
            ),
          ),
          const SizedBox(height: 24),
          _CommandButton(
            label: 'REQUEST SUMMARY',
            onPressed: () => _sendCommand('summary'),
            isLoading: _isSending,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryContent() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Sound Acquisition
        _SectionCard(
          title: 'Sound Acquisition',
          child: Column(
            children: [
              for (final ch in _summary!.audioChannels) ...[
                _AudioChannelRow(channel: ch),
                if (ch != _summary!.audioChannels.last)
                  const SizedBox(height: 8),
              ],
              if (_summary!.audioChannels.isEmpty)
                const Text(
                  'No audio data',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: TerminalColors.grey,
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Sound Recorder
        _SectionCard(
          title: 'Sound Recorder',
          child: _RecorderSection(recorder: _summary!.recorder),
        ),

        const SizedBox(height: 12),

        // GPS
        _SectionCard(
          title: 'GPS',
          child: _GpsSection(gps: _summary!.gps),
        ),

        const SizedBox(height: 12),

        // NMEA
        if (_summary!.nmeaSentence.isNotEmpty)
          _SectionCard(
            title: 'NMEA',
            child: Text(
              _summary!.nmeaSentence,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: TerminalColors.text,
              ),
            ),
          ),

        if (_summary!.nmeaSentence.isNotEmpty) const SizedBox(height: 12),

        // Analog Sensors
        if (_summary!.analogSensors.isNotEmpty)
          _SectionCard(
            title: 'Analog Sensors',
            child: Column(
              children: _summary!.analogSensors.map((sensor) {
                return _AnalogSensorRow(sensor: sensor);
              }).toList(),
            ),
          ),

        if (_summary!.analogSensors.isNotEmpty) const SizedBox(height: 12),

        // Pi Temperature
        _SectionCard(
          title: 'Pi Temperature',
          child: _TemperatureBar(temperature: _summary!.piTemperature),
        ),
      ],
    );
  }

  Widget _buildCommandBar() {
    final isConnected = _isConnected;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TerminalColors.surface,
        border: Border(
          top: BorderSide(color: TerminalColors.primary.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _CommandButton(
                  label: 'PING',
                  onPressed: isConnected ? () => _sendCommand('ping') : null,
                  isLoading: _isSending,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CommandButton(
                  label: 'STATUS',
                  onPressed: isConnected ? () => _sendCommand('status') : null,
                  isLoading: _isSending,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CommandButton(
                  label: 'SUMMARY',
                  onPressed: isConnected ? () => _sendCommand('summary') : null,
                  isLoading: _isSending,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _CommandButton(
                  label: 'START',
                  color: TerminalColors.accent,
                  onPressed: isConnected ? () => _sendCommand('start') : null,
                  isLoading: _isSending,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CommandButton(
                  label: 'STOP',
                  color: TerminalColors.red,
                  onPressed: isConnected ? () => _sendCommand('stop') : null,
                  isLoading: _isSending,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Command button widget
class _CommandButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color? color;

  const _CommandButton({
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final buttonColor = color ?? TerminalColors.primary;
    final isEnabled = onPressed != null && !isLoading;

    return GestureDetector(
      onTap: isEnabled ? onPressed : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isEnabled ? buttonColor : TerminalColors.grey,
          ),
          color: TerminalColors.background,
        ),
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: buttonColor,
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: isEnabled ? buttonColor : TerminalColors.grey,
                  ),
                ),
        ),
      ),
    );
  }
}

// Section card widget
class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: TerminalColors.primary.withValues(alpha: 0.4),
        ),
        color: TerminalColors.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: TerminalColors.primary.withValues(alpha: 0.4),
                ),
              ),
            ),
            child: Text(
              title,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: TerminalColors.primary,
                fontSize: 12,
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.all(12), child: child),
        ],
      ),
    );
  }
}

// Audio channel row
class _AudioChannelRow extends StatelessWidget {
  final ChannelData channel;

  const _AudioChannelRow({required this.channel});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildMeterRow(
          'Ch ${channel.index} RMS',
          channel.rmsdB,
          channel.rmsNormalized,
        ),
        const SizedBox(height: 4),
        _buildMeterRow(
          'Ch ${channel.index} Pk ',
          channel.peakdB,
          channel.peakNormalized,
          suffix: '[${channel.levelCategory}]',
        ),
      ],
    );
  }

  Widget _buildMeterRow(
    String label,
    double dB,
    double normalized, {
    String? suffix,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: TerminalColors.text,
            ),
          ),
        ),
        SizedBox(
          width: 60,
          child: Text(
            '${dB.toStringAsFixed(1)} dB',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: TerminalColors.textDim,
            ),
          ),
        ),
        Expanded(child: _ProgressBar(value: normalized)),
        if (suffix != null) ...[
          const SizedBox(width: 8),
          Text(
            suffix,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: _getLevelColor(suffix),
            ),
          ),
        ],
      ],
    );
  }

  Color _getLevelColor(String level) {
    if (level.contains('HIGH')) return TerminalColors.red;
    if (level.contains('MED')) return TerminalColors.yellow;
    return TerminalColors.accent;
  }
}

// Progress bar widget
class _ProgressBar extends StatelessWidget {
  final double value;
  final Color? color;

  const _ProgressBar({required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 12,
      decoration: BoxDecoration(
        border: Border.all(
          color: TerminalColors.primary.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(color: color ?? TerminalColors.primary),
      ),
    );
  }
}

// Recorder section
class _RecorderSection extends StatelessWidget {
  final RecorderSummary recorder;

  const _RecorderSection({required this.recorder});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'State: ',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: TerminalColors.grey,
              ),
            ),
            Icon(
              Icons.circle,
              size: 10,
              color: recorder.isRecording
                  ? TerminalColors.red
                  : TerminalColors.grey,
            ),
            const SizedBox(width: 4),
            Text(
              recorder.state.toUpperCase(),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: recorder.isRecording
                    ? TerminalColors.red
                    : TerminalColors.accent,
              ),
            ),
            const Spacer(),
            Text(
              'Button: ${recorder.button}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: TerminalColors.grey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'File size: ${recorder.fileSizeMB.toStringAsFixed(1)} MB  (${recorder.fileSizeGB.toStringAsFixed(3)} GB)',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: TerminalColors.text,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text(
              'Disk free: ',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: TerminalColors.grey,
              ),
            ),
            Expanded(
              child: _ProgressBar(
                value: 1.0 - recorder.diskUsageFraction,
                color: TerminalColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${recorder.freeSpaceGB.toStringAsFixed(1)} GB',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: TerminalColors.text,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// GPS section
class _GpsSection extends StatelessWidget {
  final GpsSummary gps;

  const _GpsSection({required this.gps});

  @override
  Widget build(BuildContext context) {
    final timeStr = gps.timestamp != null
        ? '${gps.timestamp!.year}-${gps.timestamp!.month.toString().padLeft(2, '0')}-${gps.timestamp!.day.toString().padLeft(2, '0')} ${gps.timestamp!.hour.toString().padLeft(2, '0')}:${gps.timestamp!.minute.toString().padLeft(2, '0')}:${gps.timestamp!.second.toString().padLeft(2, '0')}'
        : '--';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Status: ',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: TerminalColors.grey,
              ),
            ),
            Text(
              gps.status.toUpperCase(),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: gps.status.toLowerCase() == 'ok'
                    ? TerminalColors.accent
                    : TerminalColors.red,
              ),
            ),
            const SizedBox(width: 16),
            const Text(
              'Time: ',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: TerminalColors.grey,
              ),
            ),
            Expanded(
              child: Text(
                timeStr,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: TerminalColors.text,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text(
              'Lat: ',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: TerminalColors.grey,
              ),
            ),
            Text(
              gps.formattedLat,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: TerminalColors.text,
              ),
            ),
            const SizedBox(width: 16),
            const Text(
              'Lon: ',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: TerminalColors.grey,
              ),
            ),
            Text(
              gps.formattedLon,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: TerminalColors.text,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text(
              'Heading: ',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: TerminalColors.grey,
              ),
            ),
            Text(
              '${gps.headingDeg.toStringAsFixed(1)}° ${gps.headingCardinal}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: TerminalColors.text,
              ),
            ),
            const SizedBox(width: 8),
            _HeadingIndicator(heading: gps.headingDeg),
          ],
        ),
      ],
    );
  }
}

// Heading indicator
class _HeadingIndicator extends StatelessWidget {
  final double heading;

  const _HeadingIndicator({required this.heading});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: heading * 3.14159 / 180,
      child: const Icon(Icons.navigation, size: 20, color: TerminalColors.cyan),
    );
  }
}

// Analog sensor row
class _AnalogSensorRow extends StatelessWidget {
  final AnalogSensorData sensor;

  const _AnalogSensorRow({required this.sensor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            sensor.name,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: TerminalColors.grey,
            ),
          ),
        ),
        Text(
          'val: ${sensor.calibratedValue.toStringAsFixed(4)}',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: TerminalColors.text,
          ),
        ),
        const SizedBox(width: 16),
        Text(
          'V: ${sensor.voltage.toStringAsFixed(4)} V',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: TerminalColors.textDim,
          ),
        ),
      ],
    );
  }
}

// Temperature bar
class _TemperatureBar extends StatelessWidget {
  final double temperature;

  const _TemperatureBar({required this.temperature});

  @override
  Widget build(BuildContext context) {
    // Normalize to 0-1 (assuming 20-80°C range)
    final normalized = ((temperature - 20) / 60).clamp(0.0, 1.0);
    final color = temperature > 70
        ? TerminalColors.red
        : temperature > 50
        ? TerminalColors.yellow
        : TerminalColors.accent;

    return Row(
      children: [
        Expanded(
          child: _ProgressBar(value: normalized, color: color),
        ),
        const SizedBox(width: 12),
        Text(
          '${temperature.toStringAsFixed(1)} °C',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
