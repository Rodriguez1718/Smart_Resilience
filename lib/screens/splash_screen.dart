import 'package:flutter/material.dart';
import 'package:smart_resilience_app/screens/guardian_login_page.dart'; // Import your GuardianLoginPage
import 'package:smart_resilience_app/screens/admin_dashboard_page.dart'; // Import the AdminDashboardPage

// CustomPainter for drawing the graph lines
class GraphPainter extends CustomPainter {
  final Color lineColor;
  final double strokeWidth;
  final double cellSize; // Size of each grid cell

  GraphPainter({
    this.lineColor = Colors.grey, // Default line color
    this.strokeWidth = 0.5, // Default line thickness
    this.cellSize = 40.0, // Default cell size (e.g., 40x40 pixels)
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    // Draw vertical lines
    for (double i = 0; i <= size.width; i += cellSize) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }

    // Draw horizontal lines
    for (double i = 0; i <= size.height; i += cellSize) {
      canvas.drawLine(Offset(0, i), Offset(0, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    // Only repaint if properties change
    return oldDelegate is GraphPainter &&
        (oldDelegate.lineColor != lineColor ||
            oldDelegate.strokeWidth != strokeWidth ||
            oldDelegate.cellSize != cellSize);
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  // Animations for the ripple effect (splash phase)
  late Animation<double> _rippleRadiusAnimation;
  late Animation<double> _rippleOpacityAnimation;

  // Animations for the icon's vertical movement
  late Animation<double> _iconOffsetAnimation;

  // Animations for the welcome content (fade and slide up from bottom)
  late Animation<double> _welcomeContentOpacityAnimation;
  late Animation<double>
  _welcomeContentBottomOffsetAnimation; // For sliding up welcome content

  // Color Animations for icon circle and icon itself
  late Animation<Color?> _iconCircleColorAnimation;
  late Animation<Color?> _iconColorAnimation;

  // Hard-coded PIN and state for admin features
  static const String _adminPin = '123456';
  final TextEditingController _pinController = TextEditingController();
  String _errorMessage = '';

  // Function to show the admin login dialog
  void _showAdminLoginDialog() {
    showDialog(
      context: context,
      barrierDismissible:
          false, // Prevents closing the dialog by tapping outside
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.green.shade50, // Light green background
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'Admin Login',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade800, // Dark green title
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Enter your 6-digit PIN to access admin features',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.green.shade600, // Matching text color
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Custom PIN entry widget
                    SizedBox(
                      height: 50,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // This is the actual TextField, but it's invisible
                          TextField(
                            controller: _pinController,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            textAlign: TextAlign.center,
                            autofocus: true,
                            showCursor: false,
                            decoration: const InputDecoration(
                              counterText: '',
                              border: InputBorder.none,
                            ),
                            style: const TextStyle(color: Colors.transparent),
                            onChanged: (pin) {
                              setState(() {
                                _errorMessage = '';
                              });
                            },
                          ),
                          // This is the visual representation of the PIN
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(6, (index) {
                              bool isFilled =
                                  index < _pinController.text.length;
                              return Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                width: 24,
                                child: Text(
                                  isFilled ? '*' : '_',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: isFilled
                                        ? Colors.green.shade800
                                        : Colors
                                              .green
                                              .shade200, // Subtle color change
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                    // Error message display
                    if (_errorMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          _errorMessage,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _pinController.clear();
                    setState(() {
                      _errorMessage = '';
                    });
                  },
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.green.shade700,
                    ), // Matching theme color
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Validate the PIN
                    if (_pinController.text == _adminPin) {
                      Navigator.of(context).pop();
                      _pinController.clear();
                      // Redirect to the AdminDashboardPage
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const AdminDashboardPage(), // Correct redirection to AdminDashboardPage
                        ),
                      );
                    } else {
                      setState(() {
                        _errorMessage = 'Incorrect PIN. Please try again.';
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child: const Text(
                    'Login',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();

    // Increased total duration for the loading screen part
    _controller = AnimationController(
      duration: const Duration(seconds: 5), // Increased from 3 to 5 seconds
      vsync: this,
    );

    // Ripple effect: runs during the first half of the controller's duration
    _rippleRadiusAnimation = Tween<double>(begin: 0, end: 160).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _rippleOpacityAnimation =
        Tween<double>(
          begin: 0.4,
          end: 0, // Fades to transparent as it expands
        ).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
          ),
        );

    // Icon's vertical movement: starts when welcome content begins to appear
    _iconOffsetAnimation =
        Tween<double>(
          begin: 0.0, // Initially centered
          end: -80.0, // Move up by 80 pixels (adjust as needed)
        ).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic),
          ),
        );

    // Welcome content opacity: fades in during the second half
    _welcomeContentOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(
              0.6,
              1.0,
              curve: Curves.easeIn,
            ), // Delay slightly for effect
          ),
        );

    // Welcome content slide up from bottom:
    _welcomeContentBottomOffsetAnimation =
        Tween<double>(
          begin: -200.0, // Starts off-screen below
          end: 160.0, // Final desired bottom padding
        ).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.6, 1.0, curve: Curves.easeOutCubic),
          ),
        );

    // Define ColorTweens
    _iconCircleColorAnimation =
        ColorTween(
          begin: Colors.lightGreen.shade200, // Pale green start
          end: Colors.green, // Original green end
        ).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(
              0.0,
              0.5,
              curve: Curves.easeOut,
            ), // Animate during loading phase
          ),
        );

    _iconColorAnimation =
        ColorTween(
          begin: Colors.black, // Black start
          end: Colors.white, // White end
        ).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(
              0.0,
              0.5,
              curve: Curves.easeOut,
            ), // Animate during loading phase
          ),
        );

    // Start the animation forward. It will run once and stop at the end.
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Keep background white
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final bool isWelcomePhase = _controller.value > 0.5;

            return Stack(
              children: [
                // Graph Lines in the background
                Positioned.fill(
                  child: CustomPaint(
                    painter: GraphPainter(
                      lineColor: Colors.grey.withOpacity(
                        0.1,
                      ), // Very subtle grey lines
                      strokeWidth: 0.5,
                      cellSize: 40.0, // Adjust cell size as desired
                    ),
                  ),
                ),

                // 1. Icon and Ripple Effect - Centered initially, moves up
                Positioned(
                  left: 0,
                  right: 0,
                  top:
                      (MediaQuery.of(context).size.height / 2) -
                      50 +
                      _iconOffsetAnimation.value,
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // The Ripple Effect
                        Container(
                          width: _rippleRadiusAnimation.value,
                          height: _rippleRadiusAnimation.value,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.green.withOpacity(
                              _rippleOpacityAnimation.value,
                            ),
                          ),
                        ),
                        // The main icon's background circle
                        SizedBox(
                          width: 100,
                          height: 100,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _iconCircleColorAnimation.value,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.green.withOpacity(0.8),
                                  blurRadius: 10.0,
                                  spreadRadius: 4.0,
                                ),
                                BoxShadow(
                                  color: Colors.green.withOpacity(0.5),
                                  blurRadius: 20.0,
                                  spreadRadius: 8.0,
                                ),
                                BoxShadow(
                                  color: Colors.green.withOpacity(0.3),
                                  blurRadius: 30.0,
                                  spreadRadius: 12.0,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Icon(
                                Icons.location_on,
                                color: _iconColorAnimation.value,
                                size: 50,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. Main content: text, description, and button
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: _welcomeContentBottomOffsetAnimation.value,
                  child: Opacity(
                    // Changed AnimatedOpacity to Opacity, as parent AnimatedBuilder handles it.
                    opacity: _welcomeContentOpacityAnimation.value,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isWelcomePhase
                                ? "Welcome to Smart Resilience"
                                : "Setting up your child safety monitoring system",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.black87,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isWelcomePhase
                                ? "Your child safety monitoring system is ready"
                                : "Please wait while we initialize services.",
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 32), // Keep vertical space
                          // The "Get Started" button - now part of the same animation
                          ElevatedButton(
                            onPressed: () {
                              // Redirect to GuardianLoginPage
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const GuardianLoginPage(),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30.0),
                              ),
                            ),
                            child: const Text(
                              "Get Started",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 3. Feature list at the bottom
                Positioned(
                  bottom: 24,
                  left: 0,
                  right: 0,
                  child: Opacity(
                    // Changed AnimatedOpacity to Opacity, as parent AnimatedBuilder handles it.
                    opacity: _welcomeContentOpacityAnimation.value,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: const [
                        Text(
                          "• Location Tracking",
                          style: TextStyle(color: Colors.green, fontSize: 14),
                        ),
                        Text(
                          "• Real-time Alerts",
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          "• Emergency Response",
                          style: TextStyle(color: Colors.black, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),

                // Admin text positioned with more top padding
                // Placed last to ensure it's on top of other content
                Positioned(
                  top: 24, // Moved up from 48
                  right: 16,
                  child: Opacity(
                    opacity: _welcomeContentOpacityAnimation.value,
                    child: TextButton(
                      onPressed: _showAdminLoginDialog,
                      child: Text(
                        'Admin',
                        style: TextStyle(
                          color: Colors.black.withOpacity(
                            0.4,
                          ), // Reduced opacity
                          fontSize: 12, // Reduced font size
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
