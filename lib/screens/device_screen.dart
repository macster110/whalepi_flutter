import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../main.dart';
import '../models/message.dart';
import '../models/pamguard_summary.dart';
import '../services/bluetooth_le_service.dart';
import '../services/mock_bluetooth_service.dart';
import 'summary_screen.dart';

enum LineEnding {
  none('None', ''),
  lf('LF', '\n'),
  cr('CR', '\r'),
  crlf('CR+LF', '\r\n');

  final String label;
  final String value;
  const LineEnding(this.label, this.value);
}

/// Main device screen with tabs for Summary and Terminal views
class DeviceScreen extends StatefulWidget {
  final BluetoothDevice? device;
  final bool isTestMode;

  const DeviceScreen({super.key, this.device, this.isTestMode = false});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  late final BluetoothLeService? _bluetoothService;
  late final MockBluetoothService? _mockService;

  final TextEditingController _sendController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _sendFocusNode = FocusNode();

  final List<Message> _messages = [];
  final StreamController<PamGuardSummary> _summaryController =
      StreamController<PamGuardSummary>.broadcast();
  PamGuardSummary? _lastSummary;
  final GlobalKey<State<SummaryScreen>> _summaryKey = GlobalKey();

  bool _isConnecting = true;
  bool _isConnected = false;
  bool _hexMode = false;
  LineEnding _lineEnding = LineEnding.crlf;
  int _currentTab = 0;

  // Buffer for receiving fragmented data
  final StringBuffer _receiveBuffer = StringBuffer();
  // Buffer for accumulating data for summary parsing
  final StringBuffer _dataBuffer = StringBuffer();
  // Debounce timer for summary parsing
  Timer? _summaryDebounce;

  bool get _isTestMode => widget.isTestMode;

  @override
  void initState() {
    super.initState();

    if (_isTestMode) {
      _mockService = MockBluetoothService();
      _bluetoothService = null;
    } else {
      _bluetoothService = BluetoothLeService();
      _mockService = null;
    }

    _setupCallbacks();
    _connect();
  }

  @override
  void dispose() {
    _sendController.dispose();
    _scrollController.dispose();
    _sendFocusNode.dispose();
    _summaryController.close();
    _summaryDebounce?.cancel();
    if (_isTestMode) {
      _mockService?.disconnect();
    } else {
      _bluetoothService?.disconnect();
    }
    super.dispose();
  }

  void _setupCallbacks() {
    if (_isTestMode) {
      _mockService?.onDataReceived = _onDataReceived;
      _mockService?.onConnectionStateChanged = (connected) {
        if (mounted) {
          setState(() => _isConnected = connected);
          if (!connected && !_isConnecting) {
            _addMessage(Message.status('Disconnected'));
          }
        }
      };
      _mockService?.onError = (error) {
        _addMessage(Message.error(error));
      };
    } else {
      _bluetoothService?.onDataReceived = _onDataReceived;
      _bluetoothService?.onConnectionStateChanged = (connected) {
        if (mounted) {
          setState(() => _isConnected = connected);
          if (!connected && !_isConnecting) {
            _addMessage(Message.status('Disconnected'));
          }
        }
      };
      _bluetoothService?.onError = (error) {
        if (mounted) {
          _addMessage(Message.error(error));
        }
      };
      _bluetoothService?.onLog = (message) {
        if (mounted) {
          _addMessage(Message.status('[BLE] $message'));
        }
      };
    }
  }

  Future<void> _connect() async {
    setState(() {
      _isConnecting = true;
      _messages.clear();
    });

    final deviceName = _isTestMode
        ? 'WhalePi Simulator'
        : (widget.device!.platformName.isNotEmpty
              ? widget.device!.platformName
              : widget.device!.remoteId.str);
    _addMessage(Message.status('Connecting to $deviceName...'));

    bool success;
    if (_isTestMode) {
      // Fake device for mock service
      success = await _mockService!.connect(
        BluetoothDevice.fromId('TEST-DEVICE'),
      );
    } else {
      success = await _bluetoothService!.connect(widget.device!);
    }

    if (mounted) {
      setState(() => _isConnecting = false);

      if (success) {
        _addMessage(Message.status('Connected'));
        if (_isTestMode) {
          _addMessage(
            Message.status(
              'Test mode active - try: ping, status, summary, start, stop',
            ),
          );
        }
      } else {
        _addMessage(Message.error('Failed to connect'));
      }
    }
  }

  void _onDataReceived(Uint8List data) {
    final text = utf8.decode(data, allowMalformed: true);

    // Accumulate data for summary parsing
    _dataBuffer.write(text);

    // Debounce summary parsing — wait for all chunks to arrive
    _summaryDebounce?.cancel();
    _summaryDebounce = Timer(const Duration(milliseconds: 500), () {
      _tryParseSummary();
    });

    if (_hexMode) {
      final hexString = BluetoothLeService.bytesToHex(data);
      _addMessage(Message.received(hexString, rawData: data));
    } else {
      // Decode and handle text data for terminal
      _receiveBuffer.write(text);
      _processReceivedText();
    }
  }

