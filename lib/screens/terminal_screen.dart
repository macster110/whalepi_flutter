import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../main.dart';
import '../models/message.dart';
import '../services/bluetooth_le_service.dart';

enum LineEnding {
  none('None', ''),
  lf('LF', '\n'),
  cr('CR', '\r'),
  crlf('CR+LF', '\r\n');

  final String label;
  final String value;
  const LineEnding(this.label, this.value);
}

class TerminalScreen extends StatefulWidget {
  final BluetoothDevice device;

  const TerminalScreen({super.key, required this.device});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final BluetoothLeService _bluetoothService = BluetoothLeService();
  final TextEditingController _sendController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _sendFocusNode = FocusNode();

  final List<Message> _messages = [];

  bool _isConnecting = true;
  bool _isConnected = false;
  bool _hexMode = false;
  LineEnding _lineEnding = LineEnding.crlf;

  // Buffer for receiving fragmented data
  final StringBuffer _receiveBuffer = StringBuffer();

  @override
  void initState() {
    super.initState();
    _setupCallbacks();
    _connect();
  }

  @override
  void dispose() {
    _sendController.dispose();
    _scrollController.dispose();
    _sendFocusNode.dispose();
    _bluetoothService.disconnect();
    super.dispose();
  }

  void _setupCallbacks() {
    _bluetoothService.onDataReceived = _onDataReceived;
    _bluetoothService.onConnectionStateChanged = (connected) {
      if (mounted) {
        setState(() => _isConnected = connected);
        if (!connected && !_isConnecting) {
          _addMessage(Message.status('Disconnected'));
        }
      }
    };
    _bluetoothService.onError = (error) {
      if (mounted) {
        _addMessage(Message.error(error));
      }
    };
  }

  Future<void> _connect() async {
    setState(() {
      _isConnecting = true;
      _messages.clear();
    });

    final deviceName = widget.device.platformName.isNotEmpty
        ? widget.device.platformName
        : widget.device.remoteId.str;
    _addMessage(Message.status('Connecting to $deviceName...'));

    final success = await _bluetoothService.connect(widget.device);

    if (mounted) {
      setState(() => _isConnecting = false);

      if (success) {
        _addMessage(Message.status('Connected'));
      } else {
        _addMessage(Message.error('Failed to connect'));
      }
    }
  }

  void _onDataReceived(Uint8List data) {
    if (_hexMode) {
      final hexString = BluetoothLeService.bytesToHex(data);
      _addMessage(Message.received(hexString, rawData: data));
    } else {
      // Decode and handle text data
      final text = utf8.decode(data, allowMalformed: true);
      _receiveBuffer.write(text);

      // Process complete lines or flush after a short delay
      _processReceivedText();
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
      success = await _bluetoothService.sendBytes(bytes);
      displayText = BluetoothLeService.bytesToHex(bytes);
    } else {
      // Send as text with line ending
      success = await _bluetoothService.sendString(
        text,
        lineEnding: _lineEnding.value,
      );
      displayText = text;
    }

    if (success) {
      _addMessage(Message.sent(displayText));
      _sendController.clear();
    }
  }

  void _disconnect() {
    _bluetoothService.disconnect();
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
          style: TextStyle(
            fontFamily: 'monospace',
            color: TerminalColors.green,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: LineEnding.values.map((ending) {
            final isSelected = ending == _lineEnding;
            return ListTile(
              leading: Text(
                isSelected ? '[*]' : '[ ]',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: TerminalColors.green,
                ),
              ),
              title: Text(
                ending.label,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: TerminalColors.green,
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
    final deviceName = widget.device.platformName.isNotEmpty
        ? widget.device.platformName
        : 'Terminal';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '> $deviceName',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
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
        actions: [
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
                    Icon(Icons.refresh, color: TerminalColors.green),
                    SizedBox(width: 8),
                    Text(
                      'Reconnect',
                      style: TextStyle(fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'disconnect',
                child: Row(
                  children: [
                    Icon(Icons.close, color: TerminalColors.red),
                    SizedBox(width: 8),
                    Text(
                      'Disconnect',
                      style: TextStyle(fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages area
          Expanded(child: _buildMessageList()),
          // Input area
          _buildInputArea(),
        ],
      ),
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
              color: TerminalColors.greenDim,
            ),
            const SizedBox(height: 16),
            Text(
              _isConnecting ? '> Connecting...' : '> Waiting for data...',
              style: const TextStyle(
                fontFamily: 'monospace',
                color: TerminalColors.greenDim,
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
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(8),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          return _buildMessageItem(_messages[index]);
        },
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
        textColor = TerminalColors.green;
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
      decoration: const BoxDecoration(
        color: TerminalColors.surface,
        border: Border(
          top: BorderSide(color: TerminalColors.greenDim, width: 1),
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
                    ? TerminalColors.green
                    : TerminalColors.grey,
              ),
            ),
            Expanded(
              child: TextField(
                controller: _sendController,
                focusNode: _sendFocusNode,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: TerminalColors.green,
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
                cursorColor: TerminalColors.green,
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
                        ? TerminalColors.green
                        : TerminalColors.grey,
                  ),
                ),
                child: Text(
                  'SEND',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: _isConnected
                        ? TerminalColors.green
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
