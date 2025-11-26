// lib/screens/location_history_screen.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:smart_resilience_app/screens/profile_page.dart'; // Import ProfilePage
import 'package:smart_resilience_app/widgets/profile_avatar.dart';
import 'package:smart_resilience_app/screens/route_map_screen.dart'; // Screen to display the route on a map
import 'dart:async'; // Import for StreamSubscription

class LocationHistoryScreen extends StatefulWidget {
  const LocationHistoryScreen({super.key});

  @override
  State<LocationHistoryScreen> createState() => _LocationHistoryScreenState();
}

class _LocationHistoryScreenState extends State<LocationHistoryScreen> {
  User? _currentUser;
  String? _currentUserName; // To store the user's full name for the AppBar
  String? _currentUserPhotoUrl; // To store the user's profile photo URL
  List<Map<String, dynamic>> _locationLogs = [];
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now(); // Default to today
  String? _selectedChildId; // To filter logs by child
  List<Map<String, dynamic>> _children =
      []; // List of children (fetched from Firestore or hardcoded)

  StreamSubscription<User?>?
  _authStateSubscription; // Declare nullable subscription
  StreamSubscription<DocumentSnapshot>? _profileDocSubscription;

  @override
  void initState() {
    super.initState();
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
        // Listen to guardian document so profile changes propagate to all screens
        _profileDocSubscription = FirebaseFirestore.instance
            .collection('guardians')
            .doc(user.uid)
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

        _fetchChildren(); // Fetch children and then load logs
      } else {
        // User logged out, clear data
        setState(() {
          _locationLogs = [];
          _children = [];
          _selectedChildId = null;
          _currentUserName = null;
          _currentUserPhotoUrl = null;
          _isLoading = false;
        });
      }
    });
    // Gradient animation setup (copied from SettingsScreen)
    // No background animation: we'll use a static gradient (same as HomeScreen)
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel(); // Cancel the subscription
    _profileDocSubscription?.cancel(); // Cancel profile doc listener
    super.dispose();
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
      // For now, using hardcoded children. In a real app, you'd fetch this
      // from a 'children' subcollection under the guardian's document.
      // Example: guardians/{guardianId}/children/{childId}
      setState(() {
        _children = [
          {'id': 'alex_id', 'name': 'Alex'},
          {'id': 'bea_id', 'name': 'Bea'},
        ];
        // Set first child as selected by default, or handle no children case
        if (_children.isNotEmpty && _selectedChildId == null) {
          // Only set if not already selected
          _selectedChildId = _children.first['id'];
        }
      });
      _loadLocationLogs(); // Load logs after children are fetched
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

  // Loads location logs for the selected child and date
  Future<void> _loadLocationLogs() async {
    if (_currentUser == null || _selectedChildId == null) {
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
      // Define the start and end of the selected day
      DateTime startOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      DateTime endOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        23,
        59,
        59,
      );

      // This part is for actual Firestore data. For mock data, it won't be used.
      // If you switch back to real data, uncomment this:
      /*
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('guardians')
          .doc(_currentUser!.uid)
          .collection('children') // Assuming a 'children' collection
          .doc(_selectedChildId) // Specific child's document
          .collection('location_logs') // Subcollection for location logs
          .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
          .where('timestamp', isLessThanOrEqualTo: endOfDay)
          .orderBy('timestamp', descending: false) // Order by time for route drawing
          .get();

      setState(() {
        _locationLogs = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          Timestamp timestamp = data['timestamp'] as Timestamp;
          return {
            'id': doc.id,
            'latitude': data['latitude'],
            'longitude': data['longitude'],
            'timestamp': timestamp.toDate(), // Convert Firestore Timestamp to Dart DateTime
            'childName': data['childName'] ?? 'Unknown Child',
          };
        }).toList();
      });
      */

      // --- MOCK DATA FOR DEMONSTRATION (replace with Firestore fetch when ready) ---
      // This is the mock data that will be used for now.
      List<Map<String, dynamic>> mockLogs = [];
      if (_selectedChildId == 'alex_id') {
        mockLogs = [
          {
            'id': 'log1',
            'latitude': 10.6667,
            'longitude': 122.95,
            'timestamp': DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              8,
              0,
            ),
            'childName': 'Alex',
          },
          {
            'id': 'log2',
            'latitude': 10.6680,
            'longitude': 122.9510,
            'timestamp': DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              8,
              30,
            ),
            'childName': 'Alex',
          },
          {
            'id': 'log3',
            'latitude': 10.6695,
            'longitude': 122.9530,
            'timestamp': DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              9,
              0,
            ),
            'childName': 'Alex',
          },
          {
            'id': 'log4',
            'latitude': 10.6670,
            'longitude': 122.9550,
            'timestamp': DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              9,
              45,
            ),
            'childName': 'Alex',
          },
          {
            'id': 'log5',
            'latitude': 10.6650,
            'longitude': 122.9545,
            'timestamp': DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              10,
              15,
            ),
            'childName': 'Alex',
          },
        ];
      } else if (_selectedChildId == 'bea_id') {
        mockLogs = [
          {
            'id': 'log6',
            'latitude': 10.6650,
            'longitude': 122.9480,
            'timestamp': DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              11,
              0,
            ),
            'childName': 'Bea',
          },
          {
            'id': 'log7',
            'latitude': 10.6660,
            'longitude': 122.9490,
            'timestamp': DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              11,
              30,
            ),
            'childName': 'Bea',
          },
        ];
      }
      // Sort mock logs by timestamp to ensure correct route order
      mockLogs.sort(
        (a, b) =>
            (a['timestamp'] as DateTime).compareTo(b['timestamp'] as DateTime),
      );

      setState(() {
        _locationLogs = mockLogs;
      });
      // --- END MOCK DATA ---
    } catch (e) {
      print("Error loading location logs: $e");
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
      _loadLocationLogs(); // Reload logs for the new date
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
              _loadLocationLogs(); // Reload logs for the new child
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
