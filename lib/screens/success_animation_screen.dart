// lib/screens/success_animation_screen.dart
import 'package:flutter/material.dart';
import 'package:smart_resilience_app/screens/main_navigation.dart'; // Ensure this path is correct for your main navigation screen

class SuccessAnimationScreen extends StatefulWidget {
  const SuccessAnimationScreen({super.key});

  @override
  State<SuccessAnimationScreen> createState() => _SuccessAnimationScreenState();
}

class _SuccessAnimationScreenState extends State<SuccessAnimationScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  // Animation for the overall screen fade out
  late Animation<double> _fadeAnimation;
  // Animation for the large outer circle scaling in
  late Animation<double> _outerCircleScaleAnimation;
  // Animation for the inner circle scaling in
  late Animation<double> _innerCircleScaleAnimation;
  // Animation for the inner circle's subtle pulse
  late Animation<double> _innerCirclePulseAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 2500), // Total animation duration
      vsync: this,
    );

    // Fade animation for the entire screen at the end
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.8, 1.0, curve: Curves.easeOut), // Fades out in the last 20%
      ),
    );

    // Outer circle scales from 0 to 1
    _outerCircleScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack), // Scales in relatively quickly
      ),
    );

    // Inner circle scales from 0 to 1, slightly delayed
    _innerCircleScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOutBack), // Starts after outer, ends after outer
      ),
    );

    // Inner circle pulse animation (repeats after initial scale)
    _innerCirclePulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.7, 0.9, curve: Curves.easeInOut), // Pulses towards the end
      ),
    );

    // Add listener to navigate after animation completes
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) {
          // Navigate to the main navigation screen (home screen)
          // Using pushReplacement to prevent going back to the splash screen
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const MainNavigation(), // Your main navigation widget
            ),
          );
        }
      }
    });

    // Start the animation
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determine the primary color from your app's theme or define it
    // Assuming a light green/teal color from your image
    const Color primaryGreen = Color(0xFF66BB6A); // A shade of green that looks similar to your image

    return Scaffold(
      backgroundColor: primaryGreen, // Background color matching the image
      body: FadeTransition(
        opacity: _fadeAnimation, // Apply fade out to the entire screen
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Outer Circle (Large White Circle with Green Border)
                  Transform.scale(
                    scale: _outerCircleScaleAnimation.value,
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.8, // 80% of screen width
                      height: MediaQuery.of(context).size.width * 0.8, // Make it a circle
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(
                          color: primaryGreen,
                          width: 8.0, // Green border thickness
                        ),
                      ),
                    ),
                  ),
                  // Inner Circle (Smaller White Circle with Green Border and Pulse)
                  Transform.scale(
                    scale: _innerCircleScaleAnimation.value * _innerCirclePulseAnimation.value,
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.3, // 30% of screen width
                      height: MediaQuery.of(context).size.width * 0.3, // Make it a circle
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(
                          color: primaryGreen,
                          width: 8.0, // Green border thickness
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
