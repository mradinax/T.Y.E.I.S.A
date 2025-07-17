import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:activatejarvis/secrets/api_keys.dart';

class VoiceChatPage extends StatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onSettings;

  const VoiceChatPage({Key? key, this.onBack, this.onSettings}) : super(key: key);

  static const MethodChannel _audioChannel = MethodChannel('activatejarvis/audio');

  static Future<bool> isBluetoothAudioConnected() async {
    try {
      final bool result = await _audioChannel.invokeMethod('isBluetoothAudioConnected');
      return result;
    } catch (e) {
      return false;
    }
  }

  @override
  State<VoiceChatPage> createState() => _VoiceChatPageState();
}

class _VoiceChatPageState extends State<VoiceChatPage> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  bool _isListening = false;
  String _lastWords = '';
  List<Map<String, String>> _messages = [];
  BluetoothDevice? _connectedDevice;

  @override
  void initState() {
    super.initState();
    _startListening();
    _findConnectedBluetoothDevice();
  }

  Future<void> _findConnectedBluetoothDevice() async {
    List<BluetoothDevice> connectedDevices = await FlutterBluePlus.connectedDevices;
    if (connectedDevices.isNotEmpty) {
      setState(() {
        _connectedDevice = connectedDevices.first;
      });
    }
  }

  void _startListening() async {
    bool available = await _speech.initialize(
      onStatus: (val) {
        if (val == 'done' || val == 'notListening') {
          setState(() => _isListening = false);
          if (_lastWords.isNotEmpty) {
            _handleUserSpeech(_lastWords);
          }
        }
      },
      onError: (val) {
        setState(() => _isListening = false);
      },
    );
    if (available) {
      setState(() => _isListening = true);
      _speech.listen(
        onResult: (val) {
          setState(() {
            _lastWords = val.recognizedWords;
          });
        },
      );
    }
  }

  Future<void> _handleUserSpeech(String userText) async {
    setState(() {
      _messages.add({'role': 'user', 'text': userText});
    });
    String assistantReply;
    try {
      assistantReply = await _callGptApi(userText);
    } catch (e) {
      assistantReply = 'Sorry, I could not process your request.\nError: '
        + e.toString();
    }
    setState(() {
      _messages.add({'role': 'assistant', 'text': assistantReply});
    });
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setPitch(1.0);
    await _flutterTts.speak(assistantReply);
    if (_connectedDevice != null) {
      // Send the GPT response as text via Bluetooth (if supported by the device)
      // This is a placeholder: actual sending depends on the device's services/characteristics
      // await _sendTextViaBluetooth(assistantReply);
    }
    _lastWords = '';
    _startListening(); // Always restart listening, even on error
  }

  Future<String> _callGptApi(String prompt) async {
    final url = Uri.parse('https://api.openai.com/v1/chat/completions');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $openAIApiKey',
    };
    final body = jsonEncode({
      'model': 'gpt-3.5-turbo',
      'messages': [
        {'role': 'system', 'content': 'You are Jarvis, a helpful assistant.'},
        ..._messages.map((m) => {'role': m['role'], 'content': m['text']}),
        {'role': 'user', 'content': prompt},
      ],
      'max_tokens': 150,
    });
    try {
      final response = await http.post(url, headers: headers, body: body);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'].trim();
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      throw Exception('Network/API error: $e');
    }
  }

  // Placeholder for sending text via Bluetooth
  // Future<void> _sendTextViaBluetooth(String text) async {
  //   // Implement based on your device's Bluetooth service/characteristic
  // }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: widget.onSettings ?? () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: false,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['role'] == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.blueAccent : Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      msg['text'] ?? '',
                      style: TextStyle(
                        color: isUser ? Colors.white : Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Image.asset(
                  'assets/jarvis.gif',
                  width: size.width * 0.6,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 16),
                Text(
                  _isListening ? 'Listening...' : 'Start Speaking',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
} 