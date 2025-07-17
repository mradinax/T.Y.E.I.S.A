import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// import 'package:http/http.dart' as http; // For DeepSeek API

class JarvisChatPage extends StatefulWidget {
  final String userName;
  final String assistantName;

  const JarvisChatPage({
    Key? key,
    required this.userName,
    required this.assistantName,
  }) : super(key: key);

  @override
  State<JarvisChatPage> createState() => _JarvisChatPageState();
}

class _JarvisChatPageState extends State<JarvisChatPage> {
  final List<Map<String, String>> _messages = [];
  final TextEditingController _controller = TextEditingController();
  bool _showWelcome = true;

  // Add TTS and STT instances
  final FlutterTts _flutterTts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _lastWords = '';
  bool _isConnecting = false;
  bool _isConnected = false;

  // Bluetooth
  BluetoothDevice? _connectedDevice;
  List<BluetoothDevice> _devicesList = [];
  StreamSubscription? _scanSubscription;

  @override
  void initState() {
    super.initState();
    // Delay welcome message slightly
    Future.delayed(const Duration(milliseconds: 500), () {
      setState(() {
        _showWelcome = true;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _flutterTts.stop();
    _scanSubscription?.cancel();
    super.dispose();
  }

  // Bluetooth connect function
  Future<void> _connectEarbuds() async {
    setState(() {
      _isConnecting = true;
      _devicesList.clear();
    });

    // Start scanning
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      for (var scanResult in results) {
        if (!_devicesList.any((d) => d.remoteId == scanResult.device.remoteId)) {
          setState(() {
            _devicesList.add(scanResult.device);
          });
        }
      }
    });

    // Wait for scan to finish
    await Future.delayed(const Duration(seconds: 5));
    await FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();

    // Show dialog to pick device
    BluetoothDevice? selected = await showDialog<BluetoothDevice>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select Earbuds'),
        children: _devicesList.isEmpty
            ? [const Padding(padding: EdgeInsets.all(16), child: Text('No devices found'))]
            : _devicesList.map((d) => SimpleDialogOption(
                child: Text(d.platformName.isNotEmpty ? d.platformName : d.remoteId.str),
                onPressed: () => Navigator.pop(context, d),
              )).toList(),
      ),
    );

    if (selected != null) {
      try {
        await selected.connect();
      } catch (e) {
        // Already connected
      }
      setState(() {
        _connectedDevice = selected;
        _isConnected = true;
        _isConnecting = false;
      });
      await _speak('Hey there, Jarvis here');
      _startListening();
    } else {
      setState(() {
        _isConnecting = false;
      });
    }
  }

  Future<void> _speak(String text) async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setPitch(1.0);
    await _flutterTts.speak(text);
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
      _showWelcome = false;
    });
    // TODO: Replace with actual DeepSeek API call
    String assistantReply = await _mockDeepSeekLLM(userText);
    setState(() {
      _messages.add({'role': 'assistant', 'text': assistantReply});
    });
    await _speak(assistantReply);
    // Optionally, start listening again for continuous conversation
    _lastWords = '';
    _startListening();
  }

  // Mock DeepSeek LLM call
  Future<String> _mockDeepSeekLLM(String prompt) async {
    await Future.delayed(const Duration(seconds: 2));
    return "This is Jarvis's response to: '$prompt'";
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _messages.add({'role': 'user', 'text': text});
        _controller.clear();
        _showWelcome = false;
      });
      // Handle assistant response here
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              // Navigate to settings screen
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Centered text and image in the middle of the screen
          Center(
            child: SizedBox(
              width: size.width,
              height: size.height * 1, // Adjust as needed for your design
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_showWelcome)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Hey ${widget.userName},\n${widget.assistantName} is here to help',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Image.asset(
                            'assets/jarvis.gif',
                            width: size.width * 1,
                            fit: BoxFit.contain,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Bottom: Start Speaking Button
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Center(
              child: SizedBox(
                width: size.width * 0.7,
                height: 54,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF2196F3), // Blue
                        Color(0xFF9C27B0), // Purple
                        Color(0xFFE040FB), // Pinkish
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _isConnecting || _isConnected
                        ? null
                        : () {
                            _connectEarbuds();
                          },
                    child: _isConnecting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            _isConnected ? 'Earbuds Connected' : 'Connect Earbuds',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
