import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:siri_wave/siri_wave.dart';
// Removed: import 'package:activatejarvis/secrets/api_keys.dart';

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
  static const String _geminiApiKey = 'AIzaSyDAewJYdhHUFOZg9CnuDPYoASR_l2gbOBk';
  bool _processingSpeech = false;
  bool _hasGreeted = false;
  
  // Wake word and Bluetooth features
  String _assistantName = "jarvis";  // Default assistant name
  bool _isBluetoothConnected = false;

  @override
  void initState() {
    super.initState();
    _initializeTTS();
    _checkBluetoothConnection();
    _findConnectedBluetoothDevice();
    _startListening();
    // Periodically check Bluetooth connection
    _startBluetoothMonitoring();
  }

  void _startBluetoothMonitoring() {
    // Check Bluetooth connection every 10 seconds
    Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        _checkBluetoothConnection();
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _initializeTTS() async {
    // Check Bluetooth connection and configure TTS accordingly
    bool bluetoothConnected = await VoiceChatPage.isBluetoothAudioConnected();
    setState(() {
      _isBluetoothConnected = bluetoothConnected;
    });
    
    if (!bluetoothConnected) {
      // Configure TTS for phone speaker
      await _flutterTts.setSpeechRate(0.4);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(0.8);
      await _flutterTts.setLanguage('en-US');
    }
  }

  Future<void> _checkBluetoothConnection() async {
    bool connected = await VoiceChatPage.isBluetoothAudioConnected();
    setState(() {
      _isBluetoothConnected = connected;
    });
  }

  String _processWakeWords(String text) {
    // Remove common punctuation and normalize text
    String normalizedText = text.replaceAll(RegExp(r'[.,!?]'), '').trim();
    
    // Check for wake word patterns
    List<String> wakePatterns = [
      'activate $_assistantName',
      'activate$_assistantName',
      '$_assistantName',
      'hey $_assistantName',
      'ok $_assistantName',
    ];
    
    for (String pattern in wakePatterns) {
      if (normalizedText.startsWith(pattern)) {
        // Remove the wake word and return the command
        String command = normalizedText.substring(pattern.length).trim();
        if (command.isEmpty && normalizedText == pattern) {
          // Just the wake word, return a generic greeting trigger
          return "hello";
        }
        return command.isEmpty ? "hello" : command;
      }
    }
    
    // If no wake word found, return empty string
    return '';
  }

  Future<void> _configureTTSOutput() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setPitch(0.8);
    
    if (_isBluetoothConnected) {
      // Configure for Bluetooth audio
      await _flutterTts.setSpeechRate(0.4);
      await _flutterTts.setVolume(0.8);
      print('TTS configured for Bluetooth output');
    } else {
      // Configure for phone speaker
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      print('TTS configured for phone speaker output');
    }
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
      onStatus: (val) async {
        if (val == 'done' || val == 'notListening') {
          setState(() => _isListening = false);
          if (_lastWords.isNotEmpty && !_processingSpeech) {
            _processingSpeech = true;
            await _handleUserSpeech(_lastWords);
            _processingSpeech = false;
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
    // Check for wake word patterns first
    String processedText = _processWakeWords(userText.toLowerCase());
    
    // If no wake word detected and text doesn't start with assistant name, ignore
    if (processedText.isEmpty) {
      print('No wake word detected, ignoring: $userText');
      return;
    }
    
    setState(() {
      _messages.add({'role': 'user', 'text': processedText});
    });
    String assistantReply;
    try {
      assistantReply = await _callGeminiApi(processedText, isFirst: !_hasGreeted);
    } catch (e) {
      assistantReply = 'Sorry, I could not process your request.\nError: '
        + e.toString();
    }
    if (!_hasGreeted) {
      _hasGreeted = true;
    }
    setState(() {
      _messages.add({'role': 'assistant', 'text': assistantReply});
    });
    
    // Configure TTS based on Bluetooth connection
    await _configureTTSOutput();
    
    // Always stop listening before TTS
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    }
    // Set TTS completion handler to restart listening
    _flutterTts.setCompletionHandler(() async {
      await Future.delayed(const Duration(milliseconds: 200)); // Small delay for stability
      _startListening();
    });
    await _flutterTts.speak(assistantReply);
    if (_connectedDevice != null) {
      // Send the response as text via Bluetooth (if supported by the device)
      // This is a placeholder: actual sending depends on the device's services/characteristics
      // await _sendTextViaBluetooth(assistantReply);
    }
    _lastWords = '';
    // Do not call _startListening() here; it will be called after TTS completes
  }

  Future<String> _callGeminiApi(String prompt, {bool isFirst = false}) async {
    final url = Uri.parse('https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash-001:generateContent?key=$_geminiApiKey');
    final headers = {
      'Content-Type': 'application/json',
    };
    final String systemPrompt = isFirst
        ? "You are Jarvis, Tony Stark's AI. You speak casually, confidently, and with personality. The first time you respond in a session, start with 'Hey boss' or something similar. After that, skip greetings and just reply directly. Never repeat the same intro. Be witty and natural. Reply in only one short sentence."
        : "You are Jarvis, Tony Stark's AI. You speak casually, confidently, and with personality. Do not greet or introduce yourself, just reply directly. Never repeat the same intro. Be witty and natural. Reply in only one short sentence.";
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': systemPrompt},
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'maxOutputTokens': 15
      }
    });
    try {
      final response = await http.post(url, headers: headers, body: body);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Gemini's response structure
        final candidates = data['candidates'];
        if (candidates != null && candidates.length > 0) {
          final content = candidates[0]['content'];
          if (content != null && content['parts'] != null && content['parts'].length > 0) {
            return content['parts'][0]['text']?.trim() ?? '';
          }
        }
        return 'No response from Gemini.';
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
                GestureDetector(
                  onTap: _startListening,
                  child: Container(
                    width: size.width,
                    height: 120,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(60),
                      gradient: LinearGradient(
                        colors: [
                          Colors.blue.withOpacity(0.1),
                          Colors.purple.withOpacity(0.1),
                        ],
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: size.width,
                        height: 80,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(40),
                          color: Colors.black.withOpacity(0.8),
                        ),
                        child: SiriWaveform.ios9(
                          options: IOS9SiriWaveformOptions(
                            height: 80,
                            showSupportBar: _isListening,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _isListening ? 'Listening...' : 'Say "Activate Jarvis" or "Jarvis [command]"',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _isBluetoothConnected ? '🎧 Bluetooth Connected' : '📱 Phone Speaker',
                  style: TextStyle(
                    color: _isBluetoothConnected ? Colors.blue : Colors.grey,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _speech.stop();
    _flutterTts.stop();
    super.dispose();
  }
} 