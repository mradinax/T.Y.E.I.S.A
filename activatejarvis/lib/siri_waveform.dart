import 'package:flutter/material.dart';
import 'dart:math' as math;

class SiriWaveform extends StatefulWidget {
  final bool isAnimating;
  final double width;
  final double height;
  final Color color;
  final Color backgroundColor;
  final int numberOfWaves;

  const SiriWaveform({
    Key? key,
    required this.isAnimating,
    this.width = 300,
    this.height = 100,
    this.color = Colors.blue,
    this.backgroundColor = Colors.transparent,
    this.numberOfWaves = 5,
  }) : super(key: key);

  @override
  State<SiriWaveform> createState() => _SiriWaveformState();
}

class _SiriWaveformState extends State<SiriWaveform>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late List<AnimationController> _waveControllers;
  late List<Animation<double>> _waveAnimations;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _waveControllers = List.generate(
      widget.numberOfWaves,
      (index) => AnimationController(
        duration: Duration(milliseconds: 800 + (index * 200)),
        vsync: this,
      ),
    );

    _waveAnimations = _waveControllers.map((controller) {
      return Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
    }).toList();

    if (widget.isAnimating) {
      _startAnimation();
    }
  }

  @override
  void didUpdateWidget(SiriWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAnimating != oldWidget.isAnimating) {
      if (widget.isAnimating) {
        _startAnimation();
      } else {
        _stopAnimation();
      }
    }
  }

  void _startAnimation() {
    _animationController.repeat();
    for (var controller in _waveControllers) {
      controller.repeat(reverse: true);
    }
  }

  void _stopAnimation() {
    _animationController.stop();
    for (var controller in _waveControllers) {
      controller.stop();
      controller.reset();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    for (var controller in _waveControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(widget.height / 2),
      ),
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return CustomPaint(
            painter: SiriWaveformPainter(
              animations: _waveAnimations,
              color: widget.color,
              isAnimating: widget.isAnimating,
            ),
            size: Size(widget.width, widget.height),
          );
        },
      ),
    );
  }
}

class SiriWaveformPainter extends CustomPainter {
  final List<Animation<double>> animations;
  final Color color;
  final bool isAnimating;

  SiriWaveformPainter({
    required this.animations,
    required this.color,
    required this.isAnimating,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final centerY = size.height / 2;
    
    // Draw multiple waveform bars
    const int numberOfBars = 30;
    final barWidth = size.width / numberOfBars;
    
    for (int i = 0; i < numberOfBars; i++) {
      final x = (i * barWidth) + (barWidth / 2);
      
      // Calculate height based on distance from center and animation
      final distanceFromCenter = (i - numberOfBars / 2).abs() / (numberOfBars / 2);
      final baseHeight = size.height * 0.1; // Minimum height when not animating
      
      double animatedHeight = baseHeight;
      
      if (isAnimating && animations.isNotEmpty) {
        // Use different animation controllers for different bars
        final animationIndex = i % animations.length;
        final animationValue = animations[animationIndex].value;
        
        // Create wave effect
        final waveEffect = math.sin((i / numberOfBars) * 2 * math.pi + 
                                   (animations[0].value * 4 * math.pi)) * 0.5 + 0.5;
        
        // Combine base animation with wave effect
        final heightMultiplier = (animationValue * waveEffect + 0.2) * 
                                (1.0 - distanceFromCenter * 0.6);
        
        animatedHeight = baseHeight + (size.height * 0.4 * heightMultiplier);
      }
      
      // Draw the bar
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, centerY),
          width: barWidth * 0.6,
          height: animatedHeight,
        ),
        Radius.circular(barWidth * 0.3),
      );
      
      // Apply opacity based on animation state
      final opacity = isAnimating ? 
        (0.6 + 0.4 * (animations[i % animations.length].value)) : 0.3;
      
      paint.color = color.withOpacity(opacity);
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(SiriWaveformPainter oldDelegate) {
    return oldDelegate.isAnimating != isAnimating ||
           oldDelegate.color != color;
  }
}
