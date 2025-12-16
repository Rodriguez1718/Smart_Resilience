// lib/screens/location_history_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:smart_resilience_app/screens/route_map_screen.dart'; // Screen to display the route on a map
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async'; // Import for StreamSubscription

class LocationHistoryScreen extends StatefulWidget {
  const LocationHistoryScreen({super.key});

  @override
  State<LocationHistoryScreen> createState() => _LocationHistoryScreenState();
}

class _LocationHistoryScreenState extends State<LocationHistoryScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<AlignmentGeometry> _animation;
  User? _currentUser;
  String? _currentUserName; // NEW: To store the user's full name for the AppBar
  List<Map<String, dynamic>> _locationLogs = [];
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now(); // Default to today
  String? _selectedChildId; // To filter logs by child
  List<Map<String, dynamic>> _children =
      []; // List of children (fetched from Firestore or hardcoded)
  String? _guardianDocId; // Store guardian document ID
  String? _pairedDeviceId; // Store paired device ID
  String? _childName; // Store child name

  StreamSubscription<User?>?
  _authStateSubscription; // Declare nullable subscription
  StreamSubscription<DatabaseEvent>?
  _trackingHistorySubscription; // NEW: Real-time tracking history subscription

  @override
  void initState() {
    super.initState();
    _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen((
      user,
    ) async {
      if (mounted) {
        setState(() {
          _currentUser = user;
          // Attempt to get display name from Firebase Auth, or set a default
          _currentUserName =
              user?.displayName ?? user?.phoneNumber ?? 'Guardian';
        });

        if (user != null) {
          // Fetch user's full name from Firestore profile, similar to HomeScreen
          DocumentSnapshot guardianDoc = await FirebaseFirestore.instance
              .collection('guardians')
              .doc(user.uid)
              .get();
          if (guardianDoc.exists && guardianDoc.data() != null) {
            final data = guardianDoc.data() as Map<String, dynamic>;
            setState(() {
              _currentUserName =
                  data['fullName'] ?? user.phoneNumber ?? 'Guardian';
            });
          }
          _fetchChildren(); // Fetch children and then load logs
        } else {
          // User logged out, clear data
          setState(() {
            _locationLogs = [];
            _children = [];
            _selectedChildId = null;
            _currentUserName = null;
            _isLoading = false;
          });
        }
      }
    });
    // Gradient animation setup (copied from SettingsScreen)
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat(reverse: true);

    _animation =
        Tween<AlignmentGeometry>(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        );
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel(); // Cancel the subscription
    _trackingHistorySubscription
        ?.cancel(); // NEW: Cancel tracking history subscription
    _animationController.dispose(); // Dispose animation controller
    super.dispose();
  }

  // NEW: Load guardian document ID from local storage
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

  // Fetches children associated with the current guardian
  Future<void> _fetchChildren() async {
    if (_currentUser == null) {
      setState(() {
        _isLoading = false;
        _children = [];
      });
      return;
    }

    try {
      // Load guardian doc ID first
      await _loadGuardianDocId();

      if (_guardianDocId == null) {
        // Fallback: try using user.uid
        _guardianDocId = _currentUser!.uid;
      }

      // Load paired device from Firestore
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
            _children = [
              {'id': deviceId, 'name': childName ?? 'Child'},
            ];
            // Set the paired device as selected
            if (_selectedChildId == null) {
              _selectedChildId = deviceId;
            }
          });

          // Subscribe to real-time tracking history
          _subscribeToTrackingHistory(deviceId);
        } else {
          // No device paired
          setState(() {
            _children = [];
            _isLoading = false;
          });
        }
      } else {
        // No device paired
        setState(() {
          _children = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error fetching children: $e");
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error fetching children: $e")));
      }
    }
  }

  // NEW: Subscribe to real-time tracking history from Firebase Realtime Database
  void _subscribeToTrackingHistory(String deviceId) {
    _trackingHistorySubscription?.cancel();

    final db = FirebaseDatabase.instance;
    final trackingHistoryRef = db.ref('trackingHistory/$deviceId');

    _trackingHistorySubscription = trackingHistoryRef.onValue.listen(
      (DatabaseEvent event) {
        if (!mounted) return;

        print('📍 Real-time tracking history update received');

        if (!event.snapshot.exists) {
          setState(() {
            _locationLogs = [];
            _isLoading = false;
          });
          return;
        }

        final data = event.snapshot.value as Map<dynamic, dynamic>?;
        if (data == null) {
          setState(() {
            _locationLogs = [];
            _isLoading = false;
          });
          return;
        }

        // Process all location records
        final allLogs = <Map<String, dynamic>>[];

        data.forEach((timestamp, locationData) {
          if (locationData is Map) {
            final lat = locationData['lat'] as double? ?? 0.0;
            final lng = locationData['lng'] as double? ?? 0.0;
            final battery = locationData['battery'] as int? ?? 0;
            final ts = int.tryParse(timestamp.toString()) ?? 0;

            if (lat != 0.0 || lng != 0.0) {
              allLogs.add({
                'id': timestamp.toString(),
                'latitude': lat,
                'longitude': lng,
                'timestamp': DateTime.fromMillisecondsSinceEpoch(ts),
                'childName': _childName ?? 'Child',
                'battery': battery,
              });
            }
          }
        });

        // Filter by selected date
        _filterLogsByDate(allLogs);
      },
      onError: (error) {
        print("Error listening to tracking history: $error");
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      },
    );
  }

  // NEW: Filter logs by selected date
  void _filterLogsByDate(List<Map<String, dynamic>> allLogs) {
    final startOfDay = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final endOfDay = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      23,
      59,
      59,
    );

    final filteredLogs = allLogs.where((log) {
      final logDate = log['timestamp'] as DateTime;
      return logDate.isAfter(startOfDay.subtract(const Duration(seconds: 1))) &&
          logDate.isBefore(endOfDay.add(const Duration(seconds: 1)));
    }).toList();

    // Sort by timestamp (oldest first for route display)
    filteredLogs.sort(
      (a, b) =>
          (a['timestamp'] as DateTime).compareTo(b['timestamp'] as DateTime),
    );

    setState(() {
      _locationLogs = filteredLogs;
      _isLoading = false;
    });

    print(
      '✅ Filtered ${filteredLogs.length} logs for ${DateFormat('MMM d, yyyy').format(_selectedDate)}',
    );
  }

  // Loads location logs for the selected child and date
  // NOTE: This method is now mainly used to trigger a refresh when date/child changes
  // The actual data loading happens via real-time subscription in _subscribeToTrackingHistory
  Future<void> _loadLocationLogs() async {
    if (_currentUser == null ||
        _selectedChildId == null ||
        _pairedDeviceId == null) {
      setState(() {
        _isLoading = false;
        _locationLogs = [];
      });
      return;
    }

    // If we already have a subscription, it will automatically update
    // Just trigger a refresh by re-subscribing
    if (_pairedDeviceId != null) {
      _subscribeToTrackingHistory(_pairedDeviceId!);
    }
  }

  // Function to simulate adding a location log (for testing)
  Future<void> _addSimulatedLog() async {
    if (_currentUser == null || _selectedChildId == null) {
      _showSnackBar('Select a child first.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Simulate a random location around Bacolod City
      // LatLng(10.6667, 122.95)
      double baseLat = 10.6667;
      double baseLng = 122.95;
      double randomLatOffset =
          (DateTime.now().second % 100 - 50) / 10000.0; // Small random movement
      double randomLngOffset =
          (DateTime.now().minute % 100 - 50) / 10000.0; // Small random movement

      // This part is for actual Firestore data. For mock data, it won't be used.
      // If you switch back to real data, uncomment this:
      /*
      await FirebaseFirestore.instance
          .collection('guardians')
          .doc(_currentUser!.uid)
          .collection('children')
          .doc(_selectedChildId)
          .collection('location_logs')
          .add({
            'latitude': baseLat + randomLatOffset,
            'longitude': baseLng + randomLngOffset,
            'timestamp': FieldValue.serverTimestamp(),
            'childName': _children.firstWhere((c) => c['id'] == _selectedChildId)['name'],
          });
      */
      _showSnackBar('Simulated log added!');
      _loadLocationLogs(); // Reload logs after adding
    } catch (e) {
      print("Error adding simulated log: $e");
      _showSnackBar("Error adding simulated log: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Function to show date picker
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023, 1),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      // Re-filter existing logs for the new date
      // The subscription will continue to update in real-time
      if (_pairedDeviceId != null) {
        // Trigger a refresh by getting current data and filtering
        _refreshLocationLogs();
      }
    }
  }

  // NEW: Refresh location logs by fetching current data and filtering
  Future<void> _refreshLocationLogs() async {
    if (_pairedDeviceId == null) return;

    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('trackingHistory/$_pairedDeviceId')
          .get();

      if (!snapshot.exists) {
        setState(() {
          _locationLogs = [];
          _isLoading = false;
        });
        return;
      }

      final data = snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) {
        setState(() {
          _locationLogs = [];
          _isLoading = false;
        });
        return;
      }

      final allLogs = <Map<String, dynamic>>[];

      data.forEach((timestamp, locationData) {
        if (locationData is Map) {
          final lat = locationData['lat'] as double? ?? 0.0;
          final lng = locationData['lng'] as double? ?? 0.0;
          final battery = locationData['battery'] as int? ?? 0;
          final ts = int.tryParse(timestamp.toString()) ?? 0;

          if (lat != 0.0 || lng != 0.0) {
            allLogs.add({
              'id': timestamp.toString(),
              'latitude': lat,
              'longitude': lng,
              'timestamp': DateTime.fromMillisecondsSinceEpoch(ts),
              'childName': _childName ?? 'Child',
              'battery': battery,
            });
          }
        }
      });

      _filterLogsByDate(allLogs);
    } catch (e) {
      print("Error refreshing location logs: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
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

    if (_currentUser == null ||
        (_isLoading && _locationLogs.isEmpty && _children.isEmpty)) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: _buildAppBar(initial), // Pass the initial for the avatar
      body: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: _animation.value,
                end: _animation.value * -1,
                colors: [
                  Colors.green.shade100,
                  Colors.blue.shade100,
                  Colors.green.shade50,
                ],
              ),
            ),
            child: child,
          );
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionHeader(
              title: "Location History Filter",
              description:
                  "Select a child and date to view their movement history.",
            ),
            const SizedBox(height: 16),
            _buildDateFilterCard(), // Use the new card-style date filter
            const SizedBox(height: 8),
            _buildChildFilterCard(), // Use the new card-style child filter
            const SizedBox(height: 24),
            _buildLocationHistorySection(), // This section already has its own cards
            const SizedBox(height: 16),
            // Button to simulate adding a log (for testing)
            SizedBox(
              width: double.infinity, // Make it take full width
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _addSimulatedLog,
                icon: const Icon(Icons.add_location_alt),
                label: const Text(
                  "Simulate Add Location Log",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      Colors.green, // Matching the green from home_screen
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 3,
                ),
              ),
            ),
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
          child: CircleAvatar(
            backgroundColor: Colors.deepPurple[400],
            radius: 18,
            child: Text(
              initial, // Use the dynamically determined initial
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
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

  // New: Card-style Date Filter
  Widget _buildDateFilterCard() {
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
          const Text(
            "Date Filter",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          TextButton(
            onPressed: () => _selectDate(context),
            child: Row(
              children: [
                Text(
                  DateFormat('MMM d, yyyy').format(_selectedDate),
                  style: const TextStyle(fontSize: 16, color: Colors.blue),
                ),
                const Icon(Icons.arrow_drop_down, color: Colors.blue),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // New: Card-style Child Filter
  Widget _buildChildFilterCard() {
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
          const Text(
            "Select Child",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          DropdownButton<String>(
            value: _selectedChildId,
            onChanged: (String? newValue) {
              setState(() {
                _selectedChildId = newValue;
              });
              // Re-subscribe to tracking history for the new device
              if (newValue != null) {
                _subscribeToTrackingHistory(newValue);
              }
            },
            items: _children.map<DropdownMenuItem<String>>((
              Map<String, dynamic> child,
            ) {
              return DropdownMenuItem<String>(
                value: child['id'],
                child: Text(child['name']),
              );
            }).toList(),
            underline: Container(), // Remove default underline
            icon: const Icon(
              Icons.arrow_drop_down,
              color: Colors.blue,
            ), // Custom icon
            style: const TextStyle(
              fontSize: 16,
              color: Colors.blue,
            ), // Text style
          ),
        ],
      ),
    );
  }

  // _buildLocationHistorySection and _buildLocationLogCard remain largely the same,
  // as they already use a card-like structure, but I'll ensure the header matches.
  Widget _buildLocationHistorySection() {
    String formattedDate = DateFormat('MMMM d, yyyy').format(_selectedDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: "Location Logs for $formattedDate", // Updated title
          description:
              "Recorded movements for ${_children.firstWhere((c) => c['id'] == _selectedChildId, orElse: () => {'name': 'selected child'})['name']}.", // Dynamic description
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
                child: Text(
                  "No location logs found for ${DateFormat('MMM d').format(_selectedDate)} and selected child.",
                  style: const TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              )
            : Column(
                children: _locationLogs.map((log) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: _buildLocationLogCard(log),
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
          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.red, size: 24),
              const SizedBox(width: 12),
              Column(
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
            ],
          ),
          TextButton(
            onPressed: () {
              // Navigate to the RouteMapScreen to show the route for the selected day and child
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RouteMapScreen(
                    userId: _currentUser!.uid,
                    childId: _selectedChildId!,
                    childName: _children.firstWhere(
                      (c) => c['id'] == _selectedChildId,
                    )['name'],
                    selectedDate: _selectedDate,
                  ),
                ),
              );
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              alignment: Alignment.centerRight,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              "View Route",
              style: TextStyle(color: Colors.blue, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
