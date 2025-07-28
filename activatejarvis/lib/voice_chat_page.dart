import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:siri_wave/siri_wave.dart';
import 'assistant_core.dart';
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

class _VoiceChatPageState extends State<VoiceChatPage> with WidgetsBindingObserver {
  final stt.SpeechToText _speech = stt.SpeechToText();
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
  bool _isBluetoothConnected = false;
  
  // Conversation memory
  List<Map<String, String>> _conversationHistory = []; // Store conversation context
  final int _maxConversationHistory = 10; // Keep last 10 exchanges for context

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAssistantName(); // Load assistant name from SharedPreferences
    _initializeTTS();
    _checkBluetoothConnection();
    _findConnectedBluetoothDevice();
    _startListening();
    // Periodically check Bluetooth connection
    _startBluetoothMonitoring();
  }

  // Load assistant name from SharedPreferences
  Future<void> _loadAssistantName() async {
    final prefs = await SharedPreferences.getInstance();
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
            
            // Priority 1: British male voices with specific patterns
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
                  String locale = voice['locale'].toString().toLowerCase();
                  if (locale.contains('en-gb') || locale.contains('gb')) {
                    print('✅ Found British voice (any gender): ${voice['name']}');
                    return true;
                  }
                  return false;
                },
                orElse: () => voices.firstWhere(
                  (voice) {
                    String locale = voice['locale'].toString().toLowerCase();
                    if (locale.contains('en')) {
                      print('✅ Found English voice (any gender): ${voice['name']}');
                      return true;
                    }
                    return false;
                  },
                  orElse: () {
                    print('⚠️ Using first available voice: ${voices.first['name']}');
                    return voices.first;
                  },
                ),
              ),
            ),
          ),
        );
        
        print('🎯 SELECTED VOICE: ${targetVoice['name']} (${targetVoice['locale']}) Gender: ${targetVoice['gender'] ?? 'unknown'}');
        
        await _flutterTts.setVoice({
          'name': targetVoice['name'],
          'locale': targetVoice['locale']
        });
        
        // Additional verification - try to set voice by exact name if it's the British English Male Voice 1
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
                     voiceName.contains('david') || voiceName.contains('john');
        print('Voice is likely male: $isMale (Gender: $voiceGender)');
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

  Future<void> _configureTTSOutput() async {
    // Use the Jarvis TTS configuration
    await _configureJarvisTTS();
    
    // Additional logging for debugging
    print('TTS configured with Jarvis voice settings');
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
    // Clear any existing timers
    _autoStopTimer?.cancel();
    _silenceTimer?.cancel();
    
    bool available = await _speech.initialize(
      onStatus: (val) async {
        print('Speech status: $val'); // Debug log
        if (val == 'done' || val == 'notListening') {
          // Play stop listening sound
          await _playStopListeningSound();
          if (mounted) {
            setState(() => _isListening = false);
          }
          
          // Don't process speech here - wait for final result in onResult callback
          // This prevents processing partial results when status changes to "done"
          
        } else if (_waitingForWakeWord && mounted && !_processingSpeech) {
          // Only restart wake word listening if no speech was detected
          if (_lastWords.isEmpty && (val == 'notListening' || val == 'done')) {
            print('No speech detected while waiting for wake word, restarting...');
            Future.delayed(const Duration(milliseconds: 1000), () {
              if (mounted && _waitingForWakeWord && _lastWords.isEmpty) {
                _startWakeWordListening();
              }
            });
          }
        }
      },
      onError: (val) {
        print('Speech error: $val');
        if (mounted) {
          setState(() => _isListening = false);
        }
        if (_waitingForWakeWord && mounted) {
          _startWakeWordListening();
        }
      },
    );
    
    if (available) {
      // Play start listening sound before starting speech recognition
      await _playStartListeningSound();
      setState(() => _isListening = true);
      
      // Set auto-stop timer (10 seconds for normal listening, 30 seconds for wake word)
      int autoStopDuration = _waitingForWakeWord ? 30 : 10;
      _autoStopTimer = Timer(Duration(seconds: autoStopDuration), () {
        if (_isListening && mounted) {
          print('Auto-stopping listening after ${autoStopDuration}s of no input');
          _speech.stop();
          if (_isInContinuousMode && !_waitingForWakeWord) {
            // Enter wake word waiting mode
            if (mounted) {
              setState(() => _waitingForWakeWord = true);
            }
            Future.delayed(const Duration(milliseconds: 1000), () {
              if (mounted) {
                _startWakeWordListening();
              }
            });
          } else if (_waitingForWakeWord) {
            // Restart wake word listening
            Future.delayed(const Duration(milliseconds: 1000), () {
              if (mounted && _waitingForWakeWord) {
                _startWakeWordListening();
              }
            });
          }
        }
      });
      
      _speech.listen(
        onResult: (val) {
          print('Speech result - Final: ${val.finalResult}, Text: "${val.recognizedWords}"'); // Debug log
          if (mounted) {
            setState(() {
              // Always update with the latest recognized words
              _lastWords = val.recognizedWords;
            });
          }
          
          // Reset silence timer when we get speech input
          _silenceTimer?.cancel();
          if (!val.finalResult) {
            // Start silence timer for partial results - longer for wake word mode
            int silenceDuration = _waitingForWakeWord ? 3 : 2;
            _silenceTimer = Timer(Duration(seconds: silenceDuration), () {
              if (_isListening && !val.finalResult && mounted) {
                print('Silence detected, stopping listening');
                _speech.stop();
              }
            });
          } else {
            // Final result received - process the speech now
            _silenceTimer?.cancel();
            print('Final result received: "${val.recognizedWords}"');
            
            // Process speech when we get the final result
            if (val.recognizedWords.isNotEmpty && !_processingSpeech) {
              _processingSpeech = true;
              print('🎯 Processing final speech: "${val.recognizedWords}"'); // Debug log
              print('🔧 Current state - Waiting for wake word: $_waitingForWakeWord, Continuous mode: $_isInContinuousMode');
              print('🎵 Current flags: isListening=$_isListening, isSpeaking=$_isSpeaking');
              
              // Process the final result asynchronously
              Future.microtask(() async {
                try {
                  // If we're waiting for wake word, check for wake word first
                  if (_waitingForWakeWord) {
                    print('Checking for wake word in: "${val.recognizedWords}"');
                    bool hasWakeWord = _containsWakeWord(val.recognizedWords);
                    print('Wake word detected: $hasWakeWord');
                    
                    if (hasWakeWord) {
                      print('Wake word detected: "${val.recognizedWords}"');
                      
                      // Process the wake word and extract command
                      String processedText = _processWakeWords(val.recognizedWords);
                      print('Processed text after wake word removal: "$processedText"');
                      
                      // Check if this is a "close YouTube" command specifically
                      if (processedText.toLowerCase().contains('close youtube') || 
                          processedText.toLowerCase().contains('exit youtube') ||
                          processedText.toLowerCase().contains('stop youtube')) {
                        print('Close YouTube command detected from wake word: "$processedText"');
                        // Handle the close YouTube command directly
                        await _handleUserSpeech(processedText);
                      } else if (processedText.trim().isNotEmpty && processedText.trim() != val.recognizedWords.trim() && processedText != "hello") {
                        // There's a command after wake word, execute it immediately
                        print('Wake word + command detected: "$processedText"');
                        if (mounted) {
                          setState(() {
                            _waitingForWakeWord = false;
                            _isInContinuousMode = true;
                          });
                        }
                        await _handleUserSpeech(processedText);
                      } else {
                        // Just wake word, acknowledge and start listening for command
                        if (mounted) {
                          setState(() {
                            _waitingForWakeWord = false;
                            _isInContinuousMode = true;
                          });
                        }
                        await _speakResponse("Yes, I'm listening!");
                      }
                    } else {
                      print('No wake word detected while waiting, continuing to wait...');
                      print('Looking for assistant name: $_assistantName or alternatives like jarvis, tyesia');
                      
                      // If user said something but no wake word detected, just continue listening silently
                      if (val.recognizedWords.trim().length > 2) {
                        print('User said something but no wake word: "${val.recognizedWords}"');
                        // Don't give hint, just continue listening silently
                        Future.delayed(const Duration(milliseconds: 500), () {
                          if (mounted && _waitingForWakeWord) {
                            _startWakeWordListening();
                          }
                        });
                      } else {
                        Future.delayed(const Duration(milliseconds: 500), () {
                          if (mounted && _waitingForWakeWord) {
                            _startWakeWordListening();
                          }
                        });
                      }
                    }
                  } else {
                    // Normal command processing (not waiting for wake word)
                    String processedText = _processWakeWords(val.recognizedWords);
                    if (processedText.trim().isNotEmpty && processedText.trim() != val.recognizedWords.trim()) {
                      // Wake word found and removed, use processed text
                      await _handleUserSpeech(processedText);
                    } else {
                      // No wake word, use original text
                      await _handleUserSpeech(val.recognizedWords);
                    }
                  }
                } finally {
                  _processingSpeech = false;
                }
              });
            }
          }
        },
        listenFor: Duration(seconds: _waitingForWakeWord ? 30 : 20), // Increased duration
        pauseFor: Duration(seconds: _waitingForWakeWord ? 4 : 3),     // Increased pause
        cancelOnError: false,
        partialResults: true,
      );
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
    
    // Stop speech recognition
    if (_isListening) {
      await _speech.stop();
      await _playStopListeningSound();
    }
    
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

  // Helper method to check if text contains wake word
  bool _containsWakeWord(String text) {
    List<String> wakeWords = [
      _assistantName, 
      'hey $_assistantName', 
      'okay $_assistantName',
      'ok $_assistantName',
      // Common alternatives
      'jarvis', 
      'hey jarvis', 
      'okay jarvis',
      'ok jarvis',
      'tyesia', 
      'hey tyesia', 
      'okay tyesia',
      'ok tyesia',
      'assistant', 
      'hey assistant',
      'okay assistant',
      'ok assistant',
      'hello'
    ];
    String lowerText = text.toLowerCase().trim();
    
    print('Checking wake words in: "$lowerText"');
    print('Available wake words: ${wakeWords.join(", ")}');
    
    for (String wake in wakeWords) {
      if (lowerText.contains(wake)) {
        print('✅ Wake word found: "$wake" in "$text"');
        return true;
      }
    }
    print('❌ No wake word found in: "$text"');
    return false;
  }

  /// Get appropriate status text based on current mode
  String _getStatusText() {
    if (_isListening) {
      if (_waitingForWakeWord) {
        return 'Listening for commands...';
      }
      return 'Listening...';
    } else if (_isSpeaking) {
      return 'Speaking...';
    } else if (_waitingForWakeWord) {
      return 'Ready to listen...';
    } else if (_isInContinuousMode) {
      return 'Ready for next command...';
    } else if (!_waitingForWakeWord && !_isInContinuousMode) {
      // This indicates STT is completely off (like when any app is opened)
      return 'Come back when you need me';
    } else {
      return 'Ready to assist you';
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
  
  /// Speak response without going through Gemini
  /// If stopContinuousMode is true, the assistant will stop listening and wait for wake word
  Future<void> _speakResponse(String response, {bool stopContinuousMode = false}) async {
    setState(() {
      _messages.add({'role': 'assistant', 'text': response});
      _isSpeaking = true; // Set speaking state immediately
    });
    
    print('Starting TTS immediately for response: "$response"');
    
    // Configure TTS and start immediately - no delay
    await _configureTTSOutput();
    
    // Always stop listening before TTS
    if (_isListening) {
      await _speech.stop();
      await _playStopListeningSound();
      setState(() => _isListening = false);
    }
    
    // Clear any existing timers
    _listeningTimer?.cancel();
    _autoStopTimer?.cancel();
    _silenceTimer?.cancel();
    
    // Set TTS completion handler with better synchronization
    _flutterTts.setCompletionHandler(() async {
      print('TTS completed, preparing next action...');
      if (mounted) {
        setState(() => _isSpeaking = false);
      }
      
      // Shorter delay for faster response
      await Future.delayed(const Duration(milliseconds: 400));
      
      if (mounted && !_isListening && !_isSpeaking) {
        if (stopContinuousMode) {
          // Stop continuous mode, enter wake word waiting mode
          if (mounted) {
            setState(() {
              _isInContinuousMode = false;
              _waitingForWakeWord = true;
            });
          }
          print('Command executed, entering wake word mode...');
          _startWakeWordListening();
        } else {
          // Continue normal conversation mode
          if (mounted) {
            setState(() => _isInContinuousMode = true);
          }
          print('Continuing conversation mode...');
          _startListening();
        }
      }
    });
    
    // Reduced safety timeout
    _listeningTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && !_isListening && _isSpeaking) {
        print('TTS timeout - forcing restart of listening');
        if (mounted) {
          setState(() {
            _isSpeaking = false;
            if (stopContinuousMode) {
              _isInContinuousMode = false;
              _waitingForWakeWord = true;
              _startWakeWordListening();
            } else {
              _isInContinuousMode = true;
              _startListening();
            }
          });
        }
      }
    });
    
    // Start TTS immediately
    await speakAsJarvis(response);
  }

  Future<void> _handleUserSpeech(String userText) async {
    print('Raw speech input: "$userText"'); // Debug log
    
    // Ignore speech while we're speaking (TTS is active)
    if (_isSpeaking) {
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
    
    setState(() {
      _messages.add({'role': 'assistant', 'text': assistantReply});
      _isSpeaking = true; // Set speaking state immediately
    });
    
    // Add assistant response to conversation history
    _addToConversationHistory('assistant', assistantReply);
    
    print('Starting TTS immediately for: "$assistantReply"');
    
    // Configure TTS and start speaking immediately - no delay
    await _configureTTSOutput();
    
    // Always stop listening before TTS
    if (_isListening) {
      await _speech.stop();
      await _playStopListeningSound();
      setState(() => _isListening = false);
    }
    
    // Clear any existing timers
    _listeningTimer?.cancel();
    _autoStopTimer?.cancel();
    _silenceTimer?.cancel();
    
    // Set TTS completion handler to restart listening with proper synchronization
    _flutterTts.setCompletionHandler(() async {
      print('TTS completed, preparing to restart listening...');
      if (mounted) {
        setState(() => _isSpeaking = false);
      }
      
      // Shorter delay for faster response
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (mounted && !_isListening && !_isSpeaking) {
        // Enter continuous mode after Gemini response
        if (mounted) {
          setState(() => _isInContinuousMode = true);
        }
        print('Restarting listening after TTS completion...');
        _startListening(); // Restart listening automatically
      }
    });
    
    // Reduced safety timeout for faster response
    _listeningTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && !_isListening && _isSpeaking) {
        print('TTS timeout - forcing restart of listening');
        if (mounted) {
          setState(() {
            _isSpeaking = false;
            _isInContinuousMode = true;
          });
        }
        _startListening();
      }
    });
    
    // Start TTS immediately
    await speakAsJarvis(assistantReply);
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
      body: SafeArea(
        child: Column(
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
        ],
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
        if (_isListening) {
          _speech.stop();
          setState(() => _isListening = false);
        }
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
    _speech.stop();
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