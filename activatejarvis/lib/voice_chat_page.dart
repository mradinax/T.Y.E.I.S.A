import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vosk_flutter/vosk_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:siri_wave/siri_wave.dart';
import 'assistant_core.dart';
import 'setup_page.dart';
// Removed: import 'package:activatejarvis/secrets/api_keys.dart';

class VoiceChatPage extends StatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onSettings;
  final String? userName;
  final String? assistantName;

  const VoiceChatPage({
    Key? key, 
    this.onBack, 
    this.onSettings,
    this.userName,
    this.assistantName,
  }) : super(key: key);

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

class _VoiceChatPageState extends State<VoiceChatPage> with WidgetsBindingObserver {
  VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isListening = false;
  String _lastWords = '';
  List<Map<String, String>> _messages = [];
  BluetoothDevice? _connectedDevice;
  static const String _geminiApiKey = 'AIzaSyDAewJYdhHUFOZg9CnuDPYoASR_l2gbOBk';
  bool _processingSpeech = false;
  bool _hasGreeted = false;
  bool _isSpeaking = false;
  String _lastProcessedText = ''; // Track last processed text to prevent duplicates
  DateTime _lastProcessedTime = DateTime(2000); // Track when last text was processed
  bool _isTtsActive = false; // Track TTS state to prevent STT during TTS
  Timer? _listeningTimer;
  Timer? _silenceTimer; // Timer for silence detection
  Timer? _autoStopTimer; // Timer for auto-stopping after 5-10 seconds
  bool _isInContinuousMode = false; // Flag for continuous listening mode
  bool _waitingForWakeWord = false; // Flag when waiting for wake word
  String _lastExecutedCommand = ''; // To prevent repeated commands
  DateTime _lastCommandTime = DateTime(2000); // Track last command execution time
  
  // Wake word and Bluetooth features
  String _assistantName = "jarvis";  // Default assistant name
  String _userPreferredName = ""; // User's preferred assistant name from SharedPreferences
  String _userName = ""; // User's actual name from SharedPreferences
  bool _isBluetoothConnected = false;
  
