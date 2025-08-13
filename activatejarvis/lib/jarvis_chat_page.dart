import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
// import 'package:vosk_flutter/vosk_flutter.dart'; // Temporarily disabled
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:audioplayers/audioplayers.dart';
// import 'package:http/http.dart' as http; // For DeepSeek API
import 'package:activatejarvis/voice_chat_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

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

  // Add TTS instances (Vosk removed for now - use VoiceChatPage for speech)
  final FlutterTts _flutterTts = FlutterTts();
  // VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  // Model? _model;
  // Recognizer? _recognizer;
  // SpeechService? _speechService;
  final AudioPlayer _audioPlayer = AudioPlayer();
  // bool _isListening = false;
  String _lastWords = '';
  bool _isConnecting = false;
  bool _isConnected = false;

  // Bluetooth
  BluetoothDevice? _connectedDevice;
  List<BluetoothDevice> _devicesList = [];
  StreamSubscription? _scanSubscription;

  // Welcome animation variables
  bool _isFirstTime = true;
  bool _isShowingWelcomeAnimation = false;
  String _currentWelcomeText = "";
  Timer? _welcomeTextTimer;
  List<String> _welcomeMessages = [];

  @override
  void initState() {
    super.initState();
    _checkFirstTimeUser();
    // Delay welcome message slightly
    Future.delayed(const Duration(milliseconds: 500), () {
      setState(() {
        _showWelcome = true;
      });
    });
  }

  // Check if this is the first time user and setup welcome messages
  Future<void> _checkFirstTimeUser() async {
    final prefs = await SharedPreferences.getInstance();
    bool? hasUsedBefore = prefs.getBool('has_used_chat_page');
    
    if (hasUsedBefore == null || !hasUsedBefore) {
      // First time user
      setState(() {
        _isFirstTime = true;
        _welcomeMessages = [
          'Hello, sir. Initiating startup sequence.',
          'Activating all protocols.',
          'System check: complete.',
          'Power levels at 100%.',
          'You are now connected, sir.'
        ];
      });
      
      // Start welcome animation after a short delay
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          _startWelcomeAnimation();
        }
      });
      
      // Mark as used
      await prefs.setBool('has_used_chat_page', true);
    } else {
      // Returning user
      setState(() {
        _isFirstTime = false;
        _welcomeMessages = [
          'Welcome back ${widget.userName}',
          '${widget.assistantName} here to help'
        ];
      });
      
      // Start shorter welcome animation
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          _startWelcomeAnimation();
        }
      });
    }
  }

  // Start the welcome animation sequence
  void _startWelcomeAnimation() {
    if (_welcomeMessages.isEmpty) return;
    
    setState(() {
      _isShowingWelcomeAnimation = true;
      _currentWelcomeText = "";
    });
    
    // Start with first message
    _showNextWelcomeMessage(0);
  }

  // Show next welcome message with typewriter effect and synchronized TTS
  void _showNextWelcomeMessage(int messageIndex) {
    if (messageIndex >= _welcomeMessages.length) {
      // All messages shown, hide animation after a delay
      Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _isShowingWelcomeAnimation = false;
          });
        }
      });
      return;
    }
    
    String currentMessage = _welcomeMessages[messageIndex];
    int _welcomeTextIndex = 0;
    
    // Speak current message
    _speak(currentMessage);
    
    _welcomeTextTimer?.cancel();
    _welcomeTextTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_welcomeTextIndex < currentMessage.length) {
        setState(() {
          _currentWelcomeText = currentMessage.substring(0, _welcomeTextIndex + 1);
        });
        _welcomeTextIndex++;
      } else {
        timer.cancel();
        // Wait briefly then show next message
        Timer(const Duration(milliseconds: 600), () {
          if (mounted) {
            _showNextWelcomeMessage(messageIndex + 1);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _welcomeTextTimer?.cancel();
    _flutterTts.stop();
    _audioPlayer.dispose();
    _scanSubscription?.cancel();
    super.dispose();
  }

  // Bluetooth connect function
  Future<void> _connectEarbuds() async {
    setState(() {
      _isConnecting = true;
      _devicesList.clear();
    });

    // 1. Check Android system audio connection using native plugin
    bool systemAudioConnected = false;
    if (Platform.isAndroid) {
      systemAudioConnected = await VoiceChatPage.isBluetoothAudioConnected();
    }

    if (systemAudioConnected) {
      setState(() {
        _isConnected = true;
        _isConnecting = false;
      });
      await _speak('Audio device already connected. Hey there, Jarvis here');
      // Navigate to VoiceChatPage
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => VoiceChatPage(
            userName: widget.userName,
            assistantName: widget.assistantName,
          )),
        );
      }
      return;
    }

    // 2. Fallback: BLE scan and device selection as before
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
      // Navigate to VoiceChatPage
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => VoiceChatPage(
            userName: widget.userName,
            assistantName: widget.assistantName,
          )),
        );
      }
    } else {
      setState(() {
        _isConnecting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please connect your earbuds or audio device via system Bluetooth first.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
  }

  Future<void> _speak(String text) async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.9); // Faster speech rate to match typewriter animation
    await _flutterTts.speak(text);
  }

  Future<void> _playStartListeningSound() async {
    try {
      await _audioPlayer.play(AssetSource('mixkit-high-tech-bleep-2521.wav'));
    } catch (e) {
      print('Error playing start listening sound: $e');
    }
  }

  Future<void> _playStopListeningSound() async {
    try {
      await _audioPlayer.play(AssetSource('mixkit-interface-option-select-2573.wav'));
    } catch (e) {
      print('Error playing stop listening sound: $e');
    }
  }

  void _startListening() async {
    // Speech functionality temporarily disabled - use VoiceChatPage for voice commands
    print('Speech functionality disabled in this page. Use VoiceChatPage for voice commands.');
    /*
    await _playStartListeningSound();
    bool available = await _speech.initialize(
      onStatus: (val) {
        if (val == 'done' || val == 'notListening') {
          setState(() => _isListening = false);
          _playStopListeningSound();
          if (_lastWords.isNotEmpty) {
            _handleUserSpeech(_lastWords);
          }
        }
      },
      onError: (val) {
        setState(() => _isListening = false);
        _playStopListeningSound();
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
        cancelOnError: false,
      );
    }
    */
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
        
        
      ),
      body: SafeArea(
        child: Stack(
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
                          // Animated welcome text above the gif
                          if (_isShowingWelcomeAnimation)
                            Container(
                              height: 60, // Fixed height to prevent layout shifts
                              margin: const EdgeInsets.only(bottom: 16),
                              child: Center(
                                child: Text(
                                  _currentWelcomeText,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 25,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            )
                          else
                            // Default welcome text when not animating
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
            bottom: 110, // Moved up from 40 to 110
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
          // Continue without earbuds button
          Positioned(
            left: 0,
            right: 0,
            bottom: 50, // Moved up from -20 to 50
            child: Center(
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.7,
                height: 50,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white30, width: 1.5),
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
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => VoiceChatPage(
                            userName: widget.userName,
                            assistantName: widget.assistantName,
                          ),
                        ),
                      );
                    },
                    child: Text(
                      'Continue without earbuds',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
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
