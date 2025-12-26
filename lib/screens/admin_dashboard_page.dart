import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:csv/csv.dart';
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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

    final path = ui.Path();

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
    final backgroundPath = ui.Path.from(path);
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

// Model for panic button alerts
class PanicAlert {
  final String deviceId;
  final double lat;
  final double lng;
  final int timestamp;
  final String status;
  final String? childName; // NEW: Store child name

  PanicAlert({
    required this.deviceId,
    required this.lat,
    required this.lng,
    required this.timestamp,
    required this.status,
    this.childName,
  });
}

// NEW: Model for user feedback
class FeedbackItem {
  final String id;
  final String userId;
  final String userName;
  final String userPhone;
  final String category;
  final String feedbackText;
  final DateTime timestamp;
  final String status;

  FeedbackItem({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userPhone,
    required this.category,
    required this.feedbackText,
    required this.timestamp,
    required this.status,
  });

  factory FeedbackItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FeedbackItem(
      id: doc.id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? 'Anonymous',
      userPhone: data['userPhone'] ?? 'Unknown',
      category: data['category'] ?? 'General',
      feedbackText: data['feedbackText'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: data['status'] ?? 'unread',
    );
  }
}

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  List<PanicAlert> _allAlerts = [];
  Map<String, int> _alertsByLocation = {};
  Map<String, String> _deviceNameCache = {}; // NEW: Cache for device names
  int _totalAlerts = 0;
  int _todayAlerts = 0;
  List<double> _weeklyData = [0, 0, 0, 0, 0, 0, 0];
  StreamSubscription<DatabaseEvent>? _alertsSubscription;
  bool _showMap = false;
  bool _showReports = false; // NEW: Track if reports view is shown
  bool _showFeedback = false; // NEW: Track if feedback view is shown
  String _selectedPeriod =
      'Week'; // NEW: Selected period for reports (Week, Month, Year)
  late DateTime _selectedReportDate; // NEW: Selected date for report filtering

  @override
  void initState() {
    super.initState();
    _selectedReportDate = DateTime.now(); // Initialize to today
    _preloadChildNames(); // Load child names first
    _loadAlertsFromFirebase();
  }

  // NEW: Preload child names from all guardians
  Future<void> _preloadChildNames() async {
    try {
      final guardians = await FirebaseFirestore.instance
          .collection('guardians')
          .get();

      for (var guardianDoc in guardians.docs) {
        final deviceInfo = await guardianDoc.reference
            .collection('paired_device')
            .doc('device_info')
            .get();

        if (deviceInfo.exists) {
          final data = deviceInfo.data() as Map<String, dynamic>;
          final deviceId = data['deviceId'] as String?;
          final childName = data['childName'] as String?;

          if (deviceId != null && childName != null) {
            _deviceNameCache[deviceId] = childName;
            print('Cached: $deviceId -> $childName');
          }
        }
      }
    } catch (e) {
      print('Error preloading child names: $e');
    }
  }

  void _loadAlertsFromFirebase() {
    try {
      print('=== Starting Firebase Alert Load ===');
      // Try to load directly from /alerts path
      _alertsSubscription = _database
          .ref('alerts')
          .onValue
          .listen(
            (DatabaseEvent event) {
              print('=== Received Firebase Event ===');
              print('Event snapshot exists: ${event.snapshot.exists}');
              print(
                'Event snapshot value type: ${event.snapshot.value.runtimeType}',
              );

              if (!event.snapshot.exists) {
                print('No data at /alerts path');
                _processAlertsList([]);
                return;
              }

              final value = event.snapshot.value;
              print('Raw value: $value');

              final List<PanicAlert> list = [];

              if (value is Map) {
                print('Processing Map with ${value.length} entries');

                // Iterate through devices
                value.forEach((deviceKey, deviceData) {
                  print(
                    '  Device: $deviceKey, Data type: ${deviceData.runtimeType}',
                  );

                  if (deviceData is Map) {
                    print('    Device has ${deviceData.length} items');

                    // Each device can have multiple alerts (by timestamp key)
                    deviceData.forEach((timestampKey, alertData) {
                      print(
                        '      Key: $timestampKey, Data type: ${alertData.runtimeType}',
                      );

                      // Check if alertData is a Map (the actual alert object)
                      if (alertData is Map) {
                        // This is the alert object itself with lat, lng, status, timestamp
                        final alert = _parseAlert(
                          deviceKey.toString(),
                          alertData,
                        );
                        if (alert != null) {
                          list.add(alert);
                          print(
                            '        ✓ Parsed: Device=${alert.deviceId}, Status=${alert.status}, Timestamp=${alert.timestamp}, Lat=${alert.lat}, Lng=${alert.lng}',
                          );
                        } else {
                          print('        ✗ Failed to parse: $alertData');
                        }
                      } else {
                        print(
                          '        ! Alert data is not a Map, it is ${alertData.runtimeType}: $alertData',
                        );
                      }
                    });
                  } else {
                    print(
                      '    DeviceData is not a Map, it is ${deviceData.runtimeType}',
                    );
                  }
                });
              } else {
                print('ERROR: Value is not a Map, got ${value.runtimeType}');
              }

              print('=== Total alerts parsed: ${list.length} ===');
              _processAlertsList(list);
            },
            onError: (e) {
              print('=== RTDB alerts subscription ERROR ===');
              print('Error: $e');
              print('Error type: ${e.runtimeType}');
            },
          );
    } catch (e) {
      print('=== Exception in _loadAlertsFromFirebase ===');
      print('Error: $e');
      print('Stack: ${StackTrace.current}');
    }
  }

  void _processAlerts(dynamic value) {
    // This method is deprecated - use _processAlertsList instead
    final List<PanicAlert> list = [];
    if (value is Map) {
      value.forEach((deviceKey, deviceData) {
        if (deviceData is Map) {
          deviceData.forEach((timestampKey, alertData) {
            if (alertData is Map) {
              final alert = _parseAlert(deviceKey.toString(), alertData);
              if (alert != null) {
                list.add(alert);
              }
            }
          });
        }
      });
    }
    _processAlertsList(list);
  }

  void _processAlertsList(List<PanicAlert> list) {
    final Map<String, int> locationCount = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int todayCount = 0;

    print('Processing ${list.length} alerts');

    for (var alert in list) {
      // Count alerts by location
      locationCount[alert.deviceId] = (locationCount[alert.deviceId] ?? 0) + 1;

      // Count today's alerts (even if timestamp is 0, include them as "recent")
      if (alert.timestamp > 0) {
        final alertDate = DateTime.fromMillisecondsSinceEpoch(alert.timestamp);
        if (alertDate.isAfter(today)) {
          todayCount++;
        }
      } else {
        // Include alerts with no timestamp as "today"
        todayCount++;
      }
    }

    print('Location count: $locationCount');
    print('Today count: $todayCount');

    // Calculate weekly data (last 7 days)
    _calculateWeeklyData(list);

    if (mounted) {
      setState(() {
        _allAlerts = list.reversed.toList();
        _alertsByLocation = locationCount;
        _totalAlerts = list.length;
        _todayAlerts = todayCount;
      });
    }
  }

  PanicAlert? _parseAlert(String deviceId, Map<dynamic, dynamic> alertData) {
    try {
      print('      Parsing alert with data keys: ${alertData.keys.toList()}');

      final status = alertData['status']?.toString() ?? '';
      final lat = double.tryParse(alertData['lat']?.toString() ?? '0') ?? 0.0;
      final lng = double.tryParse(alertData['lng']?.toString() ?? '0') ?? 0.0;
      final tsRaw = alertData['timestamp'];
      int ts = 0;

      print(
        '      Raw values - status: "$status", lat: $lat, lng: $lng, tsRaw: $tsRaw (type: ${tsRaw.runtimeType})',
      );

      if (tsRaw is int) {
        ts = tsRaw;
      } else if (tsRaw is String) {
        ts = int.tryParse(tsRaw) ?? 0;
      } else if (tsRaw is double) {
        ts = tsRaw.toInt();
      }

      print('      Parsed timestamp: $ts');

      // Only accept PANIC and SOS alerts, filter out entry/exit geofence events
      final statusLower = status.toLowerCase();
      if (statusLower == 'panic' || statusLower == 'sos') {
        final alert = PanicAlert(
          deviceId: deviceId,
          lat: lat,
          lng: lng,
          timestamp: ts,
          status: status,
          childName: _deviceNameCache[deviceId], // NEW: Include child name
        );
        print('      ✓ Successfully created PanicAlert: $alert');
        return alert;
      }

      print('      ✗ Skipping non-panic alert for device $deviceId: "$status"');
      return null;
    } catch (e) {
      print('      ✗ Error parsing alert for device $deviceId: $e');
      print('      Stack trace: ${StackTrace.current}');
      return null;
    }
  }

  void _calculateWeeklyData(List<PanicAlert> alerts) {
    final weeklyData = List<double>.filled(7, 0);
    final now = DateTime.now();

    for (var alert in alerts) {
      if (alert.timestamp > 0) {
        try {
          final alertDate = DateTime.fromMillisecondsSinceEpoch(
            alert.timestamp,
          );
          final daysDiff = now.difference(alertDate).inDays;

          if (daysDiff >= 0 && daysDiff < 7) {
            weeklyData[6 - daysDiff]++;
          }
        } catch (e) {
          print('Error calculating date for timestamp ${alert.timestamp}: $e');
        }
      }
    }

    setState(() {
      _weeklyData = weeklyData;
    });
  }

  @override
  void dispose() {
    _alertsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use PopScope to handle the back button on Android.
    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) {
        if (didPop) {
          return;
        }
        Navigator.of(context).pushReplacementNamed('/splash');
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Smart Resilience',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Colors.black87,
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
        ),
        body: Column(
          children: [
            // Control buttons below header
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              child: Row(
                children: [
                  if (_showReports)
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: () {
                        setState(() {
                          _showReports = false;
                        });
                      },
                    ),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _showReports
                          ? _showExportOptions
                          : () {
                              setState(() {
                                _showReports = true;
                              });
                            },
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
                      child: Text(
                        _showReports ? 'Export Report' : 'View Reports',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _showFeedback = !_showFeedback;
                          if (_showFeedback) {
                            _showMap = false;
                            _showReports = false;
                          }
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _showFeedback
                            ? Colors.orange
                            : Colors.blue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.0),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        _showFeedback ? 'Back to Dashboard' : 'View Feedback',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Main content
            Expanded(
              child: _showMap
                  ? _buildMapView()
                  : _showReports
                  ? _buildReportsView()
                  : _showFeedback
                  ? _buildFeedbackView()
                  : _buildDashboardView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardView() {
    final avgAlerts = _weeklyData.isNotEmpty
        ? (_weeklyData.reduce((a, b) => a + b) / 7).toStringAsFixed(1)
        : '0';

    return SingleChildScrollView(
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
                value: _totalAlerts.toString(),
                subtitle: 'All time records',
                icon: Icons.error_outline,
                iconColor: Colors.red,
              ),
              // Today's Alerts Card
              DashboardCard(
                title: "Today's Alerts",
                value: _todayAlerts.toString(),
                subtitle: _todayAlerts > 0
                    ? 'Recent activity'
                    : 'No alerts today',
                icon: Icons.notifications_active,
                iconColor: Colors.orange,
              ),
              // Weekly Average Card with Graph
              DashboardCard(
                title: 'Weekly Average',
                value: avgAlerts,
                subtitle: 'Last 7 days',
                icon: Icons.bar_chart,
                iconColor: Colors.green,
                child: SizedBox(
                  height: 50,
                  width: 100,
                  child: CustomPaint(
                    painter: AlertGraphPainter(
                      data: _weeklyData,
                      graphColor: Colors.green,
                      backgroundColor: Colors.green,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Toggle Button for Map View
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
              TextButton(
                onPressed: () {
                  setState(() {
                    _showMap = true;
                  });
                },
                child: const Text('View Map'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // List of Top Alert Locations
          _buildLocationsList(),
          const SizedBox(height: 24),
          // All Alerts History Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                //margin: EdgeInsets.only(top: 10),
                padding: const EdgeInsets.only(top: 40.0),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'All Alert History',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Text(
                '${_allAlerts.length} total',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),

          const SizedBox(height: 16),
          _buildAllAlertsList(),
        ],
      ),
    );
  }

  Widget _buildLocationsList() {
    if (_alertsByLocation.isEmpty) {
      return Card(
        elevation: 2.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No alerts recorded yet',
            style: TextStyle(color: Colors.grey, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Sort locations by alert count
    final sortedLocations = _alertsByLocation.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: sortedLocations
          .take(5) // Show top 5
          .map((entry) {
            final deviceAlerts = _allAlerts
                .where((a) => a.deviceId == entry.key)
                .toList();
            final lastAlert = deviceAlerts.isNotEmpty
                ? DateTime.fromMillisecondsSinceEpoch(
                    deviceAlerts.first.timestamp,
                  )
                : DateTime.now();

            return LocationCard(
              deviceId: entry.key,
              alertCount: entry.value,
              lastAlert: lastAlert,
            );
          })
          .toList(),
    );
  }

  Widget _buildAllAlertsList() {
    if (_allAlerts.isEmpty) {
      return Card(
        elevation: 2.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No alerts recorded yet',
            style: TextStyle(color: Colors.grey, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: _allAlerts.map((alert) {
        final alertDateTime = DateTime.fromMillisecondsSinceEpoch(
          alert.timestamp,
        );
        final formattedTime = DateFormat(
          'MMM d, yyyy • hh:mm a',
        ).format(alertDateTime);

        return Card(
          elevation: 1.0,
          margin: const EdgeInsets.only(bottom: 8.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: InkWell(
              onTap: () {
                _showAlertDetails(alert);
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: _getAlertColor(alert.status),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _getAlertIcon(alert.status),
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Device: ${alert.childName ?? alert.deviceId}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _getAlertColor(
                                  alert.status,
                                ).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6.0),
                              ),
                              child: Text(
                                alert.status.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _getAlertColor(alert.status),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formattedTime,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Lat: ${alert.lat.toStringAsFixed(4)}, Lng: ${alert.lng.toStringAsFixed(4)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black45,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                _showAlertMapDetails(alert);
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 0,
                                ),
                                minimumSize: const Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'View Map',
                                style: TextStyle(fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMapView() {
    if (_allAlerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('No alerts to display on map'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _showMap = false;
                });
              },
              child: const Text('Back to List'),
            ),
          ],
        ),
      );
    }

    // Lock map to specified coordinates
    const double mapLat = 10.2970;
    const double mapLng = 123.8967;

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(mapLat, mapLng),
            initialZoom: 14.0,
            minZoom: 2.0,
            maxZoom: 18.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            ),
            MarkerLayer(
              markers: _allAlerts.map((alert) {
                return Marker(
                  point: LatLng(alert.lat, alert.lng),
                  width: 40,
                  height: 40,
                  child: GestureDetector(
                    onTap: () {
                      _showAlertDetails(alert);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: _getAlertColor(alert.status),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          _getAlertIcon(alert.status),
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        Positioned(
          top: 16,
          left: 16,
          child: FloatingActionButton.extended(
            onPressed: () {
              setState(() {
                _showMap = false;
              });
            },
            label: const Text('Back to List'),
            icon: const Icon(Icons.list),
            backgroundColor: Colors.blue,
          ),
        ),
      ],
    );
  }

  // NEW: Build feedback view
  Widget _buildFeedbackView() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('admin_feedback')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        print('=== Feedback StreamBuilder State ===');
        print('ConnectionState: ${snapshot.connectionState}');
        print('HasData: ${snapshot.hasData}');
        print('HasError: ${snapshot.hasError}');
        if (snapshot.hasError) {
          print('Error: ${snapshot.error}');
          print('StackTrace: ${snapshot.stackTrace}');
        }
        if (snapshot.hasData) {
          print('Documents count: ${snapshot.data!.docs.length}');
          for (var doc in snapshot.data!.docs) {
            print('Doc: ${doc.id}, Data: ${doc.data()}');
          }
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Error loading feedback: ${snapshot.error}',
                  style: const TextStyle(fontSize: 14, color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.feedback_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'No feedback received yet',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final feedbacks = snapshot.data!.docs
            .map((doc) => FeedbackItem.fromFirestore(doc))
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              const Text(
                'User Feedback',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '${feedbacks.length} feedback(s) received',
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 24),
              // Feedback Stats
              Wrap(
                spacing: 16.0,
                runSpacing: 16.0,
                children: [
                  _buildFeedbackStatCard(
                    'Total Feedback',
                    feedbacks.length.toString(),
                    Icons.message,
                    Colors.blue,
                  ),
                  _buildFeedbackStatCard(
                    'Unread',
                    feedbacks
                        .where((f) => f.status == 'unread')
                        .length
                        .toString(),
                    Icons.mail,
                    Colors.orange,
                  ),
                  _buildFeedbackStatCard(
                    'Bug Reports',
                    feedbacks
                        .where((f) => f.category == 'Bug Report')
                        .length
                        .toString(),
                    Icons.bug_report,
                    Colors.red,
                  ),
                  _buildFeedbackStatCard(
                    'Feature Requests',
                    feedbacks
                        .where((f) => f.category == 'Feature Request')
                        .length
                        .toString(),
                    Icons.lightbulb,
                    Colors.green,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Feedback List
              const Text(
                'All Feedback',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ...feedbacks
                  .map((feedback) => _buildFeedbackCard(feedback))
                  .toList(),
            ],
          ),
        );
      },
    );
  }

  // NEW: Build feedback stat card
  Widget _buildFeedbackStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  // NEW: Build feedback card
  Widget _buildFeedbackCard(FeedbackItem feedback) {
    final categoryColor = _getFeedbackCategoryColor(feedback.category);
    final formattedDate = DateFormat(
      'MMM d, yyyy • hh:mm a',
    ).format(feedback.timestamp);

    return GestureDetector(
      onTap: () => _showFeedbackDetailDialog(feedback),
      child: Card(
        elevation: 2.0,
        margin: const EdgeInsets.only(bottom: 12.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with user info and category
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          feedback.userName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          feedback.userPhone,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Chip(
                    label: Text(
                      feedback.category,
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: categoryColor.withOpacity(0.2),
                    labelStyle: TextStyle(color: categoryColor),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Feedback text preview
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Text(
                  feedback.feedbackText,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 12),
              // Footer with timestamp and status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formattedDate,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  Row(
                    children: [
                      if (feedback.status == 'unread')
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(4.0),
                          ),
                          child: Text(
                            'Unread',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.open_in_new,
                        size: 16,
                        color: Colors.blue,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // NEW: Show feedback detail dialog
  void _showFeedbackDetailDialog(FeedbackItem feedback) {
    final categoryColor = _getFeedbackCategoryColor(feedback.category);
    final formattedDate = DateFormat(
      'MMMM d, yyyy • hh:mm a',
    ).format(feedback.timestamp);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Feedback Details'),
            Chip(
              label: Text(
                feedback.category,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: categoryColor.withOpacity(0.2),
              labelStyle: TextStyle(color: categoryColor),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Info Section
            Card(
              color: Colors.grey[50],
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'From',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      feedback.userName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      feedback.userPhone,
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Feedback Text Section
            const Text(
              'Feedback',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Text(
                feedback.feedbackText,
                style: const TextStyle(fontSize: 15, height: 1.6),
              ),
            ),
            const SizedBox(height: 16),
            // Timestamp Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Received',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formattedDate,
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Status',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: feedback.status == 'unread'
                            ? Colors.orange.shade100
                            : Colors.green.shade100,
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: Text(
                        feedback.status == 'unread' ? 'Unread' : 'Read',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: feedback.status == 'unread'
                              ? Colors.orange.shade800
                              : Colors.green.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (feedback.status == 'unread')
            ElevatedButton.icon(
              onPressed: () async {
                try {
                  // Mark as read in admin_feedback collection
                  await FirebaseFirestore.instance
                      .collection('admin_feedback')
                      .doc(feedback.id)
                      .update({'status': 'read'});

                  // Also update in guardians subcollection if it exists
                  try {
                    final guardianDocs = await FirebaseFirestore.instance
                        .collection('guardians')
                        .get();

                    for (var guardianDoc in guardianDocs.docs) {
                      final feedbackRef = guardianDoc.reference
                          .collection('feedback')
                          .doc(feedback.id);

                      final docExists = await feedbackRef.get();
                      if (docExists.exists) {
                        await feedbackRef.update({'status': 'read'});
                        break;
                      }
                    }
                  } catch (e) {
                    print('Note: Could not update guardians subcollection: $e');
                  }

                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ Feedback marked as read'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                } catch (e) {
                  print('Error marking feedback as read: $e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('❌ Error marking as read: $e'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.check_circle),
              label: const Text('Mark as Read'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  // NEW: Get color for feedback category
  Color _getFeedbackCategoryColor(String category) {
    switch (category) {
      case 'Bug Report':
        return Colors.red;
      case 'Feature Request':
        return Colors.green;
      case 'General':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Color _getAlertColor(String status) {
    switch (status.toLowerCase()) {
      case 'panic':
      case 'sos':
        return Colors.red;
      case 'entry':
        return Colors.green;
      case 'exit':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  IconData _getAlertIcon(String status) {
    switch (status.toLowerCase()) {
      case 'panic':
      case 'sos':
        return Icons.warning;
      case 'entry':
        return Icons.login;
      case 'exit':
        return Icons.logout;
      default:
        return Icons.location_on;
    }
  }

  void _showExportOptions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Report'),
        content: const Text('Choose export format:'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _exportAsCSV();
            },
            child: const Text('CSV'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _exportAsPDF();
            },
            child: const Text('PDF'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportAsCSV() async {
    try {
      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd_HH-mm-ss').format(now);

      // Prepare CSV data
      List<List<dynamic>> csvData = [];

      // Header
      csvData.add(['Smart Resilience Analytics Report']);
      csvData.add([
        'Generated on ${DateFormat('MMM d, yyyy • hh:mm a').format(now)}',
      ]);
      csvData.add([]);

      // Summary statistics
      csvData.add(['SUMMARY STATISTICS']);
      csvData.add(['Total Panic Button Presses', _totalAlerts.toString()]);
      csvData.add(['Today\'s Alerts', _todayAlerts.toString()]);
      csvData.add([
        'Weekly Average',
        (_weeklyData.isNotEmpty
            ? (_weeklyData.reduce((a, b) => a + b) / 7).toStringAsFixed(1)
            : '0'),
      ]);
      csvData.add([]);

      // Weekly breakdown
      csvData.add(['WEEKLY BREAKDOWN (Last 7 Days)']);
      csvData.add(['Day', 'Alert Count']);
      final now2 = DateTime.now();
      for (int i = 0; i < 7; i++) {
        final date = now2.subtract(Duration(days: 6 - i));
        csvData.add([
          DateFormat('MMM d').format(date),
          _weeklyData[i].toInt().toString(),
        ]);
      }
      csvData.add([]);

      // Top alert locations
      csvData.add(['TOP ALERT LOCATIONS']);
      csvData.add(['Device ID', 'Alert Count', 'Last Alert']);
      final sortedLocations = _alertsByLocation.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (var entry in sortedLocations.take(10)) {
        final deviceAlerts = _allAlerts
            .where((a) => a.deviceId == entry.key)
            .toList();
        final lastAlert = deviceAlerts.isNotEmpty
            ? DateFormat('MMM d, hh:mm a').format(
                DateTime.fromMillisecondsSinceEpoch(
                  deviceAlerts.first.timestamp,
                ),
              )
            : 'N/A';
        csvData.add([entry.key, entry.value.toString(), lastAlert]);
      }
      csvData.add([]);

      // All alerts
      csvData.add(['ALL ALERTS']);
      csvData.add([
        'Device',
        'Child Name',
        'Status',
        'Timestamp',
        'Latitude',
        'Longitude',
      ]);
      for (var alert in _allAlerts) {
        final timestamp = alert.timestamp > 0
            ? DateFormat(
                'MMM d, yyyy hh:mm a',
              ).format(DateTime.fromMillisecondsSinceEpoch(alert.timestamp))
            : 'N/A';
        csvData.add([
          alert.deviceId,
          alert.childName ?? 'N/A',
          alert.status.toUpperCase(),
          timestamp,
          alert.lat.toStringAsFixed(6),
          alert.lng.toStringAsFixed(6),
        ]);
      }

      // Convert to CSV string
      String csv = const ListToCsvConverter().convert(csvData);

      // Create a data URI
      final bytes = utf8.encode(csv);
      final base64Csv = base64Encode(bytes);

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'CSV report generated: smart_resilience_report_$dateStr.csv',
            ),
            duration: const Duration(seconds: 3),
          ),
        );

        // In a real app, you would download the file using file_saver or similar
        // For now, we'll just show the success message
        print('CSV data generated: $dateStr');
      }
    } catch (e) {
      print('Error exporting CSV: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error exporting CSV: $e')));
      }
    }
  }

  Future<void> _exportAsPDF() async {
    try {
      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd_HH-mm-ss').format(now);

      final pdf = pw.Document();

      // Add content to PDF
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Text('Smart Resilience Analytics Report'),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Generated on ${DateFormat('MMM d, yyyy • hh:mm a').format(now)}',
            ),
            pw.SizedBox(height: 20),

            // Summary section
            pw.Header(level: 1, child: pw.Text('Summary Statistics')),
            pw.TableHelper.fromTextArray(
              headers: ['Metric', 'Value'],
              data: [
                ['Total Panic Button Presses', _totalAlerts.toString()],
                ['Today\'s Alerts', _todayAlerts.toString()],
                [
                  'Weekly Average',
                  (_weeklyData.isNotEmpty
                      ? (_weeklyData.reduce((a, b) => a + b) / 7)
                            .toStringAsFixed(1)
                      : '0'),
                ],
              ],
            ),
            pw.SizedBox(height: 20),

            // Weekly breakdown
            pw.Header(
              level: 1,
              child: pw.Text('Weekly Breakdown (Last 7 Days)'),
            ),
            pw.TableHelper.fromTextArray(
              headers: ['Day', 'Alert Count'],
              data: [
                for (int i = 0; i < 7; i++)
                  [
                    DateFormat(
                      'MMM d',
                    ).format(now.subtract(Duration(days: 6 - i))),
                    _weeklyData[i].toInt().toString(),
                  ],
              ],
            ),
            pw.SizedBox(height: 20),

            // Top locations
            pw.Header(level: 1, child: pw.Text('Top Alert Locations')),
            pw.TableHelper.fromTextArray(
              headers: ['Device ID', 'Alert Count', 'Last Alert'],
              data: [
                for (var entry
                    in (_alertsByLocation.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value)))
                        .take(10))
                  [
                    entry.key,
                    entry.value.toString(),
                    _allAlerts.where((a) => a.deviceId == entry.key).isNotEmpty
                        ? DateFormat('MMM d, hh:mm a').format(
                            DateTime.fromMillisecondsSinceEpoch(
                              _allAlerts
                                  .where((a) => a.deviceId == entry.key)
                                  .first
                                  .timestamp,
                            ),
                          )
                        : 'N/A',
                  ],
              ],
            ),
          ],
        ),
      );

      // Save or print the PDF
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'PDF report generated: smart_resilience_report_$dateStr.pdf',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('Error exporting PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error exporting PDF: $e')));
      }
    }
  }

  void _showAlertMapDetails(PanicAlert alert) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 4.0,
            title: const Text('Alert Location Map'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(alert.lat, alert.lng),
              initialZoom: 16.0,
              minZoom: 2.0,
              maxZoom: 18.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(alert.lat, alert.lng),
                    width: 50,
                    height: 50,
                    child: GestureDetector(
                      onTap: () {
                        _showAlertDetails(alert);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: _getAlertColor(alert.status),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            _getAlertIcon(alert.status),
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAlertDetails(PanicAlert alert) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alert Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device: ${alert.childName ?? alert.deviceId}'),
            Text('Status: ${alert.status}'),
            Text('Latitude: ${alert.lat.toStringAsFixed(6)}'),
            Text('Longitude: ${alert.lng.toStringAsFixed(6)}'),
            Text(
              'Time: ${DateFormat('MMM d, hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(alert.timestamp))}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // NEW: Get filtered alerts based on selected period and date
  List<PanicAlert> _getFilteredAlerts() {
    DateTime startDate;
    DateTime endDate;

    switch (_selectedPeriod) {
      case 'Week':
        // Start from selected date, go back 6 days (7 days total)
        startDate = _selectedReportDate.subtract(const Duration(days: 6));
        startDate = DateTime(startDate.year, startDate.month, startDate.day);
        // End date is the selected date (end of day)
        endDate = DateTime(
          _selectedReportDate.year,
          _selectedReportDate.month,
          _selectedReportDate.day,
          23,
          59,
          59,
        );
        break;
      case 'Month':
        // Start from first day of month
        startDate = DateTime(
          _selectedReportDate.year,
          _selectedReportDate.month,
          1,
        );
        // End date is the last day of the month
        final nextMonth = DateTime(
          _selectedReportDate.year,
          _selectedReportDate.month + 1,
          1,
        );
        endDate = nextMonth.subtract(const Duration(days: 1));
        endDate = DateTime(
          endDate.year,
          endDate.month,
          endDate.day,
          23,
          59,
          59,
        );
        break;
      case 'Year':
        // Start from first day of year
        startDate = DateTime(_selectedReportDate.year, 1, 1);
        // End date is the last day of the year (December 31)
        endDate = DateTime(_selectedReportDate.year, 12, 31, 23, 59, 59);
        break;
      default:
        startDate = _selectedReportDate.subtract(const Duration(days: 6));
        startDate = DateTime(startDate.year, startDate.month, startDate.day);
        endDate = DateTime(
          _selectedReportDate.year,
          _selectedReportDate.month,
          _selectedReportDate.day,
          23,
          59,
          59,
        );
    }

    final startTimestamp = startDate.millisecondsSinceEpoch;
    final endTimestamp = endDate.millisecondsSinceEpoch;

    print('Filter period: $_selectedPeriod');
    print('Selected date: $_selectedReportDate');
    print('Start: $startDate ($startTimestamp)');
    print('End: $endDate ($endTimestamp)');

    return _allAlerts.where((alert) {
      if (alert.timestamp == 0) return false;
      return alert.timestamp >= startTimestamp &&
          alert.timestamp <= endTimestamp;
    }).toList();
  }

  // NEW: Build reports view
  Widget _buildReportsView() {
    final filteredAlerts = _getFilteredAlerts();

    // Calculate date range based on selected period and date
    DateTime startDate;
    DateTime endDate;

    switch (_selectedPeriod) {
      case 'Week':
        startDate = _selectedReportDate.subtract(const Duration(days: 6));
        startDate = DateTime(startDate.year, startDate.month, startDate.day);
        endDate = DateTime(
          _selectedReportDate.year,
          _selectedReportDate.month,
          _selectedReportDate.day,
        );
        break;
      case 'Month':
        startDate = DateTime(
          _selectedReportDate.year,
          _selectedReportDate.month,
          1,
        );
        final nextMonth = DateTime(
          _selectedReportDate.year,
          _selectedReportDate.month + 1,
          1,
        );
        endDate = nextMonth.subtract(const Duration(days: 1));
        break;
      case 'Year':
        startDate = DateTime(_selectedReportDate.year, 1, 1);
        endDate = DateTime(_selectedReportDate.year, 12, 31);
        break;
      default:
        startDate = _selectedReportDate.subtract(const Duration(days: 6));
        startDate = DateTime(startDate.year, startDate.month, startDate.day);
        endDate = DateTime(
          _selectedReportDate.year,
          _selectedReportDate.month,
          _selectedReportDate.day,
        );
    }

    // Calculate statistics
    final alertsByDevice = <String, int>{};
    for (var alert in filteredAlerts) {
      alertsByDevice[alert.deviceId] =
          (alertsByDevice[alert.deviceId] ?? 0) + 1;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          const Text(
            'Panic Alerts Report',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${DateFormat('MMM d, yyyy').format(startDate)} - ${DateFormat('MMM d, yyyy').format(endDate)}',
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          // Date Picker Button
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate: _selectedReportDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (pickedDate != null) {
                    setState(() {
                      _selectedReportDate = pickedDate;
                    });
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_today,
                            color: Colors.green,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Report End Date',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat(
                                  'MMMM d, yyyy',
                                ).format(_selectedReportDate),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Icon(Icons.edit, color: Colors.grey, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Period Selector
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: ['Week', 'Month', 'Year'].map((period) {
                final isSelected = _selectedPeriod == period;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedPeriod = period;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.green.shade600
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          period,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),
          // Statistics Cards
          Wrap(
            spacing: 16.0,
            runSpacing: 16.0,
            children: [
              DashboardCard(
                title: 'Total Panic Alerts',
                value: filteredAlerts.length.toString(),
                subtitle: 'Selected period',
                icon: Icons.warning,
                iconColor: Colors.red,
              ),
              DashboardCard(
                title: 'Unique Devices',
                value: alertsByDevice.length.toString(),
                subtitle: 'With alerts',
                icon: Icons.devices,
                iconColor: Colors.blue,
              ),
              DashboardCard(
                title: 'Average per Device',
                value: alertsByDevice.isEmpty
                    ? '0'
                    : (filteredAlerts.length / alertsByDevice.length)
                          .toStringAsFixed(1),
                subtitle: 'Alerts per device',
                icon: Icons.bar_chart,
                iconColor: Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Top Devices Section
          const Text(
            'Top Devices by Alert Count',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          _buildTopDevicesList(alertsByDevice, filteredAlerts),
          const SizedBox(height: 24),
          // All Alerts in Period
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'All Panic Alerts',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Text(
                '${filteredAlerts.length} alerts',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildFilteredAlertsList(filteredAlerts),
        ],
      ),
    );
  }

  // NEW: Build top devices list
  Widget _buildTopDevicesList(
    Map<String, int> alertsByDevice,
    List<PanicAlert> filteredAlerts,
  ) {
    if (alertsByDevice.isEmpty) {
      return Card(
        elevation: 2.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No alerts in selected period',
            style: TextStyle(color: Colors.grey, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final sortedDevices = alertsByDevice.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: sortedDevices.take(5).map((entry) {
        final deviceAlerts = filteredAlerts
            .where((a) => a.deviceId == entry.key)
            .toList();
        final lastAlert = deviceAlerts.isNotEmpty
            ? DateTime.fromMillisecondsSinceEpoch(deviceAlerts.first.timestamp)
            : DateTime.now();

        return Card(
          elevation: 2.0,
          margin: const EdgeInsets.only(bottom: 12.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Text(
                    entry.value.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Device: ${_deviceNameCache[entry.key] ?? entry.key}',
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
                            '${entry.value} alerts',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.circle, size: 4, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            'Last: ${DateFormat('MMM d, hh:mm a').format(lastAlert)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // NEW: Build filtered alerts list
  Widget _buildFilteredAlertsList(List<PanicAlert> filteredAlerts) {
    if (filteredAlerts.isEmpty) {
      return Card(
        elevation: 2.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No panic alerts in selected period',
            style: TextStyle(color: Colors.grey, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: filteredAlerts.map((alert) {
        final alertDateTime = DateTime.fromMillisecondsSinceEpoch(
          alert.timestamp,
        );
        final formattedTime = DateFormat(
          'MMM d, yyyy • hh:mm a',
        ).format(alertDateTime);

        return Card(
          elevation: 1.0,
          margin: const EdgeInsets.only(bottom: 8.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: InkWell(
              onTap: () {
                _showAlertDetails(alert);
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Device: ${alert.childName ?? alert.deviceId}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6.0),
                              ),
                              child: Text(
                                alert.status.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formattedTime,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Lat: ${alert.lat.toStringAsFixed(4)}, Lng: ${alert.lng.toStringAsFixed(4)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black45,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                _showAlertMapDetails(alert);
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 0,
                                ),
                                minimumSize: const Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'View Map',
                                style: TextStyle(fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
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
  final String deviceId;
  final int alertCount;
  final DateTime lastAlert;

  const LocationCard({
    super.key,
    required this.deviceId,
    required this.alertCount,
    required this.lastAlert,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final diff = now.difference(lastAlert);
    String timeAgo;

    if (diff.inDays > 0) {
      timeAgo = '${diff.inDays} days ago';
    } else if (diff.inHours > 0) {
      timeAgo = '${diff.inHours} hours ago';
    } else if (diff.inMinutes > 0) {
      timeAgo = '${diff.inMinutes} minutes ago';
    } else {
      timeAgo = 'Just now';
    }

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
                color: Colors.red,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Text(
                alertCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Device: $deviceId',
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
                        '$alertCount alerts',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.circle, size: 4, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        'Last: $timeAgo',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Chip(
                    label: const Text('Panic Alert'),
                    backgroundColor: Colors.red.shade100,
                    labelStyle: TextStyle(
                      fontSize: 10,
                      color: Colors.red.shade800,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 0,
                    ),
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
                'High Risk',
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
