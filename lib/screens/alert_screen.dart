// lib/screens/alert_screen.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import Firebase Auth
import 'package:cloud_firestore/cloud_firestore.dart'; // Import Cloud Firestore
import 'package:smart_resilience_app/widgets/profile_avatar.dart';
import 'dart:async'; // Import for StreamSubscription

// import 'package:smart_resilience_app/screens/fullscreen_map.dart'; // Uncomment if using "View Map"
// import 'package:latlong2/latlong.dart'; // Uncomment if using "View Map"

class AlertScreen extends StatefulWidget {
  const AlertScreen({super.key});

  @override
  State<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends State<AlertScreen> {
  String _selectedFilter = 'Entry';

  User? _currentUser;
  String? _currentUserName; // To store the user's full name for the AppBar
  String? _currentUserPhotoUrl; // To store the user's profile photo URL
  StreamSubscription<User?>?
  _authStateSubscription; // Declare nullable subscription
  StreamSubscription<DocumentSnapshot>? _profileDocSubscription;

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
          // Listen to guardian document so profile changes propagate to this screen
          await _profileDocSubscription?.cancel();
          _profileDocSubscription = FirebaseFirestore.instance
              .collection('guardians')
              .doc(user.uid)
              .snapshots()
              .listen((snapshot) async {
                if (!mounted) return;
                if (snapshot.exists && snapshot.data() != null) {
                  final data = snapshot.data() as Map<String, dynamic>;
                  final newPhoto = data['photoUrl'] as String?;
                  // Evict file image cache for the new path to avoid stale images
                  try {
                    if (newPhoto != null && newPhoto.isNotEmpty) {
                      await FileImage(File(newPhoto)).evict();
                    }
                  } catch (e) {
                    // ignore eviction errors
                  }
                  if (!mounted) return;
                  setState(() {
                    _currentUserName =
                        data['fullName'] ?? user.phoneNumber ?? 'Guardian';
                    _currentUserPhotoUrl = newPhoto;
                  });
                }
              });
          // Potentially load alerts here if they depend on user ID
        } else {
          // User logged out, clear data
          setState(() {
            _currentUserName = null;
            _currentUserPhotoUrl = null;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel(); // Cancel the subscription
    _profileDocSubscription?.cancel();
    super.dispose();
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

    // Show a loading indicator until _currentUser is determined
    if (_currentUser == null && _currentUserName == null) {
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
            _buildAlertHistoryHeader(),
            const SizedBox(height: 16),
            _buildFilterButtons(),
            const SizedBox(height: 24),
            _buildRecentAlertsSection(),
            const SizedBox(height: 24),
            _buildAlertSettingsSection(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // AppBar now takes 'initial' as a parameter
  AppBar _buildAppBar(String initial) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      automaticallyImplyLeading:
          false, // Prevents back button on this tab screen
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
                Icons.location_on, // Changed icon to notifications
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
        // Use the shared ProfileAvatar widget so behaviour matches other screens
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
                    final newPhoto = data['photoUrl'] as String?;
                    try {
                      if (newPhoto != null && newPhoto.isNotEmpty) {
                        await FileImage(File(newPhoto)).evict();
                      }
                    } catch (e) {
                      // ignore
                    }
                    if (!mounted) return;
                    setState(() {
                      _currentUserName =
                          data['fullName'] ?? user.phoneNumber ?? 'Guardian';
                      _currentUserPhotoUrl = newPhoto;
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

  Widget _buildAlertHistoryHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Alert History",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          "Monitor geofence entry and exit events",
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildFilterButtons() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildFilterButton('Panic'),
          _buildFilterButton('Entry'),
          _buildFilterButton('Exit'),
        ],
      ),
    );
  }

  Widget _buildFilterButton(String title) {
    final bool isSelected = _selectedFilter == title;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedFilter = title;
          });
          print("Filter selected: $title");
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.shade700 : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentAlertsSection() {
    List<Map<String, dynamic>> alerts = [];
    if (_selectedFilter == 'Panic') {
      alerts = [
        {
          'type': 'Panic',
          'alertBy': 'Alex Mercer',
          'time': 'Today • 2:34 PM',
          'location': '10.312456, 123.901238',
          'priority': 'High Priority',
          'isEmergency': true,
        },
        {
          'type': 'Panic',
          'alertBy': 'Bea Mercer',
          'time': 'Yesterday • 10:00 AM',
          'location': '10.315000, 123.880000',
          'priority': 'High Priority',
          'isEmergency': true,
        },
      ];
    } else if (_selectedFilter == 'Entry') {
      alerts = [
        {
          'type': 'Entry',
          'alertBy': 'Bea Mercer',
          'time': 'Today • 1:12 PM',
          'location': '10.314600, 123.903900',
          'priority': 'Low Priority',
          'isEmergency': false,
        },
        {
          'type': 'Entry',
          'alertBy': 'Alex Mercer',
          'time': 'Yesterday • 3:00 PM',
          'location': '10.310000, 123.890000',
          'priority': 'Low Priority',
          'isEmergency': false,
        },
      ];
    } else if (_selectedFilter == 'Exit') {
      alerts = [
        {
          'type': 'Exit',
          'alertBy': 'Alex Mercer',
          'time': 'Today • 9:00 AM',
          'location': '10.311111, 123.888888',
          'priority': 'Medium Priority',
          'isEmergency': false,
        },
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Recent Alerts",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {
                print("View All Recent Alerts pressed!");
              },
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                alignment: Alignment.centerRight,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                "View All",
                style: TextStyle(color: Colors.blue, fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (alerts.isEmpty)
          _buildEmptyAlertsMessage()
        else
          Column(
            children: alerts.map((alert) => _buildAlertCard(alert)).toList(),
          ),
      ],
    );
  }

  Widget _buildEmptyAlertsMessage() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
        "No ${_selectedFilter.toLowerCase()} alerts found.",
        style: const TextStyle(color: Colors.grey, fontSize: 16),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    Color iconColor;
    IconData iconData;
    Color priorityColor;

    switch (alert['type']) {
      case 'Panic':
        iconColor = Colors.red;
        iconData = Icons.warning_rounded;
        break;
      case 'Entry':
        iconColor = Colors.green;
        iconData = Icons.login;
        break;
      case 'Exit':
        iconColor = Colors.orange;
        iconData = Icons.logout;
        break;
      default:
        iconColor = Colors.grey;
        iconData = Icons.info_outline;
    }

    switch (alert['priority']) {
      case 'High Priority':
        priorityColor = Colors.red;
        break;
      case 'Medium Priority':
        priorityColor = Colors.orange;
        break;
      case 'Low Priority':
        priorityColor = Colors.green;
        break;
      default:
        priorityColor = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Container(
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
                Row(
                  children: [
                    Icon(iconData, color: iconColor, size: 24),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alert['type'] == 'Panic'
                              ? "Panic Button"
                              : "Alert by: ${alert['alertBy']}",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          alert['time'],
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (alert['type'] == 'Panic')
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "Emergency",
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              alert['location'],
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      alert['priority'],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: priorityColor,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () {
                    print(
                      "View Map for alert: ${alert['type']} by ${alert['alertBy']}",
                    );
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerRight,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    "View Map",
                    style: TextStyle(color: Colors.blue, fontSize: 14),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Alert Settings",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _buildSettingCard(
          iconColor: Colors.red,
          iconData: Icons.warning_rounded,
          title: "High Priority",
          description:
              "Immediate notifications for exits during restricted hours",
        ),
        const SizedBox(height: 8),
        _buildSettingCard(
          iconColor: Colors.orange,
          iconData: Icons.notifications_active,
          title: "Medium Priority",
          description: "Standard notifications for unexpected zone changes",
        ),
        const SizedBox(height: 8),
        _buildSettingCard(
          iconColor: Colors.green,
          iconData: Icons.notifications_none,
          title: "Low Priority",
          description: "Routine notifications for expected movements",
        ),
      ],
    );
  }

  Widget _buildSettingCard({
    required Color iconColor,
    required IconData iconData,
    required String title,
    required String description,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconData, color: iconColor, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