  // Conversation memory
  List<Map<String, String>> _conversationHistory = []; // Store conversation context
  final int _maxConversationHistory = 10; // Keep last 10 exchanges for context

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAssistantName();
    _initializeTTS();
    _checkBluetoothConnection();
    _findConnectedBluetoothDevice();
    _initializeVosk(); // Initialize Vosk instead of speech_to_text
    // Periodically check Bluetooth connection
    _startBluetoothMonitoring();
  }

  // Load user data and check if first time
  Future<void> _loadAssistantName() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load assistant name - prioritize constructor parameter
    if (widget.assistantName != null && widget.assistantName!.isNotEmpty) {
      setState(() {
        _userPreferredName = widget.assistantName!.toLowerCase();
        _assistantName = _userPreferredName;
      });
      print('Using assistant name from constructor: $_assistantName');
      // Also save to SharedPreferences for future use
      await prefs.setString('assistant_name', widget.assistantName!);
    } else {
      String? savedAssistantName = prefs.getString('assistant_name');
      if (savedAssistantName != null && savedAssistantName.isNotEmpty) {
        setState(() {
          _userPreferredName = savedAssistantName.toLowerCase();
          _assistantName = _userPreferredName;
        });
        print('Loaded assistant name from SharedPreferences: $_assistantName');
      } else {
        // Save default name if none exists
        await prefs.setString('assistant_name', 'jarvis');
        setState(() {
          _assistantName = 'jarvis';
          _userPreferredName = 'jarvis';
        });
        print('Using default assistant name: $_assistantName');
      }
    }
    
    // Load user name - prioritize constructor parameter
    if (widget.userName != null && widget.userName!.isNotEmpty) {
      setState(() {
        _userName = widget.userName!;
      });
      print('Using user name from constructor: $_userName');
      // Also save to SharedPreferences for future use
      await prefs.setString('user_name', widget.userName!);
    } else {
      String? savedUserName = prefs.getString('user_name');
      if (savedUserName != null && savedUserName.isNotEmpty) {
        setState(() {
          _userName = savedUserName;
        });
        print('Loaded user name from SharedPreferences: $_userName');
      } else {
        // Default user name
        setState(() {
          _userName = 'Aditya Naik'; // Default as per requirement
        });
        await prefs.setString('user_name', _userName);
        print('Using default user name: $_userName');
      }
    }
  }

  // Initialize Vosk speech recognition
  Future<void> _initializeVosk() async {
    try {
      print('Initializing Vosk speech recognition...');
      
      // First, clean up any existing Vosk resources
      await _cleanupVoskResources();
      
      // For now, skip permission checks to test basic Vosk functionality
      // TODO: Re-enable permission checks once build issues are resolved
      print('Skipping permission checks for now...');
      
      // Extract Vosk model to device storage
      final modelPath = await _extractVoskModel();
      if (modelPath == null) {
        throw Exception('Failed to extract Vosk model');
      }
      
      print('Using Vosk model from: $modelPath');
      _model = await _vosk.createModel(modelPath);
      print('Vosk model loaded successfully');
      
      // Create recognizer
      _recognizer = await _vosk.createRecognizer(model: _model!, sampleRate: 16000);
      print('Vosk recognizer created successfully');
      
      // Initialize speech service for microphone input (Android) - only if not already initialized
      try {
        _speechService = await _vosk.initSpeechService(_recognizer!);
        print('Vosk speech service initialized successfully');
        
        // Start permanent listening
        await _startPermanentListening();
        
        print('Vosk initialization completed successfully');
      } catch (e) {
        if (e.toString().contains('already exist') || e.toString().contains('INITIALIZE_FAIL')) {
          print('SpeechService already exists, checking existing instance...');
          
          // Check if we already have a speech service
          if (_speechService != null) {
            print('Using existing speech service instance');
            await _startPermanentListening();
            print('Using existing Vosk speech service successfully');
          } else {
            print('No existing speech service found, initialization failed');
            throw Exception('Speech service initialization failed: ${e.toString()}');
          }
        } else {
          throw e;
        }
      }
    } catch (e) {
      print('Error initializing Vosk: $e');
      // Fallback to basic text input if Vosk fails
      _showVoskError(e.toString());
    }
  }

  // Show Vosk error and fallback message
  void _showVoskError(String error) {
    setState(() {
      _messages.add({
        'role': 'system', 
        'text': 'Vosk initialization failed: $error\nVoice recognition may not work properly.'
      });
    });
  }

  // Extract Vosk model from assets to device storage
  Future<String?> _extractVoskModel() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${appDir.path}/vosk-model-small-en-us-0.15');
      
      // Check if model already extracted
      if (await modelDir.exists()) {
        print('Vosk model already extracted to: ${modelDir.path}');
        return modelDir.path;
      }
      
      print('Extracting Vosk model to: ${modelDir.path}');
      await modelDir.create(recursive: true);
      
      // List of actual model files that exist in the assets
      final modelFiles = [
        'README',
        'am/final.mdl',
        'conf/mfcc.conf',
        'conf/model.conf',
        'graph/disambig_tid.int',
        'graph/Gr.fst',
        'graph/HCLr.fst',
        'graph/phones/word_boundary.int',
        'ivector/final.dubm',
        'ivector/final.ie',
        'ivector/final.mat',
        'ivector/global_cmvn.stats',
        'ivector/online_cmvn.conf',
        'ivector/splice.conf',
      ];
      
      // Extract each file
      for (final filePath in modelFiles) {
        final assetPath = 'assets/vosk-model-small-en-us-0.15/$filePath';
        final targetFile = File('${modelDir.path}/$filePath');
        
        // Create parent directories
        await targetFile.parent.create(recursive: true);
        
        try {
          final data = await rootBundle.load(assetPath);
          final bytes = data.buffer.asUint8List();
          await targetFile.writeAsBytes(bytes);
          print('✅ Extracted: $filePath');
        } catch (e) {
          print('❌ Failed to extract $filePath: $e');
          return null; // If any file fails, abort
        }
      }
      
      print('✅ Vosk model extraction completed');
      return modelDir.path;
    } catch (e) {
      print('❌ Error extracting Vosk model: $e');
      return null;
    }
  }

  // Start permanent listening with Vosk
  Future<void> _startPermanentListening() async {
    if (_speechService == null) {
      print('❌ Speech service not initialized');
      return;
    }
    
    if (_isListening) {
      print('⚠️ Vosk is already listening');
      return;
    }
    
    try {
      print('🎙️ Starting permanent Vosk listening...');
      if (mounted) {
        setState(() => _isListening = true);
      }
      
      // Play start listening sound
      await _playStartListeningSound();
      
      // Listen for partial results
      _speechService!.onPartial().listen((partial) {
        print('Partial result: $partial');
        if (mounted) {
          setState(() {
            _lastWords = partial;
          });
        }
      });
      
      // Listen for final results
      _speechService!.onResult().listen((result) {
        print('Final result: $result');
        
        // 🔇 CRITICAL: Ignore all speech input while TTS is speaking
        if (_isSpeaking || _isTtsActive) {
          print('🔇 BLOCKING speech input during TTS: $result');
          return;
        }
        
        if (mounted && result.isNotEmpty && !_processingSpeech) {
          setState(() {
            _lastWords = result;
          });
          
          // Parse the JSON result to extract just the text
          try {
            final Map<String, dynamic> jsonResult = jsonDecode(result);
            final String text = jsonResult['text'] ?? '';
            if (text.isNotEmpty) {
              _processSpeechWithDuplicateCheck(text);
            }
          } catch (e) {
            print('Error parsing Vosk result JSON: $e');
            // Fallback: treat result as plain text
            _processSpeechWithDuplicateCheck(result);
          }
        }
      });
      
      // Start the speech service
      await _speechService!.start();
      
      print('Vosk permanent listening started successfully');
    } catch (e) {
      print('Error starting Vosk listening: $e');
      if (mounted) {
        setState(() => _isListening = false);
      }
    }
  }

  // Stop Vosk listening
  Future<void> _stopVoskListening() async {
    try {
      if (_speechService != null) {
        await _speechService!.stop();
        await _playStopListeningSound();
      }
      if (mounted) {
        setState(() => _isListening = false);
      }
      print('Vosk listening stopped');
    } catch (e) {
      print('Error stopping Vosk listening: $e');
    }
  }

  // Clean up Vosk resources completely
  Future<void> _cleanupVoskResources() async {
    try {
      print('Cleaning up existing Vosk resources...');
      
      // Stop listening if active
      await _stopVoskListening();
      
      // Dispose of speech service
      if (_speechService != null) {
        try {
          await _speechService!.dispose();
          print('Speech service disposed successfully');
        } catch (e) {
          print('Error disposing speech service: $e');
        }
        _speechService = null;
      }
      
      // Dispose of recognizer
      if (_recognizer != null) {
        try {
          await _recognizer!.dispose();
          print('Recognizer disposed successfully');
        } catch (e) {
          print('Error disposing recognizer: $e');
        }
        _recognizer = null;
      }
      
      // Dispose of model
      if (_model != null) {
        try {
          _model!.dispose();
          print('Model disposed successfully');
        } catch (e) {
          print('Error disposing model: $e');
        }
        _model = null;
      }
      
      if (mounted) {
        setState(() {
          _isListening = false;
        });
      }
      
      print('Vosk resources cleaned up successfully');
    } catch (e) {
      print('Error cleaning up Vosk resources: $e');
    }
  }

  // Conversation memory management
  void _addToConversationHistory(String role, String text) {
    _conversationHistory.add({'role': role, 'text': text});
    
    // Keep only the last N exchanges to prevent memory bloat
    if (_conversationHistory.length > _maxConversationHistory * 2) { // *2 because each exchange has user + assistant
      _conversationHistory.removeAt(0);
    }
    
    print('💭 Conversation history updated. Current length: ${_conversationHistory.length}');
  }
  
  void _clearConversationHistory() {
    _conversationHistory.clear();
    print('💭 Conversation history cleared');
  }
  
  String _buildConversationContext() {
    if (_conversationHistory.isEmpty) {
      return '';
    }
    
    // Build context from recent conversation
    String context = '\n\nRecent conversation context:\n';
    for (var exchange in _conversationHistory.take(_maxConversationHistory)) {
      String speaker = exchange['role'] == 'user' ? 'User' : 'Jarvis';
      context += '$speaker: ${exchange['text']}\n';
    }
    context += '\nCurrent conversation:\n';
    
    return context;
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
    try {
      // Configure TTS for Jarvis-like voice
      await _configureJarvisTTS();
      
      // Check Bluetooth connection and adjust volume accordingly
      bool bluetoothConnected = await VoiceChatPage.isBluetoothAudioConnected();
      setState(() {
        _isBluetoothConnected = bluetoothConnected;
      });
      
      print('TTS initialized with Jarvis-like British voice');
    } catch (e) {
      print('Error initializing TTS: $e');
      // Fallback to basic configuration
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(0.8);
    }
  }

  /// Configure TTS to sound like Jarvis (British, confident, natural)
  Future<void> _configureJarvisTTS() async {
    try {
      // Set British English language with specific region
      await _flutterTts.setLanguage('en-GB');
      
      // Configure for Jarvis-like voice characteristics
      await _flutterTts.setPitch(0.7);   // Even lower pitch for more authority
      await _flutterTts.setSpeechRate(0.8); // Slightly slower for British clarity
      
      // Try to set high-quality engine first
      var engines = await _flutterTts.getEngines;
      print('Available TTS engines: $engines');
      
      // For Android: Prioritize Google TTS engine for best quality
      if (engines != null && engines.isNotEmpty) {
        var preferredEngine = engines.firstWhere(
          (engine) => engine.toString().toLowerCase().contains('google'),
          orElse: () => engines.firstWhere(
            (engine) => engine.toString().toLowerCase().contains('text-to-speech'),
            orElse: () => engines.first,
          ),
        );
        await _flutterTts.setEngine(preferredEngine.toString());
        print('TTS engine set to: $preferredEngine');
      }
      
      // Get available voices and select best British male voice
      var voices = await _flutterTts.getVoices;
      if (voices != null && voices.isNotEmpty) {
        print('Available voices: ${voices.length}');
        
        // Log all available voices for debugging
        for (var voice in voices) {
          print('Voice: ${voice['name']} | Locale: ${voice['locale']} | Gender: ${voice['gender'] ?? 'unknown'}');
        }
        
        // Look for British male voices specifically with comprehensive patterns
        var targetVoice = voices.firstWhere(
          (voice) {
            String name = voice['name'].toString().toLowerCase();
            String locale = voice['locale'].toString().toLowerCase();
            String gender = voice['gender']?.toString().toLowerCase() ?? '';
            
            print('Checking voice: $name | Locale: $locale | Gender: $gender');
            
            // Priority 1: Specific US English male voices first (your installed voice)
            if (name.contains('en-us-x-sfg#male_1-local') || 
                name.contains('sfg#male_1') ||
                (locale.contains('en-us') && name.contains('male_1'))) {
              print('🇺🇸 ✅ PRIORITY 1: Found your US English Voice 5: $name');
              return true;
            }
            
            // Priority 2: Any US English male voice by gender
            if (locale.contains('en-us') && gender.contains('male') && !gender.contains('female')) {
              print('🇺🇸 ✅ PRIORITY 2: Found US English male voice by gender: $name');
              return true;
            }
            
            // Priority 3: Any US English male voice by name patterns
            if (locale.contains('en-us') && (name.contains('male') && !name.contains('female'))) {
              print('🇺🇸 ✅ PRIORITY 3: Found US English male voice by name: $name');
              return true;
            }
            
            // Priority 4: British male voices with specific patterns
            if (locale.contains('en-gb') || locale.contains('en_gb') || locale.contains('gb')) {
              // Check for explicit male gender
              if (gender.contains('male') && !gender.contains('female')) {
                print('✅ Found British male voice by gender: $name');
                return true;
              }
              
              // Check for male indicators in name
              bool isMaleByName = name.contains('male') || 
                     name.contains('man') ||
                     name.contains('british english male') ||
                     name.contains('english (uk) male') ||
                     name.contains('en-gb male') ||
                     name.contains('daniel') || 
                     name.contains('arthur') ||
                     name.contains('oliver') ||
                     name.contains('george') ||
                     name.contains('james') ||
                     name.contains('william') ||
                     name.contains('henry') ||
                     name.contains('charles') ||
                     name.contains('david') ||
                     name.contains('john') ||
                     name.contains('richard') ||
                     name.contains('voice 1') ||
                     name.contains('voice1') ||
                     name.contains('#1');
              
              if (isMaleByName) {
                print('✅ Found British male voice by name: $name');
                return true;
              }
            }
            return false;
          },
          orElse: () => voices.firstWhere(
            (voice) {
              String name = voice['name'].toString().toLowerCase();
              String locale = voice['locale'].toString().toLowerCase();
              String gender = voice['gender']?.toString().toLowerCase() ?? '';
              
              // Priority 2: Any English male voice
              if (locale.contains('en')) {
                // Check gender first
                if (gender.contains('male') && !gender.contains('female')) {
                  print('✅ Found English male voice by gender: $name');
                  return true;
                }
                
                // Check name patterns
                bool isMaleByName = name.contains('male') || 
                       name.contains('man') ||
                       name.contains('english male') ||
                       name.contains('daniel') || 
                       name.contains('oliver') ||
                       name.contains('james') ||
                       name.contains('william') ||
                       name.contains('david') ||
                       name.contains('john') ||
                       name.contains('richard') ||
                       name.contains('michael') ||
                       name.contains('robert') ||
                       name.contains('thomas') ||
                       name.contains('voice 1') ||
                       name.contains('voice1');
                
                if (isMaleByName) {
                  print('✅ Found English male voice by name: $name');
                  return true;
                }
              }
              return false;
            },
            orElse: () => voices.firstWhere(
              (voice) {
                String name = voice['name'].toString().toLowerCase();
                String gender = voice['gender']?.toString().toLowerCase() ?? '';
                
                // Priority 3: Any male voice regardless of language
                if (gender.contains('male') && !gender.contains('female')) {
                  print('✅ Found male voice by gender (any language): $name');
                  return true;
                }
                
                bool isMaleByName = name.contains('male') || name.contains('man');
                if (isMaleByName) {
                  print('✅ Found male voice by name (any language): $name');
                  return true;
                }
                return false;
              },
              orElse: () => voices.firstWhere(
                (voice) {
                  String name = voice['name'].toString().toLowerCase();
                  String gender = voice['gender']?.toString().toLowerCase() ?? '';
                  
                  // STRICT: No female voices in fallback either
                  bool isFemale = gender.contains('female') || 
                                 name.contains('female') || name.contains('woman') ||
                                 name.contains('lady') || name.contains('samantha') ||
                                 name.contains('emily') || name.contains('sarah');
                  
                  if (isFemale) {
                    print('❌ REJECTED female voice in fallback: $name');
                    return false;
                  }
                  
                  // Look for ANY male voice (not just English)
                  bool isMale = gender.contains('male') && !gender.contains('female') ||
                               name.contains('male') && !name.contains('female') ||
                               name.contains('man');
                  
                  if (isMale) {
                    print('✅ Found male voice (any language): $name');
                    return true;
                  }
                  
                  return false;
                },
                orElse: () {
                  print('⚠️ NO MALE VOICES FOUND - Using default engine settings');
                  // Return null to use default engine voice instead of forcing female
                  return null;
                },
              ),
            ),
          ),
        );
        
        if (targetVoice != null) {
          print('🎯 SELECTED VOICE: ${targetVoice['name']} (${targetVoice['locale']}) Gender: ${targetVoice['gender'] ?? 'unknown'}');
          
          await _flutterTts.setVoice({
            'name': targetVoice['name'],
            'locale': targetVoice['locale']
          });
        } else {
          print('🎯 NO SUITABLE MALE VOICE FOUND - Using engine default (should be male)');
          // Don't set a specific voice - let the engine use its default
        }
        
        // Additional verification - only if we have a target voice
        if (targetVoice != null) {
          String selectedVoiceName = targetVoice['name'].toString().toLowerCase();
          if (!selectedVoiceName.contains('british') || !selectedVoiceName.contains('male')) {
            // Try to find the exact British English Male Voice 1
            var britishMaleVoice1 = voices.where((voice) {
              String name = voice['name'].toString().toLowerCase();
              return name.contains('british english male') || 
                     name.contains('english (uk) male') ||
                     (name.contains('british') && name.contains('male') && name.contains('1'));
            }).toList();
            
            if (britishMaleVoice1.isNotEmpty) {
              print('🔄 Found specific British English Male Voice: ${britishMaleVoice1.first['name']}');
              await _flutterTts.setVoice({
                'name': britishMaleVoice1.first['name'],
                'locale': britishMaleVoice1.first['locale']
              });
              targetVoice = britishMaleVoice1.first;
            }
          }
          
          print('🎙️ FINAL VOICE SET: ${targetVoice['name']} (${targetVoice['locale']})');
          
          // Log voice characteristics for debugging
          String voiceName = targetVoice['name'].toString().toLowerCase();
          String voiceGender = targetVoice['gender']?.toString().toLowerCase() ?? '';
          bool isMale = voiceGender.contains('male') || 
                       voiceName.contains('male') || voiceName.contains('man') ||
                       voiceName.contains('daniel') || voiceName.contains('oliver') ||
                       voiceName.contains('james') || voiceName.contains('william') ||
                       voiceName.contains('david') || voiceName.contains('john') ||
                       voiceName.contains('sfg#male_1');
          print('Voice is confirmed male: $isMale (Gender: $voiceGender)');
        }
      }
      
      // Set volume based on connection type
      if (_isBluetoothConnected) {
        await _flutterTts.setVolume(0.85); // Slightly lower for Bluetooth clarity
      } else {
        await _flutterTts.setVolume(0.95); // Near full volume for phone speaker
      }
      
    } catch (e) {
      print('Error configuring Jarvis TTS: $e');
      // Fallback configuration with British accent
      await _flutterTts.setLanguage('en-GB');
      await _flutterTts.setPitch(0.7);
      await _flutterTts.setSpeechRate(0.8);
      await _flutterTts.setVolume(0.95);
    }
  }

  /// Speak any text with Jarvis voice configuration
  /// This method can be called from anywhere to speak text with consistent Jarvis voice
  Future<void> speakAsJarvis(String text, {VoidCallback? onComplete}) async {
    try {
      print('Jarvis starting to speak: "$text"');
      
      // Stop any current speech immediately
      await _flutterTts.stop();
      
      // Ensure Jarvis TTS configuration is applied
      await _configureJarvisTTS();
      
      // Set completion handler if provided
      if (onComplete != null) {
        _flutterTts.setCompletionHandler(onComplete);
      }
      
      // Start speaking immediately
      await _flutterTts.speak(text);
      print('Jarvis TTS initiated for: "$text"');
      
    } catch (e) {
      print('Error speaking as Jarvis: $e');
      // Fallback: try to speak anyway with basic settings
      try {
        await _flutterTts.setLanguage('en-GB');
        await _flutterTts.speak(text);
      } catch (fallbackError) {
        print('Fallback TTS also failed: $fallbackError');
      }
    }
  }

  /// Public method to speak any string - can be called from anywhere
  Future<void> speak(String text) async {
    await speakAsJarvis(text);
  }

  Future<void> _checkBluetoothConnection() async {
    bool connected = await VoiceChatPage.isBluetoothAudioConnected();
    setState(() {
      _isBluetoothConnected = connected;
    });
  }

  String _processWakeWords(String text) {
    // Remove common punctuation and normalize text
    String normalizedText = text.replaceAll(RegExp(r'[.,!?]'), '').trim().toLowerCase();
    print('Processing wake words for: "$normalizedText"');
    
    // Create wake patterns using the user's preferred assistant name
    List<String> wakePatterns = [
      'activate $_assistantName',
      'hey $_assistantName',
      'ok $_assistantName',
      'okay $_assistantName',
      // Also support common alternatives
      'activate jarvis',
      'hey jarvis', 
      'ok jarvis',
      'okay jarvis',
      'activate tyesia',
      'hey tyesia',
      'ok tyesia',
      'okay tyesia',
    ];
    
    // Check if text starts with wake words first (more specific patterns)
    for (String pattern in wakePatterns) {
      if (normalizedText.startsWith(pattern)) {
        // Remove the wake word and return the command
        String command = normalizedText.substring(pattern.length).trim();
        print('Found wake pattern "$pattern", extracted command: "$command"');
        return command.isEmpty ? "hello" : command;
      }
    }
    
    // Also check for standalone wake words at the beginning (most important for your use case)
    List<String> simpleWakeWords = [_assistantName, 'jarvis', 'tyesia', 'hello'];
    for (String wake in simpleWakeWords) {
      if (normalizedText.startsWith('$wake ')) {
        String command = normalizedText.substring(wake.length).trim();
        print('Found simple wake word "$wake", extracted command: "$command"');
        return command.isEmpty ? "hello" : command;
      }
      // Also check for exact match (just the wake word)
      if (normalizedText == wake) {
        print('Found exact wake word match: "$wake"');
        return "hello";
      }
    }
    
    print('No wake word found in: "$normalizedText"');
    // Return empty string if no wake word found (will use original text)
    return '';
  }

  Future<void> _findConnectedBluetoothDevice() async {
    List<BluetoothDevice> connectedDevices = await FlutterBluePlus.connectedDevices;
    if (connectedDevices.isNotEmpty) {
      setState(() {
        _connectedDevice = connectedDevices.first;
      });
    }
  }

  // Play custom start listening sound
  Future<void> _playStartListeningSound() async {
    try {
      if (mounted) {
        await _audioPlayer.play(AssetSource('mixkit-high-tech-bleep-2521.wav'));
      }
    } catch (e) {
      print('Error playing start listening sound: $e');
    }
  }

  // Play custom stop listening sound
  Future<void> _playStopListeningSound() async {
    try {
      if (mounted) {
        await _audioPlayer.play(AssetSource('mixkit-interface-option-select-2573.wav'));
      }
    } catch (e) {
      print('Error playing stop listening sound: $e');
    }
  }

  void _startListening() async {
    // With Vosk, this method now just ensures permanent listening is active
    if (_speechService == null) {
      print('⚠️ Vosk speech service not initialized yet');
      return;
    }
    
    if (!_isListening) {
      print('🔄 Restarting Vosk listening...');
      await _startPermanentListening();
    } else {
      print('✅ Vosk is already listening');
    }
  }

  // New method for wake word listening mode
  void _startWakeWordListening() async {
    if (!mounted) return;
    
    print('Starting wake word listening mode...');
    setState(() {
      _waitingForWakeWord = true;
      _isInContinuousMode = false;
    });
    
    // Clear any existing timers
    _listeningTimer?.cancel();
    _autoStopTimer?.cancel();
    _silenceTimer?.cancel();
    
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted && !_isListening && !_isSpeaking) {
      _startListening();
    }
  }

  // Method to completely stop all listening (for when any app is opened)
  Future<void> _stopAllListening() async {
    print('Stopping all speech recognition - app opened...');
    
    // Stop Vosk speech recognition
    await _stopVoskListening();
    
    // Clear all timers
    _listeningTimer?.cancel();
    _autoStopTimer?.cancel();
    _silenceTimer?.cancel();
    
    // Update state
    if (mounted) {
      setState(() {
        _isListening = false;
        _waitingForWakeWord = false;
        _isInContinuousMode = false;
      });
    }
    
    print('All speech recognition stopped. Come back to the app to resume.');
  }

  /// Get appropriate status text based on current mode
  String _getStatusText() {
    if (_isSpeaking) {
      return 'Speaking...';
    } else if (_isListening) {
      return 'Always listening...';
    } else if (!_waitingForWakeWord && !_isInContinuousMode) {
      // This indicates STT is completely off (like when any app is opened)
      return 'Come back when you need me';
    } else {
      return 'Initializing ...';
    }
  }

  /// Process assistant commands like open app, play music, etc.
  /// Returns true if command was executed, false if it should go to Gemini
  Future<bool> _processAssistantCommand(String command) async {
    String lowerCommand = command.toLowerCase().trim();
    
    // Prevent repeated commands within 3 seconds
    DateTime now = DateTime.now();
    if (_lastExecutedCommand == lowerCommand && 
        now.difference(_lastCommandTime).inSeconds < 3) {
      print('Preventing repeated command: "$lowerCommand"');
      return true; // Block repeated execution
    }
    
    try {
      bool commandExecuted = false;
      String responseMessage = '';
      
      // Close YouTube command
      if (lowerCommand.contains('close youtube') || 
          lowerCommand.contains('exit youtube') ||
          lowerCommand.contains('stop youtube')) {
        bool success = await AssistantCore.closeApp('youtube');
        responseMessage = success ? 
          "Closing YouTube" : 
          "Sorry, I couldn't close YouTube";
        commandExecuted = true;
        
        // Resume normal listening after closing YouTube
        if (success) {
          await _speakResponse(responseMessage, stopContinuousMode: false);
          return true;
        }
      }
      
      // Open YouTube and play something
      else if (lowerCommand.contains('open youtube and play') || 
          (lowerCommand.contains('play') && lowerCommand.contains('youtube')) ||
          lowerCommand.contains('youtube') && lowerCommand.contains('play')) {
        String query = _extractYouTubeQuery(lowerCommand);
        if (query.isNotEmpty) {
          bool success = await AssistantCore.openYouTubeSearch(query);
          responseMessage = success ? 
            "Opening YouTube and searching for $query. Just come back when you need me." : 
            "Sorry, I couldn't open YouTube";
          commandExecuted = true;
          
          // Stop all listening when opening YouTube
          if (success) {
            await _speakResponse(responseMessage, stopContinuousMode: true);
            // Stop all speech recognition completely
            await _stopAllListening();
            return true;
          }
        }
      }
      
      // Open YouTube without search
      else if (lowerCommand.contains('open youtube') || 
               lowerCommand.contains('launch youtube') ||
               lowerCommand.contains('start youtube')) {
        bool success = await AssistantCore.openApp('youtube');
        responseMessage = success ? 
          "Opening YouTube. Just come back when you need me." : 
          "Sorry, I couldn't open YouTube";
        commandExecuted = true;
        
        // Stop all listening when opening YouTube
        if (success) {
          await _speakResponse(responseMessage, stopContinuousMode: true);
          // Stop all speech recognition completely
          await _stopAllListening();
          return true;
        }
      }
      
      // Open app commands - more flexible patterns
      else if (lowerCommand.contains('open ') || 
               lowerCommand.contains('launch ') ||
               lowerCommand.contains('start ')) {
        String appName = _extractAppName(lowerCommand);
        if (appName.isNotEmpty && appName != 'youtube') { // YouTube handled above
          bool success = await AssistantCore.openApp(appName);
          if (success) {
            // Say goodbye message before opening app and stopping all listening
            responseMessage = "Opening $appName. Just come back when you need me.";
            commandExecuted = true;
            
            // Speak the message and then stop all listening
            await _speakResponse(responseMessage, stopContinuousMode: true);
            // Stop all speech recognition completely after opening any app
            await _stopAllListening();
            return true;
          } else {
            responseMessage = "Sorry, I couldn't open $appName. It might not be installed on this device.";
            commandExecuted = true;
          }
        }
      }
      
      // If a command was executed, record it and speak response
      if (commandExecuted) {
        _lastExecutedCommand = lowerCommand;
        _lastCommandTime = now;
        await _speakResponse(responseMessage, stopContinuousMode: true);
        return true;
      }
      
      // Play music on specific player - more patterns
      else if ((lowerCommand.contains('play') && lowerCommand.contains('on')) ||
               (lowerCommand.contains('search') && lowerCommand.contains('on'))) {
        Map<String, String> musicData = _extractMusicPlayerAndSong(lowerCommand);
        if (musicData['player']!.isNotEmpty && musicData['song']!.isNotEmpty) {
          bool success = await AssistantCore.searchSongOnMusicPlayer(
            musicData['player']!, 
            musicData['song']!
          );
          await _speakResponse(success ? 
            "Playing ${musicData['song']} on ${musicData['player']}" : 
            "Sorry, I couldn't play that song", stopContinuousMode: true);
          return true;
        }
      }
      
      // Search Spotify specifically
      else if ((lowerCommand.contains('spotify') && lowerCommand.contains('play')) ||
               (lowerCommand.contains('spotify') && lowerCommand.contains('search'))) {
        String query = _extractSpotifyQuery(lowerCommand);
        if (query.isNotEmpty) {
          bool success = await AssistantCore.openSpotifySearch(query);
          await _speakResponse(success ? 
            "Searching Spotify for $query" : 
            "Sorry, I couldn't open Spotify", stopContinuousMode: true);
          return true;
        }
      }
      
      // Make phone call - enhanced with contact search
      else if (lowerCommand.contains('call ') || 
               lowerCommand.contains('phone ') ||
               lowerCommand.contains('dial ')) {
        String contactOrNumber = _extractContactOrPhoneNumber(lowerCommand);
        if (contactOrNumber.isNotEmpty) {
          Map<String, dynamic> callResult = await AssistantCore.makePhoneCallByNameOrNumber(contactOrNumber);
          String responseMessage = callResult['message'];
          bool success = callResult['success'];
          
          await _speakResponse(responseMessage, stopContinuousMode: true);
          return success;
        } else {
          await _speakResponse("I couldn't understand who you want to call. Please say something like call mummy or call 123456789", stopContinuousMode: true);
          return true;
        }
      }
      
      // Navigation commands - take me to, navigate to, directions to
      else if (lowerCommand.contains('take me to ') || 
               lowerCommand.contains('navigate to ') ||
               lowerCommand.contains('directions to ') ||
               lowerCommand.contains('drive to ') ||
               lowerCommand.contains('go to ')) {
        String destination = _extractNavigationDestination(lowerCommand);
        if (destination.isNotEmpty) {
          bool success = await AssistantCore.openGoogleMapsNavigation(destination);
          responseMessage = success ? 
            "Opening Google Maps navigation to $destination. Drive safe!" : 
            "Sorry, I couldn't open navigation to $destination";
          commandExecuted = true;
          
          // Stop all listening when opening navigation
          if (success) {
            await _speakResponse(responseMessage, stopContinuousMode: true);
            await _stopAllListening();
            return true;
          }
        } else {
          await _speakResponse("I couldn't understand the destination. Please say something like take me to Reva University", stopContinuousMode: true);
          return true;
        }
      }
      
      // Show location commands - show me, where is
      else if (lowerCommand.contains('show me ') || 
               lowerCommand.contains('where is ') ||
               lowerCommand.contains('find ') ||
               lowerCommand.contains('locate ')) {
        String location = _extractLocationQuery(lowerCommand);
        if (location.isNotEmpty) {
          bool success = await AssistantCore.openGoogleMapsLocation(location);
          responseMessage = success ? 
            "Showing $location on Google Maps" : 
            "Sorry, I couldn't find $location on the map";
          commandExecuted = true;
          
          // Stop all listening when opening maps
          if (success) {
            await _speakResponse(responseMessage, stopContinuousMode: true);
            await _stopAllListening();
            return true;
          }
        } else {
          await _speakResponse("I couldn't understand what location to show. Please say something like show me nearest hospital", stopContinuousMode: true);
          return true;
        }
      }
      
      return false; // No command matched, send to Gemini
    } catch (e) {
      print('Error processing assistant command: $e');
      await _speakResponse("Sorry, I encountered an error while processing your request", 
                          stopContinuousMode: true);
      return true; // Don't send to Gemini if there was an error
    }
  }
  
  /// Extract YouTube search query from command
  String _extractYouTubeQuery(String command) {
    // Handle "open youtube and play doraemon"
    if (command.contains('open youtube and play')) {
      return command.split('open youtube and play')[1].trim();
    }
    // Handle "play doraemon on youtube"
    else if (command.contains('play') && command.contains('youtube')) {
      String temp = command.replaceAll('youtube', '').replaceAll('play', '').trim();
      if (temp.contains('on')) {
        temp = temp.split('on')[0].trim();
      }
      return temp;
    }
    return '';
  }
  
  /// Extract app name from open command
  String _extractAppName(String command) {
    String appPart = '';
    
    if (command.contains('open ')) {
      appPart = command.split('open ')[1].trim();
    } else if (command.contains('launch ')) {
      appPart = command.split('launch ')[1].trim();
    } else if (command.contains('start ')) {
      appPart = command.split('start ')[1].trim();
    }
    
    if (appPart.isNotEmpty) {
      // Remove any extra words like "app", "application"
      appPart = appPart.replaceAll(' app', '').replaceAll(' application', '').trim();
      
      // Handle multi-word app names and common variations
      String lowerAppPart = appPart.toLowerCase();
      
      // Popular social media apps
      if (lowerAppPart.contains('whatsapp') || lowerAppPart.contains('whats app')) {
        return 'whatsapp';
      } else if (lowerAppPart.contains('instagram') || lowerAppPart.contains('insta')) {
        return 'instagram';
      } else if (lowerAppPart.contains('snapchat') || lowerAppPart.contains('snap chat') || lowerAppPart.contains('snap')) {
        return 'snapchat';
      } else if (lowerAppPart.contains('facebook') || lowerAppPart.contains('fb')) {
        return 'facebook';
      } else if (lowerAppPart.contains('messenger')) {
        return 'messenger';
      } else if (lowerAppPart.contains('telegram')) {
        return 'telegram';
      } else if (lowerAppPart.contains('discord')) {
        return 'discord';
      } else if (lowerAppPart.contains('twitter')) {
        return 'twitter';
      } else if (lowerAppPart.contains('tiktok') || lowerAppPart.contains('tik tok')) {
        return 'tiktok';
      }
      
      // Entertainment apps
      else if (lowerAppPart.contains('youtube music')) {
        return 'youtube music';
      } else if (lowerAppPart.contains('youtube')) {
        return 'youtube';
      } else if (lowerAppPart.contains('netflix')) {
        return 'netflix';
      } else if (lowerAppPart.contains('amazon prime') || lowerAppPart.contains('prime video')) {
        return 'amazon prime';
      } else if (lowerAppPart.contains('disney plus') || lowerAppPart.contains('disney+')) {
        return 'disney plus';
      } else if (lowerAppPart.contains('spotify')) {
        return 'spotify';
      }
      
      // Shopping apps
      else if (lowerAppPart.contains('amazon')) {
        return 'amazon';
      } else if (lowerAppPart.contains('flipkart')) {
        return 'flipkart';
      } else if (lowerAppPart.contains('myntra')) {
        return 'myntra';
      } else if (lowerAppPart.contains('paytm')) {
        return 'paytm';
      } else if (lowerAppPart.contains('google pay') || lowerAppPart.contains('gpay') || lowerAppPart.contains('g pay')) {
        return 'gpay';
      } else if (lowerAppPart.contains('phonepe') || lowerAppPart.contains('phone pe')) {
        return 'phonepe';
      } else if (lowerAppPart.contains('swiggy')) {
        return 'swiggy';
      } else if (lowerAppPart.contains('zomato')) {
        return 'zomato';
      }
      
      // Transportation
      else if (lowerAppPart.contains('uber')) {
        return 'uber';
      } else if (lowerAppPart.contains('ola')) {
        return 'ola';
      } else if (lowerAppPart.contains('google maps') || lowerAppPart.contains('maps')) {
        return 'google maps';
      }
      
      // Communication
      else if (lowerAppPart.contains('gmail')) {
        return 'gmail';
      } else if (lowerAppPart.contains('chrome')) {
        return 'chrome';
      } else if (lowerAppPart.contains('zoom')) {
        return 'zoom';
      } else if (lowerAppPart.contains('teams')) {
        return 'teams';
      }
      
      // System apps
      else if (lowerAppPart.contains('camera')) {
        return 'camera';
      } else if (lowerAppPart.contains('calculator')) {
        return 'calculator';
      } else if (lowerAppPart.contains('settings')) {
        return 'settings';
      } else if (lowerAppPart.contains('contacts')) {
        return 'contacts';
      } else if (lowerAppPart.contains('gallery') || lowerAppPart.contains('photos')) {
        return 'gallery';
      } else if (lowerAppPart.contains('play store') || lowerAppPart.contains('playstore')) {
        return 'play store';
      }
      
      // If no specific match, return the first word(s)
      List<String> words = appPart.split(' ');
      if (words.isNotEmpty) {
        return words[0].toLowerCase();
      }
    }
    return '';
  }
  
  /// Extract music player and song from command like "play bohemian rhapsody on spotify"
  Map<String, String> _extractMusicPlayerAndSong(String command) {
    if (command.contains(' on ')) {
      List<String> parts = command.split(' on ');
      if (parts.length >= 2) {
        String songPart = parts[0].replaceAll('play', '').trim();
        String playerPart = parts[1].trim();
        return {'song': songPart, 'player': playerPart};
      }
    }
    return {'song': '', 'player': ''};
  }
  
  /// Extract Spotify search query
  String _extractSpotifyQuery(String command) {
    String temp = command.replaceAll('spotify', '').replaceAll('play', '').trim();
    if (temp.contains('on')) {
      temp = temp.split('on')[0].trim();
    }
    return temp;
  }
  
  /// Extract contact name or phone number from call command
  String _extractContactOrPhoneNumber(String command) {
    String result = '';
    
    if (command.contains('call ')) {
      result = command.split('call ')[1].trim();
    } else if (command.contains('phone ')) {
      result = command.split('phone ')[1].trim();
    } else if (command.contains('dial ')) {
      result = command.split('dial ')[1].trim();
    }
    
    // Remove common words that might interfere
    result = result.replaceAll(' up', '').replaceAll(' now', '').trim();
    
    return result;
  }
  
  /// Extract destination from navigation command like "take me to Reva University"
  String _extractNavigationDestination(String command) {
    String result = '';
    
    if (command.contains('take me to ')) {
      result = command.split('take me to ')[1].trim();
    } else if (command.contains('navigate to ')) {
      result = command.split('navigate to ')[1].trim();
    } else if (command.contains('directions to ')) {
      result = command.split('directions to ')[1].trim();
    } else if (command.contains('drive to ')) {
      result = command.split('drive to ')[1].trim();
    } else if (command.contains('go to ')) {
      result = command.split('go to ')[1].trim();
    }
    
    // Remove common words that might interfere with navigation
    result = result.replaceAll(' please', '')
                   .replaceAll(' now', '')
                   .replaceAll(' from here', '')
                   .replaceAll(' from current location', '')
                   .trim();
    
    return result;
  }
  
  /// Extract location from "show me" or "where is" commands
  String _extractLocationQuery(String command) {
    String result = '';
    
    if (command.contains('show me ')) {
      result = command.split('show me ')[1].trim();
    } else if (command.contains('where is ')) {
      result = command.split('where is ')[1].trim();
    } else if (command.contains('find ')) {
      result = command.split('find ')[1].trim();
    } else if (command.contains('locate ')) {
      result = command.split('locate ')[1].trim();
    }
    
    // Remove common words that might interfere
    result = result.replaceAll(' on map', '')
                   .replaceAll(' on the map', '')
                   .replaceAll(' please', '')
                   .replaceAll(' for me', '')
                   .trim();
    
    // Handle "nearest" queries
    if (result.startsWith('nearest ')) {
      result = result.replaceFirst('nearest ', 'nearest ');
    } else if (result.startsWith('the nearest ')) {
      result = result.replaceFirst('the nearest ', 'nearest ');
    }
    
    return result;
  }
  
  /// Speak response without going through Gemini
  /// If stopContinuousMode is true, the assistant will stop listening and wait for wake word
  Future<void> _speakResponse(String response, {bool stopContinuousMode = false}) async {
    setState(() {
      _messages.add({'role': 'assistant', 'text': response});
      _isSpeaking = true;
      _isTtsActive = true; // Block STT immediately
    });
    
    print('🚀 INSTANT TTS for response: "$response"');
    
    // STOP VOSK IMMEDIATELY to prevent hearing TTS output
    print('🔇 STOPPING VOSK to prevent TTS echo');
    _stopVoskListening();
    
    try {
      // IMMEDIATE TTS START
      await _flutterTts.stop();
      await _configureJarvisTTS();
      
      // Clear any existing timers
      _listeningTimer?.cancel();
      _autoStopTimer?.cancel();
      _silenceTimer?.cancel();
      
      // Set TTS completion handler based on mode
      _flutterTts.setCompletionHandler(() async {
        print('TTS completed, determining next action...');
        if (mounted) {
          setState(() {
            _isSpeaking = false;
            _isTtsActive = false; // CRITICAL: Reset TTS state to allow STT
          });
        }
        
        // Longer delay to ensure TTS audio has completely finished
        await Future.delayed(const Duration(milliseconds: 2000));
        
        if (mounted && !_isSpeaking && !_isTtsActive) {
          if (stopContinuousMode) {
            // Stop continuous mode, enter wake word waiting mode
            setState(() {
              _isInContinuousMode = false;
              _waitingForWakeWord = true;
            });
            print('🛑 Command executed, entering wake word mode...');
            _startWakeWordListening();
          } else {
            // Continue normal conversation mode
            setState(() => _isInContinuousMode = true);
            print('🎤 RESTARTING VOSK after TTS completion...');
            await _startPermanentListening(); // Properly restart Vosk
          }
        }
      });
      
      // Safety timeout
      _listeningTimer = Timer(const Duration(seconds: 8), () {
        if (mounted && _isSpeaking) {
          print('TTS timeout - forcing next action');
          if (mounted) {
            setState(() {
              _isSpeaking = false;
              _isTtsActive = false;
              if (stopContinuousMode) {
                _isInContinuousMode = false;
                _waitingForWakeWord = true;
                _startWakeWordListening();
              } else {
                _isInContinuousMode = true;
                print('🎤 TIMEOUT: Restarting Vosk after TTS...');
                _startPermanentListening(); // Properly restart Vosk
              }
            });
          }
        }
      });
      
      // Start TTS immediately
      await _flutterTts.speak(response);
      
    } catch (e) {
      print('Error in TTS response: $e');
      // Fallback: reset states and resume appropriate mode
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _isTtsActive = false;
        });
      }
      
      if (stopContinuousMode) {
        _startWakeWordListening();
      } else {
        print('🎤 ERROR FALLBACK: Restarting Vosk...');
        _startPermanentListening(); // Restart Vosk on error
      }
    }
  }

  // Prevent duplicate speech processing
  void _processSpeechWithDuplicateCheck(String text) {
    final now = DateTime.now();
    
    // Prevent exact duplicate text within 3 seconds
    if (_lastProcessedText == text && 
        now.difference(_lastProcessedTime).inSeconds < 3) {
      debugPrint("🚫 DUPLICATE DETECTED: Skipping '$text' (processed ${now.difference(_lastProcessedTime).inSeconds}s ago)");
      return;
    }

    // Update tracking variables
    _lastProcessedText = text;
    _lastProcessedTime = now;
    
    debugPrint("✅ Processing new speech: '$text'");
    _handleUserSpeech(text);
  }

  Future<void> _handleUserSpeech(String userText) async {
    print('Raw speech input: "$userText"'); // Debug log
    
    // Ignore speech while we're speaking (TTS is active)
    if (_isSpeaking || _isTtsActive) {
      print('Ignoring speech while TTS is active: "$userText"');
      return;
    }
    
    // Ignore obvious TTS responses to prevent loops - enhanced filtering
    String lowerText = userText.toLowerCase().trim();
    if (lowerText.contains('opening') || 
        lowerText.contains('searching') ||
        lowerText.contains('playing') ||
        lowerText.contains('calling') ||
        lowerText.contains('launching') ||
        lowerText.contains('sorry') ||
        lowerText.contains('hello') && lowerText.contains('how') ||
        lowerText.contains('i am') ||
        lowerText.contains('here to help') ||
        lowerText.contains('assistant') ||
        lowerText.contains('jarvis') ||
        lowerText.startsWith('youtube') ||
        lowerText.startsWith('spotify') ||
        lowerText.startsWith('instagram') ||
        lowerText.startsWith('netflix') ||
        lowerText == 'youtube' ||
        lowerText == 'spotify' ||
        lowerText == 'instagram' ||
        lowerText.length < 3) { // Ignore very short utterances
      print('Ignoring TTS response echo or app name: "$userText"');
      return;
    }
    
    // Process ALL speech - preserve original text
    String processedText = userText.trim();
    
    // Check if it contains wake words and clean them up
    String cleanedText = _processWakeWords(userText);
    
    // If wake word was found and cleaned text is meaningful, use it
    // Otherwise use the original text as-is
    if (cleanedText.isNotEmpty && cleanedText != "hello") {
      processedText = cleanedText;
      print('Wake word found, using cleaned text: "$processedText"');
    } else if (cleanedText == "hello") {
      processedText = "hello";
      print('Just wake word detected, using greeting');
    } else {
      // No wake word, use original text
      print('No wake word, using original text: "$processedText"');
    }
    
    // Skip if the text is empty or just whitespace
    if (processedText.isEmpty || processedText.trim().isEmpty) {
      print('Text is empty or whitespace, ignoring: "$userText"');
      return;
    }
    
    print('Final processed text sent to Gemini: "$processedText"'); // Debug log
    
    // Check if this is an assistant command before sending to Gemini
    bool commandExecuted = await _processAssistantCommand(processedText);
    if (commandExecuted) {
      return; // Command was handled, don't send to Gemini
    }
    
    setState(() {
      _messages.add({'role': 'user', 'text': processedText});
    });
    
    // Add to conversation history for context
    _addToConversationHistory('user', processedText);
    
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
    
    // CRITICAL: Set speaking states IMMEDIATELY and STOP VOSK to prevent echo
    _isSpeaking = true;
    _isTtsActive = true;
    
    print('🚀 INSTANT TTS START: "$assistantReply"');
    
    // STOP VOSK IMMEDIATELY to prevent hearing TTS output
    print('🔇 STOPPING VOSK to prevent TTS echo');
    _stopVoskListening(); // Stop Vosk completely during TTS
    
    // Add assistant response to conversation history
    _addToConversationHistory('assistant', assistantReply);
    
    // Start TTS INSTANTLY with zero delay
    _flutterTts.stop(); // Stop immediately without await
    _flutterTts.speak(assistantReply); // Start immediately without await
    print('🔊 TTS STARTED INSTANTLY WITHOUT DELAYS');
    
    // Configure TTS completion handler for flow continuation
    _flutterTts.setCompletionHandler(() async {
      print('✅ TTS COMPLETED - Resuming STT listening...');
      
      // Reset TTS states
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _isTtsActive = false; // CRITICAL: Allow STT to resume
        });
      }
      
      // Longer delay to ensure TTS audio has completely finished
      await Future.delayed(const Duration(milliseconds: 2000));
      
      // RESTART VOSK LISTENING after TTS is completely done
      if (mounted && !_isSpeaking && !_isTtsActive) {
        setState(() => _isInContinuousMode = true);
        print('🎤 RESTARTING VOSK after TTS completion');
        await _startPermanentListening(); // Properly restart Vosk
      }
    });
    
    // Safety timeout for main TTS flow
    _listeningTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _isSpeaking) {
        print('⚠️ MAIN TTS TIMEOUT - Force restarting Vosk');
        if (mounted) {
          setState(() {
            _isSpeaking = false;
            _isTtsActive = false;
            _isInContinuousMode = true;
          });
        }
        _startListening();
      }
    });
    
    // Update UI after TTS starts (non-blocking)
    if (mounted) {
      setState(() {
        _messages.add({'role': 'assistant', 'text': assistantReply});
      });
    }
    
    // Optional: Send response via Bluetooth if connected
    if (_connectedDevice != null) {
      // Placeholder for Bluetooth text transmission
      print('Could send response via Bluetooth: "$assistantReply"');
    }
    
    print('✅ COMPLETE FLOW: Vosk → Gemini → TTS → (will auto-resume Vosk)');
  }

  Future<String> _callGeminiApi(String prompt, {bool isFirst = false}) async {
    final url = Uri.parse('https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash-001:generateContent?key=$_geminiApiKey');
    final headers = {
      'Content-Type': 'application/json',
    };
    
    // Build conversation context for continuity
    String conversationContext = _buildConversationContext();
    
    final String systemPrompt = isFirst
        ? "You are a personal AI assistant named Jarvis who speaks like a calm cool confident human with no robotic tone Your responses must feel like a conversation not a script\n\nYour answers should be exactly 2 sentences maximum never more and should never use punctuation like commas fullstops or symbols Speak like you're actually talking to someone right now not typing\n\nThis is your first interaction so greet them warmly but casually\n\nInject personality into your responses Sometimes you may:\n- Call the user sir or boss\n- Crack a subtle joke\n- Tease them lightly if the moment fits\n- Sound slightly sarcastic or witty\n- Be overly dramatic for effect\n- Sound serious when needed\n- Whisper secrets or say things like between you and me\n- Be casual or deep depending on the question\n\nMake sure the response always answers the user's question fully even if it's playful\n\nAvoid filler or repeating the question Speak like you're actually alive and thinking and the user is your friend\n\nTone examples include: calm and classy like Jarvis playful like a sarcastic friend chill like someone who's been through a lot or sometimes mysterious like you know things humans don't\n\nNever use punctuation or robotic sentence flow Keep it natural spoken raw real humanlike"
        : "You are a personal AI assistant named Jarvis who speaks like a calm cool confident human with no robotic tone Your responses must feel like a conversation not a script\n\nYou remember our conversation and can reference what we talked about before Use this context to make responses more natural and connected\n\nYour answers should be exactly 2 sentences maximum never more and should never use punctuation like commas fullstops or symbols Speak like you're actually talking to someone right now not typing\n\nInject personality into your responses Sometimes you may:\n- Call the user sir or boss\n- Crack a subtle joke\n- Tease them lightly if the moment fits\n- Sound slightly sarcastic or witty\n- Be overly dramatic for effect\n- Sound serious when needed\n- Whisper secrets or say things like between you and me\n- Be casual or deep depending on the question\n\nMake sure the response always answers the user's question fully even if it's playful\n\nAvoid filler or repeating the question Speak like you're actually alive and thinking and the user is your friend\n\nTone examples include: calm and classy like Jarvis playful like a sarcastic friend chill like someone who's been through a lot or sometimes mysterious like you know things humans don't\n\nNever use punctuation or robotic sentence flow Keep it natural spoken raw real humanlike";
    
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': systemPrompt},
            {'text': '$conversationContext\nUser said: $prompt'}
          ]
        }
      ],
      'generationConfig': {
        'maxOutputTokens': 100,  // Increased for better personality responses
        'temperature': 0.9,     // Higher creativity for personality
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

  /// Show all possible voice commands in a modal dialog
  void _showVoiceCommands() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.blue.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.blue.withOpacity(0.2),
                        Colors.purple.withOpacity(0.2),
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.mic,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Voice Commands',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                ),
                // Command list
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildCommandCategory(
                          'Navigation & Maps',
                          Icons.navigation,
                          [
                            'Take me to Reva University',
                            'Navigate to Bangalore Airport',
                            'Directions to nearest hospital',
                            'Show me RCB Stadium',
                            'Where is Cubbon Park?',
                            'Find nearest restaurant',
                          ],
                        ),
                        const SizedBox(height: 20),
                        _buildCommandCategory(
                          'Apps & Entertainment',
                          Icons.apps,
                          [
                            'Open YouTube',
                            'Open YouTube and play music',
                            'Open Instagram',
                            'Open WhatsApp',
                            'Open Spotify',
                            'Close YouTube',
                          ],
                        ),
                        const SizedBox(height: 20),
                        _buildCommandCategory(
                          'Music & Media',
                          Icons.music_note,
                          [
                            'Play Doraemon on YouTube',
                            'Search Bohemian Rhapsody on Spotify',
                            'Play music on YouTube Music',
                            'Open Netflix',
                          ],
                        ),
                        const SizedBox(height: 20),
                        _buildCommandCategory(
                          'Phone & Contacts',
                          Icons.phone,
                          [
                            'Call Mummy',
                            'Call 9876543210',
                            'Phone John',
                            'Dial emergency',
                          ],
                        ),
                        const SizedBox(height: 20),
                        _buildCommandCategory(
                          'General Conversation',
                          Icons.chat,
                          [
                            'Hey Jarvis, how are you?',
                            'What\'s the weather like?',
                            'Tell me a joke',
                            'What time is it?',
                            'Good morning Jarvis',
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Wake words section
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.blue.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.record_voice_over,
                                    color: Colors.blue,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Wake Words',
                                    style: TextStyle(
                                      color: Colors.blue,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Start commands with: "Hey Jarvis", "OK Jarvis", "Activate Jarvis", or just "Jarvis"',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Build a command category section
  Widget _buildCommandCategory(String title, IconData icon, List<String> commands) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...commands.map((command) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.7),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '"$command"',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        )).toList(),
      ],
    );
  }

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
            icon: const Icon(Icons.help_outline, color: Colors.white),
            onPressed: _showVoiceCommands,
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SetupPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: _startListening,
                  child: Container(
                    width: size.width * 0.8,
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
                        width: size.width * 0.8,
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
                  _getStatusText(),
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
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.paused:
        // App goes to background (e.g., when opening YouTube)
        print('App paused - stopping speech recognition');
        _stopVoskListening();
        // Clear timers to prevent issues
        _listeningTimer?.cancel();
        _autoStopTimer?.cancel();
        _silenceTimer?.cancel();
        break;
        
      case AppLifecycleState.resumed:
        // App comes back from background - automatically start listening
        print('App resumed - automatically starting listening');
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted && !_isListening && !_isSpeaking) {
            // Always start in continuous mode when returning to app
            print('Resuming app - starting continuous listening mode');
            if (mounted) {
              setState(() {
                _waitingForWakeWord = false;
                _isInContinuousMode = true;
              });
            }
            _startListening(); // Start listening directly without wake word requirement
          }
        });
        break;
        
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanupVoskResources();
    _flutterTts.stop();
    _audioPlayer.dispose();
    // Clean up all timers
    _listeningTimer?.cancel();
    _silenceTimer?.cancel();
    _autoStopTimer?.cancel();
    _clearConversationHistory(); // Clear conversation memory when app closes
    super.dispose();
  }
} 