  void _tryParseSummary() {
    final data = _dataBuffer.toString();

    // Check if we have complete summary data (contains key markers)
    if (data.contains('<RawDataSummary>') ||
        data.contains('<GPSSummary>') ||
        data.contains('<RecorderSummary>')) {
      final summary = PamGuardSummary.parse(data);
      if (summary != null) {
        _lastSummary = summary;
        _summaryController.add(summary);
      }

      // Clear buffer after processing (keep last bit in case of partial data)
      if (data.contains('</')) {
        _dataBuffer.clear();
      }
    }

    // Prevent buffer from growing too large
    if (_dataBuffer.length > 10000) {
      final trimmed = _dataBuffer.toString().substring(
        _dataBuffer.length - 5000,
      );
      _dataBuffer.clear();
      _dataBuffer.write(trimmed);
    }
  }

  void _processReceivedText() {
    final buffer = _receiveBuffer.toString();

    // Split by common line endings
    final lines = buffer.split(RegExp(r'\r\n|\n|\r'));

    // Add complete lines as messages
    for (int i = 0; i < lines.length - 1; i++) {
      if (lines[i].isNotEmpty) {
        _addMessage(Message.received(lines[i]));
      }
    }

    // Keep the last incomplete line in the buffer
    _receiveBuffer.clear();
    if (lines.isNotEmpty) {
      _receiveBuffer.write(lines.last);
    }

    // Flush remaining buffer after a delay if no newline received
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_receiveBuffer.isNotEmpty && mounted) {
        _addMessage(Message.received(_receiveBuffer.toString()));
        _receiveBuffer.clear();
      }
    });
  }

  void _addMessage(Message message) {
    setState(() {
      _messages.add(message);
    });

    // Auto-scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _sendController.text.trim();
    if (text.isEmpty) return;

    if (!_isConnected) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Not connected')));
      return;
    }

    bool success;
    String displayText;

    if (_hexMode) {
      // Send as hex bytes
      final bytes = BluetoothLeService.hexToBytes(text);
      if (_isTestMode) {
        success = await _mockService!.sendBytes(bytes);
      } else {
        success = await _bluetoothService!.sendBytes(bytes);
      }
      displayText = BluetoothLeService.bytesToHex(bytes);
    } else {
      // Send as text with line ending
      final textWithEnding = text + _lineEnding.value;
      if (_isTestMode) {
        success = await _mockService!.sendString(textWithEnding);
      } else {
        success = await _bluetoothService!.sendString(
          text,
          lineEnding: _lineEnding.value,
        );
      }
      displayText = text;
    }

    if (success) {
      _addMessage(Message.sent(displayText));
      _sendController.clear();
    }
  }

  void _disconnect() {
    if (_isTestMode) {
      _mockService?.disconnect();
    } else {
      _bluetoothService?.disconnect();
    }
    Navigator.pop(context);
  }

  void _clearMessages() {
    setState(() {
      _messages.clear();
    });
    _addMessage(Message.status('Cleared'));
  }

  void _showLineEndingDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TerminalColors.surface,
        title: const Text(
          '> Line Ending',
          style: TextStyle(fontFamily: 'monospace', color: TerminalColors.text),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: LineEnding.values.map((ending) {
            final isSelected = ending == _lineEnding;
            return ListTile(
              leading: Text(
                isSelected ? '[*]' : '[ ]',
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: isSelected
                      ? TerminalColors.primary
                      : TerminalColors.textDim,
                ),
              ),
              title: Text(
                ending.label,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: TerminalColors.text,
                ),
              ),
              onTap: () {
                setState(() => _lineEnding = ending);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deviceName = _isTestMode
        ? 'WhalePi Simulator'
        : (widget.device!.platformName.isNotEmpty
              ? widget.device!.platformName
              : 'WhalePi');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '> $deviceName',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                ),
                if (_isTestMode) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
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
              ],
            ),
            Text(
              _isConnecting
                  ? '[CONNECTING...]'
                  : _isConnected
                  ? '[CONNECTED]'
                  : '[DISCONNECTED]',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: _isConnected ? TerminalColors.green : TerminalColors.red,
              ),
            ),
          ],
        ),
        actions: _currentTab == 1 ? _buildTerminalActions() : null,
      ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          // Summary tab
          SummaryScreen(
            key: _summaryKey,
            device: widget.device,
            bluetoothService: _bluetoothService,
            mockService: _mockService,
            isTestMode: _isTestMode,
            summaryStream: _summaryController.stream,
            initialSummary: _lastSummary,
          ),
          // Terminal tab
          _buildTerminalView(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  void _copyAllMessages() {
    final text = _messages
        .map((m) {
          String prefix;
          switch (m.type) {
            case MessageType.sent:
              prefix = '< ';
              break;
            case MessageType.received:
              prefix = '> ';
              break;
            case MessageType.status:
              prefix = '# ';
              break;
            case MessageType.error:
              prefix = '! ';
              break;
          }
          return '${m.formattedTime} $prefix${m.text}';
        })
        .join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Terminal output copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  List<Widget> _buildTerminalActions() {
    return [
      IconButton(
        icon: const Icon(Icons.copy),
        onPressed: _messages.isNotEmpty ? _copyAllMessages : null,
        tooltip: 'Copy All',
      ),
      IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: _clearMessages,
        tooltip: 'Clear',
      ),
      IconButton(
        icon: const Icon(Icons.wrap_text),
        onPressed: _showLineEndingDialog,
        tooltip: 'Line Ending: ${_lineEnding.label}',
      ),
      IconButton(
        icon: Icon(_hexMode ? Icons.text_fields : Icons.hexagon_outlined),
        onPressed: () {
          setState(() => _hexMode = !_hexMode);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_hexMode ? '> HEX mode' : '> TEXT mode'),
              duration: const Duration(seconds: 1),
            ),
          );
        },
        tooltip: _hexMode ? 'Switch to Text mode' : 'Switch to HEX mode',
      ),
      PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'reconnect':
              _connect();
              break;
            case 'disconnect':
              _disconnect();
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'reconnect',
            child: Row(
              children: [
                Icon(Icons.refresh, color: TerminalColors.primary),
                SizedBox(width: 8),
                Text('Reconnect', style: TextStyle(fontFamily: 'monospace')),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'disconnect',
            child: Row(
              children: [
                Icon(Icons.close, color: TerminalColors.red),
                SizedBox(width: 8),
                Text('Disconnect', style: TextStyle(fontFamily: 'monospace')),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: TerminalColors.surface,
        border: Border(
          top: BorderSide(color: TerminalColors.primary.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: _NavTab(
                icon: Icons.dashboard,
                label: 'SUMMARY',
                isSelected: _currentTab == 0,
                onTap: () => setState(() => _currentTab = 0),
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: TerminalColors.primary.withValues(alpha: 0.5),
            ),
            Expanded(
              child: _NavTab(
                icon: Icons.terminal,
                label: 'TERMINAL',
                isSelected: _currentTab == 1,
                onTap: () => setState(() => _currentTab = 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTerminalView() {
    return Column(
      children: [
        Expanded(child: _buildMessageList()),
        _buildInputArea(),
      ],
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isConnecting ? Icons.bluetooth_searching : Icons.terminal,
              size: 64,
              color: TerminalColors.primary,
            ),
            const SizedBox(height: 16),
            Text(
              _isConnecting ? '> Connecting...' : '> Waiting for data...',
              style: const TextStyle(
                fontFamily: 'monospace',
                color: TerminalColors.textDim,
                fontSize: 14,
              ),
            ),
            if (!_isConnecting && !_isConnected) ...[
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _connect,
                child: const Text('RECONNECT'),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      color: TerminalColors.background,
      child: SelectionArea(
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(8),
          itemCount: _messages.length,
          itemBuilder: (context, index) {
            return _buildMessageItem(_messages[index]);
          },
        ),
      ),
    );
  }

  Widget _buildMessageItem(Message message) {
    String prefix;
    Color textColor;

    switch (message.type) {
      case MessageType.sent:
        prefix = '< ';
        textColor = TerminalColors.cyan;
        break;
      case MessageType.received:
        prefix = '> ';
        textColor = TerminalColors.text;
        break;
      case MessageType.status:
        prefix = '# ';
        textColor = TerminalColors.yellow;
        break;
      case MessageType.error:
        prefix = '! ';
        textColor = TerminalColors.red;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prefix,
            style: TextStyle(
              fontFamily: 'monospace',
              color: textColor,
              fontSize: 14,
            ),
          ),
          Expanded(
            child: Text(
              message.text,
              style: TextStyle(
                fontFamily: 'monospace',
                color: textColor,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            message.formattedTime,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: TerminalColors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      decoration: BoxDecoration(
        color: TerminalColors.surface,
        border: Border(
          top: BorderSide(
            color: TerminalColors.primary.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: SafeArea(
        child: Row(
          children: [
            Text(
              _isConnected ? '\$ ' : '# ',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                color: _isConnected
                    ? TerminalColors.primary
                    : TerminalColors.grey,
              ),
            ),
            Expanded(
              child: TextField(
                controller: _sendController,
                focusNode: _sendFocusNode,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: TerminalColors.text,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: _hexMode
                      ? 'HEX: 48 65 6C 6C 6F'
                      : 'Enter command...',
                  hintStyle: const TextStyle(
                    fontFamily: 'monospace',
                    color: TerminalColors.grey,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                enabled: _isConnected,
                cursorColor: TerminalColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _isConnected ? _send : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _isConnected
                        ? TerminalColors.primary
                        : TerminalColors.grey,
                  ),
                ),
                child: Text(
                  'SEND',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: _isConnected
                        ? TerminalColors.primary
                        : TerminalColors.grey,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Navigation tab widget
class _NavTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavTab({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? TerminalColors.primary : TerminalColors.grey,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? TerminalColors.primary
                    : TerminalColors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
