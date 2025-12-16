// lib/screens/location_history_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:smart_resilience_app/widgets/profile_avatar.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:async'; // Import for StreamSubscription

class LocationHistoryScreen extends StatefulWidget {
  const LocationHistoryScreen({super.key});

  @override
  State<LocationHistoryScreen> createState() => _LocationHistoryScreenState();
}

class _LocationHistoryScreenState extends State<LocationHistoryScreen> {
  User? _currentUser;
  String? _guardianDocId; // Store the actual guardian document ID
  String? _currentUserName; // To store the user's full name for the AppBar
  String? _currentUserPhotoUrl; // To store the user's profile photo URL
  String? _childName; // NEW: Store the child's name
  List<Map<String, dynamic>> _locationLogs = [];
  bool _isLoading = true;
  String? _deviceId; // Device ID (loaded from Firestore)

  // NEW: Route simulation variables
  bool _isSimulatingRoute = false;
  List<LatLng> _routePoints = [];
  LatLng? _currentSimulatedLocation;
  int _currentRouteIndex = 0;
  Timer? _simulationTimer;
  final MapController _routeMapController = MapController();

  // Date and time filter variables
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  TimeOfDay? _selectedStartTime;
  TimeOfDay? _selectedEndTime;

  // NEW: Collapsible date sections tracking
  Set<String> _expandedDateSections = {};

  StreamSubscription<User?>?
  _authStateSubscription; // Declare nullable subscription
  StreamSubscription<DocumentSnapshot>? _profileDocSubscription;

  @override
  void initState() {
    super.initState();
    _loadGuardianDocId();
    _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen((
      user,
    ) async {
      if (!mounted) return;
      setState(() {
        _currentUser = user;
        // Attempt to get display name from Firebase Auth, or set a default
        _currentUserName = user?.displayName ?? user?.phoneNumber ?? 'Guardian';
      });

      // Cancel any existing profile doc subscription
      await _profileDocSubscription?.cancel();

      if (user != null) {
        // Load guardian doc ID from local storage
        final prefs = await SharedPreferences.getInstance();
        final guardianDocId = prefs.getString('guardianDocId');

        if (guardianDocId != null && guardianDocId.isNotEmpty) {
          setState(() {
            _guardianDocId = guardianDocId;
          });
          print(
            '✅ LocationHistoryScreen: Loaded guardian doc ID: $guardianDocId',
          );

          // Listen to guardian document so profile changes propagate to all screens
          _profileDocSubscription = FirebaseFirestore.instance
              .collection('guardians')
              .doc(guardianDocId)
              .snapshots()
              .listen((snapshot) {
                if (!mounted) return;
                if (snapshot.exists && snapshot.data() != null) {
                  final data = snapshot.data() as Map<String, dynamic>;
                  setState(() {
                    _currentUserName =
                        data['fullName'] ?? user.phoneNumber ?? 'Guardian';
                    _currentUserPhotoUrl = data['photoUrl'] as String?;
                  });
                }
              });

          // NEW: Load paired device info (device ID and child name)
          await _loadPairedDevice(guardianDocId);
        }
      } else {
        // User logged out, clear data
        setState(() {
          _locationLogs = [];
          _currentUserName = null;
          _currentUserPhotoUrl = null;
          _guardianDocId = null;
          _isLoading = false;
        });
      }
    });
    // Gradient animation setup (copied from SettingsScreen)
    // No background animation: we'll use a static gradient (same as HomeScreen)
  }

