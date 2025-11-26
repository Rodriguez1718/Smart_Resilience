// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:smart_resilience_app/screens/fullscreen_map.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_resilience_app/widgets/profile_avatar.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  final Function(int)? onTabSelected;

  const HomeScreen({super.key, this.onTabSelected});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _safeZones = [];
  bool _isLoadingZones = false;
  bool _entryNotificationsEnabled = true;

  String? _currentUserId;
  String? _currentUserName; // NEW: To store the user's full name for the AppBar
  String? _currentUserPhotoUrl; // NEW: To store the user's profile photo URL
  StreamSubscription<DocumentSnapshot>? _profileDocSubscription;

  final List<Map<String, dynamic>> _childLocations = [
    {
      'name': 'Alex',
      'location': LatLng(10.6680, 122.9520),
      'battery': 98,
      'status': 'Safe',
      'color': Colors.red,
    },
    {
      'name': 'Bea',
      'location': LatLng(10.6650, 122.9480),
      'battery': 87,
      'status': 'Safe',
      'color': Colors.red,
    },
  ];

  // Using a StreamSubscription to explicitly manage the auth state listener
  late Stream<User?> _authStateChangesStream;
  StreamSubscription<User?>?
  _authStateSubscription; // Declare a nullable StreamSubscription

  @override
  void initState() {
    super.initState();
    _authStateChangesStream = FirebaseAuth.instance.authStateChanges();
    _listenToAuthChanges(); // Call a new method to listen to auth changes
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel(); // Cancel the subscription in dispose
    _profileDocSubscription?.cancel();
    super.dispose();
  }

  // METHOD TO LISTEN TO AUTH CHANGES
  void _listenToAuthChanges() {
    _authStateSubscription = _authStateChangesStream.listen((User? user) async {
      if (mounted) {
        setState(() {
          _currentUserId = user?.uid;
          // Attempt to get display name from Firebase Auth, or set a default
          _currentUserName =
              user?.displayName ?? user?.phoneNumber ?? 'Guardian';
        });

        if (user != null) {
          // Listen to guardian document for real-time updates to profile
          _profileDocSubscription?.cancel();
          _profileDocSubscription = FirebaseFirestore.instance
              .collection('guardians')
              .doc(user.uid)
              .snapshots()
              .listen((DocumentSnapshot doc) {
                if (!mounted) return;
                if (doc.exists && doc.data() != null) {
                  final data = doc.data() as Map<String, dynamic>;
                  setState(() {
                    _currentUserName =
                        data['fullName'] ?? user.phoneNumber ?? 'Guardian';
                    _currentUserPhotoUrl = data['photoUrl'] as String?;
                  });
                }
              });

          await _loadSafeZones();
          await _loadNotificationSettings();
        } else {
          // User logged out
          setState(() {
            _safeZones = [];
            _entryNotificationsEnabled = true;
            _currentUserName = null; // Clear user name on logout
          });
          // Only show snackbar if it's a genuine logout, not initial app load
          // This might be redundant if MainNavigation handles initial route based on auth state
          // ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No user logged in.")));
        }
      }
    });
  }

  Future<void> _loadSafeZones() async {
    if (_currentUserId == null) {
      print("Cannot load safe zones: User ID is null.");
      setState(() {
        _safeZones = []; // Clear previous zones if user logs out
      });
      return;
    }

    setState(() {
      _isLoadingZones = true;
    });
    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('guardians')
          .doc(_currentUserId!)
          .collection('geofences')
          .orderBy('createdAt', descending: false) // Keep orderBy for sorting
          .get();

      setState(() {
        _safeZones = snapshot.docs
            .map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              // Filter out placeholder documents
              if (data['isPlaceholder'] == true) {
                return null; // Skip this document
              }
              return {
                'id': doc.id,
                'name': data['name'] ?? 'Unnamed Zone',
                'location': LatLng(data['lat'], data['lng']),
                'radius': data['radius'],
              };
            })
            .whereType<Map<String, dynamic>>()
            .toList(); // Filter out nulls
      });
    } catch (e) {
      print("Error loading safe zones: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error loading safe zones: $e")));
    } finally {
      setState(() {
        _isLoadingZones = false;
      });
    }
  }

  Future<void> _loadNotificationSettings() async {
    if (_currentUserId == null) {
      print("Cannot load notification settings: User ID is null.");
      return;
    }

    try {
      DocumentSnapshot settingsDoc = await FirebaseFirestore.instance
          .collection('guardians')
          .doc(_currentUserId!)
          .collection('settings')
          .doc(
            'notifications',
          ) // Assuming 'notifications' is the specific doc for settings
          .get();

      if (settingsDoc.exists && settingsDoc.data() != null) {
        final data = settingsDoc.data() as Map<String, dynamic>;
        // Check for the placeholder and actual data
        if (data['isPlaceholder'] == true) {
          setState(() {
            _entryNotificationsEnabled =
                true; // Default to true if only placeholder exists
          });
          // Optionally, save the default setting to replace the placeholder
          await _saveNotificationSettings(true);
        } else {
          setState(() {
            _entryNotificationsEnabled = data['entryNotifications'] ?? true;
          });
        }
      } else {
        // If settings doc doesn't exist at all, assume default true and save it
        setState(() {
          _entryNotificationsEnabled = true;
        });
        await _saveNotificationSettings(true);
      }
    } catch (e) {
      print("Error loading notification settings: $e");
    }
  }

  Future<void> _saveNotificationSettings(bool value) async {
    if (_currentUserId == null) {
      print("Cannot save notification settings: User ID is null.");
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('guardians')
          .doc(_currentUserId!)
          .collection('settings')
          .doc('notifications')
          .set({
            'entryNotifications': value,
            'lastUpdated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Notifications ${value ? 'enabled' : 'disabled'}'),
        ),
      );
    } catch (e) {
      print("Error saving notification settings: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error saving notification settings: $e")),
      );
    }
  }

  void _openFullScreenMap({
    LatLng? location,
    double? radius,
    String? zoneName,
    String? safeZoneId,
    bool isForAddingOrEditing = false,
    List<Map<String, dynamic>>? allSafeZones,
    List<Map<String, dynamic>>? allChildLocations,
    double? initialRadius,
  }) async {
    if (_currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error: User not logged in.")),
      );
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullscreenMap(
          initialLocation: location ?? LatLng(10.6667, 122.95),
          initialRadius: initialRadius ?? 100,
          initialZoneName: zoneName ?? 'New Safe Zone',
          initialSafeZoneId: safeZoneId,
          isForAddingOrEditing: isForAddingOrEditing,
          allSafeZones: allSafeZones,
          allChildLocations: allChildLocations,
          userId: _currentUserId!,
        ),
      ),
    );

    if (result != null) {
      _loadSafeZones(); // Reload zones after map interaction
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Safe Zone updated!')));
    }
  }

  Widget _buildBodyContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildChildLocationSection(),
        const SizedBox(height: 16),
        _buildChildStatusCards(),
        const SizedBox(height: 16),
        _buildCurrentSafeZones(),
        const SizedBox(height: 16),
        _buildZoneSettings(),
        const SizedBox(height: 16),
        _buildAlertAndHistoryButtons(),
        const SizedBox(height: 16),
        _buildExportLogsButton(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show a loading indicator until _currentUserId is determined
    if (_currentUserId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Determine the initial for the avatar
    String initial = 'P'; // Default if no user or name/email
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
        child: _buildBodyContent(),
      ),
    );
  }

  // AppBar now takes 'initial' as a parameter
  AppBar _buildAppBar(String initial) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      automaticallyImplyLeading: false,
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
                Icons.location_on,
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

  Widget _buildChildLocationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Child Location",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          "Last updated 2 minutes ago",
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
        const SizedBox(height: 16),
        Container(
          height: 200,
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
            child: GestureDetector(
              onTap: () {
                _openFullScreenMap(
                  isForAddingOrEditing: false,
                  allSafeZones: _safeZones,
                  allChildLocations: _childLocations,
                );
              },
              child: Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: _safeZones.isNotEmpty
                          ? _safeZones.first['location']
                          : LatLng(10.6667, 122.95),
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
                        tileSize: 256,
                        retinaMode: false,
                      ),
                      CircleLayer(
                        circles: _safeZones.map((zone) {
                          return CircleMarker(
                            point: zone['location'],
                            radius: zone['radius'],
                            color: Colors.blue.withOpacity(0.1),
                            borderColor: Colors.blueAccent,
                            borderStrokeWidth: 2,
                            useRadiusInMeter: true,
                          );
                        }).toList(),
                      ),
                      MarkerLayer(
                        markers: _childLocations.map((child) {
                          return Marker(
                            point: child['location'],
                            width: 40,
                            height: 40,
                            child: Container(
                              decoration: BoxDecoration(
                                color: child['color'],
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  child['name'][0],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
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
                    bottom: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 5,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLegendItem(Colors.blueAccent, "Safe Zone(s)"),
                          _buildLegendItem(Colors.red, "Alex"),
                          _buildLegendItem(Colors.red, "Bea"),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: ElevatedButton(
                      onPressed: () =>
                          _openFullScreenMap(isForAddingOrEditing: true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.blue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        elevation: 3,
                      ),
                      child: const Text(
                        "Add Safe Zone",
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Icon(Icons.circle, color: color, size: 10),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildChildStatusCards() {
    return Column(
      children: _childLocations.map((child) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: _childStatusCard(
            name: child['name'],
            battery: child['battery'],
            status: child['status'],
            location: child['location'],
          ),
        );
      }).toList(),
    );
  }

  Widget _childStatusCard({
    required String name,
    required int battery,
    required String status,
    required LatLng location,
  }) {
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
              const Icon(Icons.circle, color: Colors.green, size: 12),
              const SizedBox(width: 8),
              Text(
                "$name - $status",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "$battery%",
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    "Battery",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              TextButton(
                onPressed: () {
                  _openFullScreenMap(
                    location: location,
                    initialRadius: 100,
                    zoneName: "${name}'s Location",
                    isForAddingOrEditing: false,
                    allSafeZones: _safeZones,
                    allChildLocations: _childLocations,
                  );
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerRight,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  "View Location",
                  style: TextStyle(color: Colors.blue, fontSize: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentSafeZones() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Current Safe Zones",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {
                print("View All Safe Zones pressed!");
                // You might navigate to a screen listing all geofences here
                // widget.onTabSelected?.call(index_for_geofences_screen);
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
        _isLoadingZones
            ? const Center(child: CircularProgressIndicator())
            : _safeZones.isEmpty
            ? Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
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
                  "No safe zones added yet. Add one above!",
                  style: TextStyle(color: Colors.grey),
                ),
              )
            : Column(
                children: _safeZones.map((zone) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: _buildSafeZoneCard(zone),
                  );
                }).toList(),
              ),
      ],
    );
  }

  Widget _buildSafeZoneCard(Map<String, dynamic> zone) {
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
                const Icon(Icons.circle, color: Colors.green, size: 12),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    zone['name'],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "Radius: ${zone['radius'].toInt()}m",
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(width: 4),
                const Text(
                  "• Active",
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              _openFullScreenMap(
                location: zone['location'],
                radius: zone['radius'],
                zoneName: zone['name'],
                safeZoneId: zone['id'],
                isForAddingOrEditing: true,
                initialRadius: zone['radius'],
              );
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              alignment: Alignment.centerRight,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              "Edit",
              style: TextStyle(color: Colors.blue, fontSize: 14),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
            onPressed: () => _confirmDeleteSafeZone(zone['id'], zone['name']),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Delete Safe Zone',
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteSafeZone(String zoneId, String zoneName) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Safe Zone?'),
          content: Text(
            'Are you sure you want to delete "$zoneName"? This action cannot be undone.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      _deleteSafeZone(zoneId);
    }
  }

  Future<void> _deleteSafeZone(String zoneId) async {
    if (_currentUserId == null) {
      print("Cannot delete safe zone: User ID is null.");
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('guardians')
          .doc(_currentUserId!)
          .collection('geofences')
          .doc(zoneId)
          .delete();
      _loadSafeZones();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Safe Zone deleted successfully!')),
      );
    } catch (e) {
      print("Error deleting safe zone: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error deleting safe zone: $e")));
    }
  }

  Widget _buildZoneSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Zone Settings",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Entry Notifications",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    "Get notified when Alex enters a safe zone",
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
              Switch(
                value: _entryNotificationsEnabled,
                onChanged: (bool value) {
                  setState(() {
                    _entryNotificationsEnabled = value;
                  });
                  _saveNotificationSettings(value);
                },
                activeColor: Colors.green,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAlertAndHistoryButtons() {
    return Row(
      children: [
        Expanded(
          child: _sectionCard(
            title: "Alert History",
            onViewAll: () {
              // Now call the callback if it exists
              widget.onTabSelected?.call(1); // Index 1 for Alerts
            },
            hasNotification: true,
            notificationCount: 1,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _sectionCard(
            title: "Location Logs",
            onViewAll: () {
              // Now call the callback if it exists
              widget.onTabSelected?.call(2); // Index 2 for History
            },
            hasNotification: false,
          ),
        ),
      ],
    );
  }

  Widget _buildExportLogsButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          print("Export Logs pressed!");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Exporting logs... (Functionality to be implemented)',
              ),
            ),
          );
        },
        icon: const Icon(Icons.download),
        label: const Text(
          "Export Logs",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 3,
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required VoidCallback onViewAll,
    bool hasNotification = false,
    int notificationCount = 0,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (hasNotification)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    notificationCount.toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              Expanded(
                child: Align(
                  alignment: hasNotification
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onViewAll,
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
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
