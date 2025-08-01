import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'setup_page.dart';
import 'jarvis_chat_page.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _revealAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _revealAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    _controller.forward();
    
    // Check if we should navigate after animation
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _checkSetupStatus();
      }
    });
  }

  Future<void> _checkSetupStatus() async {
    // Wait longer to show the splash screen properly
    await Future.delayed(const Duration(seconds: 3));
    
    final prefs = await SharedPreferences.getInstance();
    bool setupCompleted = prefs.getBool('setup_completed') ?? false;
    
    if (setupCompleted) {
      // Get saved user data and navigate to chat page
      String userName = prefs.getString('user_name') ?? 'User';
      String assistantName = prefs.getString('assistant_name') ?? 'Jarvis';
      
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => JarvisChatPage(
            userName: userName,
            assistantName: assistantName,
          ),
        ),
      );
    } else {
      // Navigate to setup page
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const SetupPage()),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // Removed AppBar
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Center(
                child: FadeTransition(
                  opacity: _revealAnimation,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/earbuds.png',
                        width: 400,
                        height: 400,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        'T.Y.E.I.S.A',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          '"Turn Your Earbuds into a Smart Assistant – Hear the Future."',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
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