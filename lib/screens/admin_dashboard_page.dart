import 'package:flutter/material.dart';

// The main entry point of the application
void main() {
  runApp(const MyApp());
}

// The root widget of the application
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Resilience Analytics',
      theme: ThemeData(
        primarySwatch: Colors.green,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'Inter',
      ),
      // Define the routes for navigation
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/dashboard': (context) => const AdminDashboardPage(),
      },
    );
  }
}

// A simple splash screen
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // We use a Future.delayed to simulate a loading period and then navigate
    // to the main dashboard.
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.of(context).pushReplacementNamed('/dashboard');
    });

    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // A simple circular progress indicator to show loading
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
            ),
            SizedBox(height: 20),
            Text(
              'Loading Smart Resilience Analytics...',
              style: TextStyle(fontSize: 18, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom painter for drawing a simple line graph
class AlertGraphPainter extends CustomPainter {
  final List<double> data;
  final Color graphColor;
  final Color backgroundColor;

  AlertGraphPainter({
    required this.data,
    this.graphColor = Colors.white,
    this.backgroundColor = Colors.green,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = graphColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    // Find the min and max values for scaling
    final minData = data.reduce((a, b) => a < b ? a : b);
    final maxData = data.reduce((a, b) => a > b ? a : b);
    final dataRange = (maxData - minData) == 0 ? 1 : (maxData - minData);

    // Calculate scaling factors
    final xStep = size.width / (data.length - 1);
    final yScale = size.height / dataRange;

    // Move to the starting point
    path.moveTo(0, size.height - ((data[0] - minData) * yScale));

    // Draw the path for the data points
    for (int i = 1; i < data.length; i++) {
      final x = i * xStep;
      final y = size.height - ((data[i] - minData) * yScale);
      path.lineTo(x, y);
    }

    // Draw a background fill for the graph area
    final backgroundPath = Path.from(path);
    backgroundPath.lineTo(size.width, size.height);
    backgroundPath.lineTo(0, size.height);
    backgroundPath.close();
    canvas.drawPath(
      backgroundPath,
      Paint()..color = backgroundColor.withOpacity(0.2),
    );

    // Draw the main line
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(AlertGraphPainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.graphColor != graphColor;
  }
}

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Mock data for the dashboard
    final weeklyData = [1.0, 3.0, 5.0, 4.0, 2.0, 6.0, 4.0];
    final locations = [
      {
        'title': 'Central Park Area',
        'alerts': 2,
        'last_alert': '27 days ago',
        'tags': ['Public Park', 'High Traffic', 'Recreation'],
        'risk': 'High risk',
      },
      {
        'title': 'School District 5',
        'alerts': 3,
        'last_alert': '45 days ago',
        'tags': ['School Zone', 'Children Area', 'Peak Hours'],
        'risk': 'High risk',
      },
      {
        'title': 'Downtown Mall',
        'alerts': 2,
        'last_alert': '1 month ago',
        'tags': ['Shopping Center', 'Crowded', 'Indoor'],
        'risk': 'High risk',
      },
      {
        'title': 'Riverside Park',
        'alerts': 4,
        'last_alert': '3 months ago',
        'tags': ['Waterfront', 'Recreation', 'Evening Activity'],
        'risk': 'High risk',
      },
      {
        'title': 'Community Center',
        'alerts': 2,
        'last_alert': '1 week ago',
        'tags': ['Community Hub', 'Events', 'Safe Zone'],
        'risk': 'High risk',
      },
    ];

    // Use PopScope to handle the back button on Android.
    // The `onPopInvoked` callback will be called when a back gesture is made.
    return PopScope(
      canPop:
          false, // Prevents the route from being popped by the system back button.
      onPopInvoked: (bool didPop) {
        if (didPop) {
          // The pop was successful, so no need to do anything.
          return;
        }
        // Navigate back to the splash screen and replace the current route.
        // This prevents the user from going back to the dashboard from the splash screen.
        Navigator.of(context).pushReplacementNamed('/splash');
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        // The updated AppBar to match the provided design.
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 4.0,
          toolbarHeight: 80,
          title: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.green,
                radius: 20,
                child: Icon(Icons.location_pin, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              // Use Expanded to allow the text to take up the available space
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: const <TextSpan>[
                          const TextSpan(
                            // Added const here
                            text: 'Smart Resilience',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                          const TextSpan(
                            // Added const here
                            text: ' Analytics',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Panic Button Usage Dashboard',
                      style: TextStyle(fontSize: 10, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: const Text(
                  'Export Report',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Analytics Cards
              Wrap(
                spacing: 16.0,
                runSpacing: 16.0,
                children: [
                  // Total Panic Button Presses Card
                  DashboardCard(
                    title: 'Total Panic Button Presses',
                    value: '37',
                    subtitle: '+1 from yesterday',
                    icon: Icons.error_outline,
                    iconColor: Colors.red,
                  ),
                  // Today's Alerts Card
                  DashboardCard(
                    title: "Today's Alerts",
                    value: '2',
                    subtitle: 'Above average',
                    icon: Icons.star_border,
                    iconColor: Colors.amber,
                  ),
                  // Weekly Average Card with Graph
                  DashboardCard(
                    title: 'Weekly Average',
                    value: '4',
                    subtitle: '',
                    icon: Icons.bar_chart,
                    iconColor: Colors.green,
                    child: SizedBox(
                      height: 50,
                      width: 100,
                      child: CustomPaint(
                        painter: AlertGraphPainter(
                          data: weeklyData,
                          graphColor: Colors.green,
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Top Alert Locations Section
              Card(
                elevation: 4.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Top Alert Locations',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () {},
                                child: const Text('List'),
                              ),
                              TextButton(
                                onPressed: () {},
                                child: const Text('Map'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // List of Top Alert Locations
                      ...locations
                          .map((loc) => LocationCard(data: loc))
                          .toList(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Widget for the main dashboard cards (metrics)
class DashboardCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget? child;

  const DashboardCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    this.icon,
    this.iconColor,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
                  ),
                ),
                if (icon != null) Icon(icon, color: iconColor, size: 24),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green.shade600,
                      ),
                    ),
                  ),
              ],
            ),
            if (child != null)
              Padding(padding: const EdgeInsets.only(top: 8.0), child: child),
          ],
        ),
      ),
    );
  }
}

// Widget for individual location cards
class LocationCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const LocationCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2.0,
      margin: const EdgeInsets.only(bottom: 12.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Text(
                '${data['alerts']}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data['title'],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${data['alerts']} alerts',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.circle, size: 4, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        'Last: ${data['last_alert']}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: (data['tags'] as List<String>)
                        .map(
                          (tag) => Chip(
                            label: Text(tag),
                            backgroundColor: Colors.grey.shade200,
                            labelStyle: const TextStyle(
                              fontSize: 10,
                              color: Colors.black54,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 0,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Text(
                data['risk'],
                style: TextStyle(
                  color: Colors.red.shade800,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
