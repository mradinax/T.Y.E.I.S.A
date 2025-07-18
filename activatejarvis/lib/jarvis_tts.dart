import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';

class JarvisTTS {
  final FlutterTts _flutterTts = FlutterTts();
  bool _initialized = false;

  JarvisTTS() {
    _init();
  }

  Future<void> _init() async {
    // Set language to British English
    await _flutterTts.setLanguage('en-GB');
    // Set speech rate and pitch
    await _flutterTts.setSpeechRate(0.4);
    await _flutterTts.setPitch(0.8);
    // Try to select the best British male voice
    await _setBestBritishMaleVoice();
    _initialized = true;
  }

  Future<void> _setBestBritishMaleVoice() async {
    final voices = await _flutterTts.getVoices;
    if (voices is List) {
      // 1. Strict: British male voice
      final maleGbVoice = voices.firstWhere(
        (v) => v is Map &&
            (v['locale'] == 'en-GB' || v['locale']?.toString().startsWith('en-GB') == true) &&
            ((v['name']?.toString().toLowerCase().contains('male') == true) ||
             (v['gender']?.toString().toLowerCase() == 'male')),
        orElse: () => null,
      );
      if (maleGbVoice != null) {
        await _flutterTts.setVoice(maleGbVoice);
        debugPrint('JarvisTTS: Using British male voice: ${maleGbVoice['name'] ?? maleGbVoice}');
        return;
      }
      // 2. Fallback: any British voice
      final gbVoice = voices.firstWhere(
        (v) => v is Map && (v['locale'] == 'en-GB' || v['locale']?.toString().startsWith('en-GB') == true),
        orElse: () => null,
      );
      if (gbVoice != null) {
        await _flutterTts.setVoice(gbVoice);
        debugPrint('JarvisTTS: Using fallback British voice: ${gbVoice['name'] ?? gbVoice}');
        return;
      }
      // 3. Fallback: any male voice
      final anyMaleVoice = voices.firstWhere(
        (v) => v is Map && ((v['name']?.toString().toLowerCase().contains('male') == true) || (v['gender']?.toString().toLowerCase() == 'male')),
        orElse: () => null,
      );
      if (anyMaleVoice != null) {
        await _flutterTts.setVoice(anyMaleVoice);
        debugPrint('JarvisTTS: Using fallback male voice: ${anyMaleVoice['name'] ?? anyMaleVoice}');
        return;
      }
      // 4. Fallback: default
      debugPrint('JarvisTTS: No British or male voice found, using default.');
    }
  }

  /// Speaks the given [text] aloud.
  Future<void> speak(String text) async {
    if (!_initialized) await _init();
    await _flutterTts.speak(text);
  }

  /// Stops any ongoing speech.
  Future<void> stop() async {
    await _flutterTts.stop();
  }

  /// Lists all available voices and prints them to the debug console.
  Future<void> listVoices() async {
    final voices = await _flutterTts.getVoices;
    if (voices is List) {
      for (final v in voices) {
        debugPrint('Voice: ${v.toString()}');
      }
    } else {
      debugPrint('No voices found or unexpected format.');
    }
  }
}

/*
Sample usage in a Flutter widget:

import 'package:flutter/material.dart';
import 'jarvis_tts.dart';

class JarvisButton extends StatelessWidget {
  final JarvisTTS jarvisTTS = JarvisTTS();

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () {
        jarvisTTS.speak('System boot complete, sir.');
      },
      child: Text('Activate Jarvis'),
    );
  }
}
*/ 