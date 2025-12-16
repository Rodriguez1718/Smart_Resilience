// lib/screens/reports_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_resilience_app/widgets/profile_avatar.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _selectedPeriod = 'Week'; // Week, Month, Year
  User? _currentUser;
  String? _currentUserName;
  String? _currentUserPhotoUrl;
  String? _guardianDocId;
  String? _pairedDeviceId;
  String? _childName;
  bool _isLoading = false;

  // Report data
  Map<String, dynamic> _reportData = {};

  @override
  void initState() {
    super.initState();
    _loadGuardianDocId();
    _listenToAuthChanges();
  }

  Future<void> _loadGuardianDocId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final docId = prefs.getString('guardianDocId');
      if (docId != null && docId.isNotEmpty) {
        setState(() {
          _guardianDocId = docId;
        });
      }
    } catch (e) {
      print('❌ Error loading guardian doc ID: $e');
    }
  }

  void _listenToAuthChanges() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) async {
      if (mounted) {
        setState(() {
          _currentUser = user;
          _currentUserName =
              user?.displayName ?? user?.phoneNumber ?? 'Guardian';
        });

        if (user != null) {
          // Load guardian profile
          if (_guardianDocId != null) {
            final doc = await FirebaseFirestore.instance
                .collection('guardians')
                .doc(_guardianDocId!)
                .get();
            if (doc.exists && doc.data() != null) {
              final data = doc.data() as Map<String, dynamic>;
              setState(() {
                _currentUserName =
                    data['fullName'] ?? user.phoneNumber ?? 'Guardian';
                _currentUserPhotoUrl = data['photoUrl'] as String?;
              });
            }

            // Load paired device
            await _loadPairedDevice();
            // Generate initial report
            await _generateReport();
          }
        }
      }
    });
  }

  Future<void> _loadPairedDevice() async {
    if (_guardianDocId == null) return;

    try {
      final deviceDoc = await FirebaseFirestore.instance
          .collection('guardians')
          .doc(_guardianDocId!)
          .collection('paired_device')
          .doc('device_info')
          .get();

      if (deviceDoc.exists && deviceDoc.data() != null) {
        final deviceId = deviceDoc.data()!['deviceId'] as String?;
        final childName = deviceDoc.data()!['childName'] as String?;
        if (deviceId != null && deviceId.isNotEmpty) {
          setState(() {
            _pairedDeviceId = deviceId;
            _childName = childName;
          });
        }
      }
    } catch (e) {
      print("Error loading paired device: $e");
    }
  }

  Future<void> _generateReport() async {
    if (_pairedDeviceId == null) {
      setState(() {
        _reportData = {};
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Calculate date range based on selected period
      final now = DateTime.now();
      DateTime startDate;
      DateTime endDate = now;

      switch (_selectedPeriod) {
        case 'Week':
          startDate = now.subtract(const Duration(days: 7));
          break;
        case 'Month':
          startDate = DateTime(now.year, now.month, 1);
          break;
        case 'Year':
          startDate = DateTime(now.year, 1, 1);
          break;
        default:
          startDate = now.subtract(const Duration(days: 7));
      }

      final startTimestamp = startDate.millisecondsSinceEpoch;
      final endTimestamp = endDate.millisecondsSinceEpoch;

      // Fetch location history
      final locationHistory = await _fetchLocationHistory(
        startTimestamp,
        endTimestamp,
      );

      // Fetch alerts
      final alerts = await _fetchAlerts(startTimestamp, endTimestamp);

      // Calculate statistics
      final stats = _calculateStatistics(locationHistory, alerts);

      setState(() {
        _reportData = {
          'period': _selectedPeriod,
          'startDate': startDate,
          'endDate': endDate,
          'locationHistory': locationHistory,
          'alerts': alerts,
          'stats': stats,
        };
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error generating report: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error generating report: $e')));
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchLocationHistory(
    int startTimestamp,
    int endTimestamp,
  ) async {
    if (_pairedDeviceId == null) return [];

    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('trackingHistory/$_pairedDeviceId')
          .get();

      if (!snapshot.exists) return [];

      final data = snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return [];

      final history = <Map<String, dynamic>>[];

      data.forEach((timestamp, locationData) {
        if (locationData is Map) {
          final ts = int.tryParse(timestamp.toString()) ?? 0;
          if (ts >= startTimestamp && ts <= endTimestamp) {
            final lat = locationData['lat'] as double? ?? 0.0;
            final lng = locationData['lng'] as double? ?? 0.0;
            final battery = locationData['battery'] as int? ?? 0;

            if (lat != 0.0 || lng != 0.0) {
              history.add({
                'timestamp': ts,
                'lat': lat,
                'lng': lng,
                'battery': battery,
              });
            }
          }
        }
      });

      // Sort by timestamp
      history.sort(
        (a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int),
      );

      return history;
    } catch (e) {
      print('Error fetching location history: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAlerts(
    int startTimestamp,
    int endTimestamp,
  ) async {
    if (_pairedDeviceId == null) return [];

    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('alerts/$_pairedDeviceId')
          .get();

      if (!snapshot.exists) return [];

      final data = snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return [];

      final alerts = <Map<String, dynamic>>[];

      data.forEach((timestamp, alertData) {
        if (alertData is Map) {
          final ts =
              alertData['timestamp'] as int? ??
              int.tryParse(timestamp.toString()) ??
              0;
          if (ts >= startTimestamp && ts <= endTimestamp) {
            final lat = alertData['lat'] as double? ?? 0.0;
            final lng = alertData['lng'] as double? ?? 0.0;
            final status = alertData['status']?.toString() ?? 'unknown';

            if (lat != 0.0 || lng != 0.0) {
              alerts.add({
                'timestamp': ts,
                'lat': lat,
                'lng': lng,
                'status': status,
              });
            }
          }
        }
      });

      // Sort by timestamp
      alerts.sort(
        (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int),
      );

      return alerts;
    } catch (e) {
      print('Error fetching alerts: $e');
      return [];
    }
  }

  Map<String, dynamic> _calculateStatistics(
    List<Map<String, dynamic>> locationHistory,
    List<Map<String, dynamic>> alerts,
  ) {
    if (locationHistory.isEmpty) {
      return {
        'totalLocations': 0,
        'totalDistance': 0.0,
        'avgBattery': 0,
        'panicAlerts': 0,
        'entryAlerts': 0,
        'exitAlerts': 0,
        'totalAlerts': 0,
      };
    }

    // Calculate total distance
    double totalDistance = 0.0;
    for (int i = 1; i < locationHistory.length; i++) {
      final prev = locationHistory[i - 1];
      final curr = locationHistory[i];
      totalDistance += _calculateDistance(
        prev['lat'] as double,
        prev['lng'] as double,
        curr['lat'] as double,
        curr['lng'] as double,
      );
    }

    // Calculate average battery
    int totalBattery = 0;
    int batteryCount = 0;
    for (var loc in locationHistory) {
      final battery = loc['battery'] as int? ?? 0;
      if (battery > 0) {
        totalBattery += battery;
        batteryCount++;
      }
    }
    final avgBattery = batteryCount > 0
        ? (totalBattery / batteryCount).round()
        : 0;

    // Count alerts by type
    int panicAlerts = 0;
    int entryAlerts = 0;
    int exitAlerts = 0;

    for (var alert in alerts) {
      final status = (alert['status'] as String).toLowerCase();
      if (status == 'panic' || status == 'sos') {
        panicAlerts++;
      } else if (status == 'entry') {
        entryAlerts++;
      } else if (status == 'exit') {
        exitAlerts++;
      }
    }

    return {
      'totalLocations': locationHistory.length,
      'totalDistance': totalDistance,
      'avgBattery': avgBattery,
      'panicAlerts': panicAlerts,
      'entryAlerts': entryAlerts,
      'exitAlerts': exitAlerts,
      'totalAlerts': alerts.length,
    };
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371000; // Earth radius in meters
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _toRad(double degree) {
    return degree * (math.pi / 180);
  }

  @override
  Widget build(BuildContext context) {
    String initial = 'G';
    if (_currentUserName != null && _currentUserName!.isNotEmpty) {
      initial = _currentUserName![0].toUpperCase();
    } else {
      final user = FirebaseAuth.instance.currentUser;
      if (user?.email?.isNotEmpty == true) {
        initial = user!.email![0].toUpperCase();
      } else if (user?.phoneNumber?.isNotEmpty == true) {
        initial = user!.phoneNumber![0].toUpperCase();
      }
    }

    if (_currentUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: _buildAppBar(initial),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.green.shade100,
              Colors.blue.shade100,
              Colors.green.shade50,
            ],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  _buildPeriodSelector(),
                  const SizedBox(height: 24),
                  if (_reportData.isNotEmpty) ..._buildReportContent(),
                  if (_reportData.isEmpty) _buildEmptyState(),
                ],
              ),
      ),
    );
  }

  AppBar _buildAppBar(String initial) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      automaticallyImplyLeading: true,
      title: Padding(
        padding: const EdgeInsets.only(left: 16.0),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.green.shade500,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.assessment,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Smart Resilience",
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "Reports & Analytics",
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: ProfileAvatar(
            photoPath: _currentUserPhotoUrl,
            displayName: _currentUserName,
            radius: 18,
            onProfileUpdated: (updated) async {
              if (updated == true) {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  final doc = await FirebaseFirestore.instance
                      .collection('guardians')
                      .doc(user.uid)
                      .get();
                  if (doc.exists && doc.data() != null) {
                    final data = doc.data() as Map<String, dynamic>;
                    setState(() {
                      _currentUserName =
                          data['fullName'] ?? user.phoneNumber ?? 'Guardian';
                      _currentUserPhotoUrl = data['photoUrl'] as String?;
                    });
                  }
                }
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Reports & Analytics",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          _childName != null
              ? "Activity report for $_childName"
              : "View activity statistics and insights",
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 3),
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
                _generateReport();
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
    );
  }

  List<Widget> _buildReportContent() {
    final stats = _reportData['stats'] as Map<String, dynamic>;
    final startDate = _reportData['startDate'] as DateTime;
    final endDate = _reportData['endDate'] as DateTime;
    final distanceKm = ((stats['totalDistance'] as double) / 1000)
        .toStringAsFixed(2);

    return [
      _buildDateRangeCard(startDate, endDate),
      const SizedBox(height: 16),
      _buildStatCard(
        title: "Location Points",
        value: "${stats['totalLocations']}",
        icon: Icons.location_on,
        color: Colors.blue,
      ),
      const SizedBox(height: 12),
      _buildStatCard(
        title: "Distance Traveled",
        value: "$distanceKm km",
        icon: Icons.straighten,
        color: Colors.green,
      ),
      const SizedBox(height: 12),
      _buildStatCard(
        title: "Average Battery",
        value: "${stats['avgBattery']}%",
        icon: Icons.battery_charging_full,
        color: Colors.orange,
      ),
      const SizedBox(height: 16),
      const Text(
        "Alerts Summary",
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      _buildStatCard(
        title: "Panic Alerts",
        value: "${stats['panicAlerts']}",
        icon: Icons.warning,
        color: Colors.red,
      ),
      const SizedBox(height: 12),
      _buildStatCard(
        title: "Geofence Entries",
        value: "${stats['entryAlerts']}",
        icon: Icons.login,
        color: Colors.green,
      ),
      const SizedBox(height: 12),
      _buildStatCard(
        title: "Geofence Exits",
        value: "${stats['exitAlerts']}",
        icon: Icons.logout,
        color: Colors.orange,
      ),
      const SizedBox(height: 12),
      _buildStatCard(
        title: "Total Alerts",
        value: "${stats['totalAlerts']}",
        icon: Icons.notifications,
        color: Colors.purple,
      ),
    ];
  }

  Widget _buildDateRangeCard(DateTime startDate, DateTime endDate) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today, color: Colors.green.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Report Period",
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  "${DateFormat('MMM d, yyyy').format(startDate)} - ${DateFormat('MMM d, yyyy').format(endDate)}",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.assessment_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _pairedDeviceId == null
                ? "No device paired yet"
                : "No data available for selected period",
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