  Future<void> _loadGuardianDocId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final docId = prefs.getString('guardianDocId');
      if (docId != null && docId.isNotEmpty) {
        setState(() {
          _guardianDocId = docId;
        });
        print('✅ LocationHistoryScreen: Loaded guardian doc ID: $docId');
      }
    } catch (e) {
      print('❌ LocationHistoryScreen: Error loading guardian doc ID: $e');
    }
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel(); // Cancel the subscription
    _profileDocSubscription?.cancel(); // Cancel profile doc listener
    _simulationTimer?.cancel(); // Cancel route simulation timer
    super.dispose();
  }

  // NEW: Load paired device info (device ID and child name)
  Future<void> _loadPairedDevice(String userId) async {
    try {
      final deviceDoc = await FirebaseFirestore.instance
          .collection('guardians')
          .doc(userId)
          .collection('paired_device')
          .doc('device_info')
          .get();

      if (deviceDoc.exists && deviceDoc.data() != null) {
        final data = deviceDoc.data() as Map<String, dynamic>;
        final deviceId = data['deviceId'] as String?;
        final childName = data['childName'] as String?;

        if (deviceId != null && deviceId.isNotEmpty) {
          setState(() {
            _deviceId = deviceId;
            _childName = childName;
          });
          _loadLocationLogs(); // Load logs after getting device ID
        }
      }
    } catch (e) {
      print("Error loading paired device: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Loads location logs from the tracking history
  Future<void> _loadLocationLogs() async {
    if (_currentUser == null || _deviceId == null) {
      setState(() {
        _isLoading = false;
        _locationLogs = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _locationLogs = []; // Clear previous logs
    });

    try {
      // Read from Realtime Database path: /trackingHistory/{deviceId}
      // This contains timestamped location records
      final db = FirebaseDatabase.instance;
      final ref = db.ref('trackingHistory/$_deviceId');
      final snapshot = await ref.get();

      List<Map<String, dynamic>> logs = [];

      print('📍 Fetching location history from trackingHistory/$_deviceId');

      if (snapshot.exists && snapshot.value != null) {
        final value = snapshot.value;
        print('📊 Raw data type: ${value.runtimeType}');

        if (value is Map) {
          // Iterate through all timestamped records
          value.forEach((timestamp, record) {
            try {
              if (record is Map) {
                final entry = Map<String, dynamic>.from(record);
                int ts = 0;

                // Try to parse timestamp key directly
                if (timestamp is String) {
                  ts = int.tryParse(timestamp) ?? 0;
                } else if (timestamp is int) {
                  ts = timestamp;
                }

                // Fallback to timestamp in data if key parsing fails
                if (ts == 0) {
                  final tsRaw = entry['timestamp'];
                  if (tsRaw is int) {
                    ts = tsRaw;
                  } else if (tsRaw is String) {
                    ts = int.tryParse(tsRaw) ?? 0;
                  }
                }

                // Convert seconds -> ms if necessary
                if (ts > 0 && ts < 10000000000) ts = ts * 1000;

                if (ts > 0) {
                  final dt = DateTime.fromMillisecondsSinceEpoch(ts);
                  final lat =
                      double.tryParse(entry['lat']?.toString() ?? '') ?? 0.0;
                  final lng =
                      double.tryParse(entry['lng']?.toString() ?? '') ?? 0.0;

                  if (lat != 0.0 || lng != 0.0) {
                    logs.add({
                      'id': 'tracking_${ts}',
                      'latitude': lat,
                      'longitude': lng,
                      'timestamp': dt,
                      'childName': _childName ?? _deviceId ?? 'Device',
                      'battery': entry['battery'] ?? 0,
                    });
                    print(
                      '  ✅ Location: $lat, $lng @ ${dt.toString()} (Battery: ${entry['battery']}%)',
                    );
                  }
                }
              }
            } catch (e) {
              print('  ⚠️ Error parsing record $timestamp: $e');
            }
          });
        }
      } else {
        print('⚠️ No data found at trackingHistory/$_deviceId');
        print('   Make sure location tracking is active to build history');
      }

      // Sort by timestamp (oldest first) so animation plays chronologically
      logs.sort(
        (a, b) =>
            (a['timestamp'] as DateTime).compareTo(b['timestamp'] as DateTime),
      );

      print('✅ Loaded ${logs.length} total location records');
      setState(() {
        _locationLogs = logs;
      });
    } catch (e) {
      print("❌ Error loading location logs from RTDB: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading location logs: $e")),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      initialDate: _selectedStartDate ?? DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedStartDate = picked;
        _selectedEndDate =
            picked; // Set end date to same day for single date selection
      });
    }
  }

  Future<void> _selectStartTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedStartTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedStartTime = picked;
      });
    }
  }

  Future<void> _selectEndTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedEndTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedEndTime = picked;
      });
    }
  }

  void _clearDateTimeFilters() {
    setState(() {
      _selectedStartDate = null;
      _selectedEndDate = null;
      _selectedStartTime = null;
      _selectedEndTime = null;
    });
  }

  bool _isLocationInDateTimeRange(Map<String, dynamic> log) {
    if (_selectedStartDate == null &&
        _selectedEndDate == null &&
        _selectedStartTime == null &&
        _selectedEndTime == null) {
      return true; // No filters applied
    }

    final logDateTime = log['timestamp'] as DateTime;

    // Check date range
    if (_selectedStartDate != null &&
        logDateTime.isBefore(_selectedStartDate!)) {
      return false;
    }
    if (_selectedEndDate != null) {
      final endOfDay = _selectedEndDate!.add(const Duration(days: 1));
      if (logDateTime.isAfter(endOfDay)) {
        return false;
      }
    }

    // Check time range
    if (_selectedStartTime != null || _selectedEndTime != null) {
      final logTime = TimeOfDay.fromDateTime(logDateTime);
      final logMinutes = logTime.hour * 60 + logTime.minute;

      if (_selectedStartTime != null) {
        final startMinutes =
            _selectedStartTime!.hour * 60 + _selectedStartTime!.minute;
        if (logMinutes < startMinutes) {
          return false;
        }
      }

      if (_selectedEndTime != null) {
        final endMinutes =
            _selectedEndTime!.hour * 60 + _selectedEndTime!.minute;
        if (logMinutes > endMinutes) {
          return false;
        }
      }
    }

    return true;
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // NEW: Start route simulation with selected date or all logs
  void _startRouteSimulation() {
    // Determine which logs to simulate
    late List<Map<String, dynamic>> logsToSimulate;

    if (_selectedStartDate != null) {
      // If a start date is selected, use only logs from that date
      final selectedDay = _selectedStartDate!;
      final dayStart = DateTime(
        selectedDay.year,
        selectedDay.month,
        selectedDay.day,
      );
      final dayEnd = DateTime(
        selectedDay.year,
        selectedDay.month,
        selectedDay.day,
        23,
        59,
        59,
      );

      logsToSimulate = _locationLogs.where((log) {
        final logTime = log['timestamp'] as DateTime;
        return logTime.isAfter(dayStart) && logTime.isBefore(dayEnd);
      }).toList();
    } else {
      // If no date is selected, use all logs
      logsToSimulate = _locationLogs;
    }

    if (logsToSimulate.isEmpty) {
      final dateStr = _selectedStartDate != null
          ? DateFormat('MMM d, yyyy').format(_selectedStartDate!)
          : 'today';
      _showSnackBar('No location data available for $dateStr');
      return;
    }

    // Extract route points from selected logs
    final routePoints = logsToSimulate
        .map((log) => LatLng(log['latitude'], log['longitude']))
        .toList();

    setState(() {
      _isSimulatingRoute = true;
      _routePoints = routePoints;
      _currentRouteIndex = 0;
      _currentSimulatedLocation = routePoints.isNotEmpty
          ? routePoints[0]
          : null;
    });

    // Start timer to animate through route
    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_currentRouteIndex < _routePoints.length - 1) {
          _currentRouteIndex++;
          _currentSimulatedLocation = _routePoints[_currentRouteIndex];

          // Move map to follow device
          try {
            _routeMapController.move(_currentSimulatedLocation!, 16.0);
          } catch (e) {
            // ignore map controller errors
          }
        } else {
          // Simulation finished
          timer.cancel();
          _showSnackBar('Route simulation completed');
        }
      });
    });
  }

  // NEW: Stop route simulation
  void _stopRouteSimulation() {
    _simulationTimer?.cancel();
    setState(() {
      _isSimulatingRoute = false;
      _routePoints = [];
      _currentRouteIndex = 0;
      _currentSimulatedLocation = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Determine the initial for the avatar, similar to HomeScreen
    String initial = 'G'; // Default if no user or name/email
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

    if (_currentUser == null || (_isLoading && _locationLogs.isEmpty)) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: _buildAppBar(initial), // Pass the initial for the avatar
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
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionHeader(
              title: "Location History Filter",
              description:
                  "Select a date and time to view your device's movement history.",
            ),
            const SizedBox(height: 16),
            _buildDateTimeFilterCard(), // Add date/time filter
            const SizedBox(height: 24),
            // NEW: Route Simulation Card
            if (_isSimulatingRoute) _buildRouteSimulationMap(),
            if (_isSimulatingRoute) const SizedBox(height: 24),
            _buildLocationHistorySection(), // This section already has its own cards
          ],
        ),
      ),
    );
  }

  // Reusable AppBar from SettingsScreen, now takes 'initial'
  AppBar _buildAppBar(String initial) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      automaticallyImplyLeading: true, // Allow back button
      title: Padding(
        padding: const EdgeInsets.only(
          left: 16.0,
        ), // Reduced left padding as per previous update
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
                Icons.location_on, // Changed icon to history
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
                  "Child Safety Monitor",
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        // User avatar, dynamically displaying initial
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

  // Reusable Section Header from SettingsScreen
  Widget _buildSectionHeader({
    required String title,
    required String description,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      ],
    );
  }

  // NEW: Route simulation map widget
  Widget _buildRouteSimulationMap() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: "Route Simulation",
          description:
              "Watch today's device route replay in real-time on the map below.",
        ),
        const SizedBox(height: 16),
        Container(
          height: 300,
          decoration: BoxDecoration(
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _currentSimulatedLocation != null
                ? FlutterMap(
                    mapController: _routeMapController,
                    options: MapOptions(
                      initialCenter: _currentSimulatedLocation!,
                      initialZoom: 16.0,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all,
                      ),
                      maxZoom: 18.0,
                      minZoom: 10.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName:
                            'com.example.smart_resilience_app',
                        maxZoom: 18,
                        tileDimension: 256,
                        retinaMode: false,
                      ),
                      // Draw full route path
                      if (_routePoints.isNotEmpty)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _routePoints,
                              color: Colors.lightBlue.withValues(alpha: 0.4),
                              strokeWidth: 2,
                            ),
                          ],
                        ),
                      // Draw traveled path (up to current location)
                      if (_currentRouteIndex > 0)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _routePoints.sublist(
                                0,
                                _currentRouteIndex + 1,
                              ),
                              color: Colors.blue.withValues(alpha: 0.8),
                              strokeWidth: 4,
                            ),
                          ],
                        ),
                      // Mark current simulated location
                      MarkerLayer(
                        markers: [
                          if (_currentSimulatedLocation != null)
                            Marker(
                              point: _currentSimulatedLocation!,
                              width: 40,
                              height: 40,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.blue.withValues(alpha: 0.8),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: const CircleAvatar(
                                  backgroundColor: Colors.blue,
                                  child: Icon(
                                    Icons.my_location,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
        ),
        const SizedBox(height: 16),
        // Simulation controls
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isSimulatingRoute
                    ? _stopRouteSimulation
                    : _startRouteSimulation,
                icon: Icon(_isSimulatingRoute ? Icons.stop : Icons.play_arrow),
                label: Text(_isSimulatingRoute ? 'Stop Simulation' : 'Start'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isSimulatingRoute
                      ? Colors.red
                      : Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _stopRouteSimulation,
                icon: const Icon(Icons.refresh),
                label: const Text('Reset'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Progress: ${_currentRouteIndex + 1}/${_routePoints.length} points',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  // New: Card-style Date/Time Filter
  Widget _buildDateTimeFilterCard() {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Date & Time Filter',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              if (_selectedStartDate != null ||
                  _selectedStartTime != null ||
                  _selectedEndTime != null)
                TextButton(
                  onPressed: _clearDateTimeFilters,
                  child: const Text(
                    'Clear All',
                    style: TextStyle(color: Colors.red, fontSize: 14),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Single Date Picker
          GestureDetector(
            onTap: _selectDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[50],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _selectedStartDate != null
                        ? DateFormat('MMM d, yyyy').format(_selectedStartDate!)
                        : 'Select a Date',
                    style: TextStyle(
                      fontSize: 14,
                      color: _selectedStartDate != null
                          ? Colors.black87
                          : Colors.grey,
                    ),
                  ),
                  Icon(
                    Icons.calendar_today,
                    size: 20,
                    color: _selectedStartDate != null
                        ? Colors.blue
                        : Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Time Range
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _selectStartTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey[50],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _selectedStartTime != null
                                ? _selectedStartTime!.format(context)
                                : 'Start Time',
                            style: TextStyle(
                              fontSize: 14,
                              color: _selectedStartTime != null
                                  ? Colors.black87
                                  : Colors.grey,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.access_time,
                          size: 20,
                          color: _selectedStartTime != null
                              ? Colors.blue
                              : Colors.grey,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: _selectEndTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey[50],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _selectedEndTime != null
                                ? _selectedEndTime!.format(context)
                                : 'End Time',
                            style: TextStyle(
                              fontSize: 14,
                              color: _selectedEndTime != null
                                  ? Colors.black87
                                  : Colors.grey,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.access_time,
                          size: 20,
                          color: _selectedEndTime != null
                              ? Colors.blue
                              : Colors.grey,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocationHistorySection() {
    // Apply date/time filtering to location logs
    final filteredLogs = _locationLogs
        .where((log) => _isLocationInDateTimeRange(log))
        .toList();

    // Group logs by date
    Map<String, List<Map<String, dynamic>>> logsByDate = {};
    for (var log in filteredLogs) {
      final dateKey = DateFormat('MMM d, yyyy').format(log['timestamp']);

      if (!logsByDate.containsKey(dateKey)) {
        logsByDate[dateKey] = [];
      }
      logsByDate[dateKey]!.add(log);
    }

    // Sort dates in descending order (newest first)
    final sortedDates = logsByDate.keys.toList()
      ..sort((a, b) {
        final dateA = DateFormat('MMM d, yyyy').parse(a);
        final dateB = DateFormat('MMM d, yyyy').parse(b);
        return dateB.compareTo(dateA);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: _buildSectionHeader(
                title: "Location Logs",
                description: "Recorded movements for your device.",
              ),
            ),
            ElevatedButton.icon(
              onPressed: _startRouteSimulation,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Simulate'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _locationLogs.isEmpty
            ? Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
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
                alignment: Alignment.center,
                child: const Text(
                  "No location logs found.",
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              )
            : filteredLogs.isEmpty
            ? Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
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
                alignment: Alignment.center,
                child: const Text(
                  "No location logs match the selected date and time filters.",
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              )
            : Column(
                children: sortedDates.map((dateKey) {
                  final isExpanded = _expandedDateSections.contains(dateKey);
                  final logsForDate = logsByDate[dateKey] ?? [];

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
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
                          // Date header (clickable)
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                if (_expandedDateSections.contains(dateKey)) {
                                  _expandedDateSections.remove(dateKey);
                                } else {
                                  _expandedDateSections.add(dateKey);
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: isExpanded
                                    ? const BorderRadius.only(
                                        topLeft: Radius.circular(12),
                                        topRight: Radius.circular(12),
                                      )
                                    : BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '$dateKey (${logsForDate.length} logs)',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.blue.shade800,
                                    ),
                                  ),
                                  Icon(
                                    isExpanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    color: Colors.blue.shade800,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Location logs for this date (shown when expanded)
                          if (isExpanded)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: Colors.grey.shade200,
                                    width: 1,
                                  ),
                                ),
                              ),
                              child: Column(
                                children: logsForDate
                                    .map(
                                      (log) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: _buildLocationLogCard(log),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
      ],
    );
  }

  Widget _buildLocationLogCard(Map<String, dynamic> log) {
    String time = DateFormat('hh:mm a').format(log['timestamp']);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.location_on, color: Colors.red, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${log['latitude'].toStringAsFixed(6)}, ${log['longitude'].toStringAsFixed(6)}",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        "$time ${log['childName']}",
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
