import 'package:flutter/material.dart';
import 'jarvis_chat_page.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({Key? key}) : super(key: key);

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final TextEditingController _userNameController = TextEditingController();
  final TextEditingController _assistantNameController = TextEditingController(text: 'Jarvis');
  String _voiceType = 'Female';

  @override
  void dispose() {
    _userNameController.dispose();
    _assistantNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      // Removed AppBar
      body: Stack(
        children: [
          // Earbuds image at bottom right with 20% opacity
          Positioned(
            right: -size.width * 0.15,
            bottom: -size.height * 0.05,
            child: Opacity(
              opacity: 0.2,
              child: Image.asset(
                'assets/earbuds.png',
                width: size.width * 1.1,
                fit: BoxFit.contain,
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ],
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 24),
                          const Text(
                            "Let's Set Up Your\nSmart Assistant",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 40),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Your Name',
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _userNameController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white10,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Assistant Name',
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _assistantNameController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white10,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Voice Type',
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _voiceTypeButton('Male'),
                              _voiceTypeButton('Female'),
                              _voiceTypeButton('Neutral'),
                            ],
                          ),
                          const SizedBox(height: 36),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () {
                                // Deploy action
                                final assistantName = _assistantNameController.text.trim();
                                final userName = _userNameController.text.trim();
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (context) => JarvisChatPage(
                                      userName: userName.isEmpty ? 'User' : userName,
                                      assistantName: assistantName.isEmpty ? 'Jarvis' : assistantName,
                                    ),
                                  ),
                                );
                              },
                              child: Text(
                                'DEPLOY  ${_assistantNameController.text.isEmpty ? 'JARVIS' : _assistantNameController.text.toUpperCase()}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Charvers will be your voice in the dark.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
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
        ],
      ),
    );
  }

  Widget _voiceTypeButton(String type) {
    final isSelected = _voiceType == type;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: GestureDetector(
          onTap: () {
            setState(() {
              _voiceType = type;
            });
          },
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: isSelected ? Colors.white24 : Colors.white10,
              borderRadius: BorderRadius.circular(8),
              border: isSelected ? Border.all(color: Colors.blueAccent, width: 2) : null,
            ),
            child: Center(
              child: Text(
                type,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
} 