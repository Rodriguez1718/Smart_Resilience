// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:smart_resilience_app/screens/fullscreen_map.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_resilience_app/screens/guardian_login_page.dart';
import 'package:smart_resilience_app/widgets/profile_avatar.dart';
import 'package:smart_resilience_app/screens/reports_screen.dart';
import 'package:smart_resilience_app/services/iprogsms_service.dart'; // NEW: iProgsms SMS service
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:csv/csv.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

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
  String? _guardianDocId; // Store the actual guardian document ID
  String? _currentUserName;
  String? _currentUserPhotoUrl;
  String? _pairedDeviceId; // NEW: Store the paired device ID
  String? _childName; // NEW: Store the child's name
  StreamSubscription<DocumentSnapshot>? _profileDocSubscription;
  StreamSubscription<DatabaseEvent>?
  _trackingSubscription; // NEW: Subscribe to real-time tracking data

  // NEW: Track unviewed alerts
  int _unviewedAlertCount = 0;
  Set<String> _viewedAlertIds = {};
  int _lastPanicAlertTimestamp =
      0; // Track the timestamp of the last panic alert we sent SMS for
  Set<String> _processedPanicAlertIds =
      {}; // Track panic alerts that have been processed (SMS + notification sent)
  StreamSubscription<DatabaseEvent>? _alertsSubscription;
  Timer? _panicAlertDebounceTimer; // Prevent rapid re-processing of same alert

  // Map controller and zoom to keep the map centered on device
  final MapController _mapController = MapController();
  double _mapZoom = 16.0;

  // Real-time device data from Firebase
  Map<String, dynamic> _deviceData = {
    'name': 'Loading...',
    'location': LatLng(10.6667, 122.95),
    'battery': 0,
    'status': 'Offline',
    'color': Colors.grey,
    'timestamp': null,
  };

  bool _isLoadingDevice = true;

  List<Map<String, dynamic>> _trackingHistory =
      []; // Store all location history
  final List<Map<String, dynamic>> _childLocations =
      []; // Store child location data

  // Using a StreamSubscription to explicitly manage the auth state listener
  late Stream<User?> _authStateChangesStream;
  StreamSubscription<User?>?
  _authStateSubscription; // Declare a nullable StreamSubscription

  @override
  void initState() {
    super.initState();
    _loadGuardianDocId(); // Load guardian doc ID from local storage first
    _authStateChangesStream = FirebaseAuth.instance.authStateChanges();
    _listenToAuthChanges(); // Call a new method to listen to auth changes
    _loadTrackingHistory(); // Load location history on startup
  }

  Future<void> _loadGuardianDocId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final docId = prefs.getString('guardianDocId');
      if (docId != null && docId.isNotEmpty) {
        setState(() {
          _guardianDocId = docId;
        });
        print('✅ HomeScreen: Loaded guardian doc ID: $docId');
      }
    } catch (e) {
      print('❌ HomeScreen: Error loading guardian doc ID: $e');
    }
  }

  // NEW: Load all location history from Firebase
  Future<void> _loadTrackingHistory() async {
    if (_currentUserId == null || _pairedDeviceId == null) {
      return;
    }

    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('trackingHistory/$_pairedDeviceId')
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final history = <Map<String, dynamic>>[];

        data.forEach((timestamp, locationData) {
          if (locationData is Map) {
            final lat = locationData['lat'] as double? ?? 0.0;
            final lng = locationData['lng'] as double? ?? 0.0;
            final battery = locationData['battery'] as int? ?? 0;
            final ts = int.tryParse(timestamp.toString()) ?? 0;

            if (lat != 0.0 || lng != 0.0) {
              history.add({
                'timestamp': ts,
                'lat': lat,
                'lng': lng,
                'battery': battery,
              });
            }
          }
        });

        // Sort by timestamp descending (newest first)
        history.sort(
          (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int),
        );

        setState(() {
          _trackingHistory = history;
        });

        print('✅ Loaded ${history.length} location history records');
      }
    } catch (e) {
      print('⚠️ Error loading tracking history: $e');
    }
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel(); // Cancel the subscription in dispose
    _profileDocSubscription?.cancel();
    _trackingSubscription?.cancel(); // Cancel tracking subscription
    _alertsSubscription?.cancel(); // NEW: Cancel alerts subscription
    _panicAlertDebounceTimer?.cancel(); // Cancel debounce timer
    super.dispose();
  }

  // Intercept back button (Android) to confirm logout instead of exiting app
  Future<bool> _onWillPop() async {
    final bool? shouldLogout = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Logout?'),
          content: const Text(
            'Do you want to logout and return to the login screen?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Logout', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (e) {
        // ignore sign-out errors; still attempt navigation
      }
      if (!mounted) return false;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const GuardianLoginPage()),
        (route) => false,
      );
    }

    // Always prevent the default pop (exiting the app)
    return Future.value(false);
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
          // Load guardian doc ID from local storage
          final prefs = await SharedPreferences.getInstance();
          final guardianDocId = prefs.getString('guardianDocId');

          if (guardianDocId != null && guardianDocId.isNotEmpty) {
            setState(() {
              _guardianDocId = guardianDocId;
            });
            print('✅ HomeScreen auth: Using guardian doc ID: $guardianDocId');

            // Listen to guardian document for real-time updates to profile
            _profileDocSubscription?.cancel();
            _profileDocSubscription = FirebaseFirestore.instance
                .collection('guardians')
                .doc(guardianDocId)
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
            // Load paired device ID and listen to its tracking data
            await _loadPairedDeviceAndTracking(guardianDocId);
            await _loadSafeZones();
            await _loadNotificationSettings();
            // NEW: Load last panic alert timestamp to prevent resending on app restart
            await _loadLastPanicAlertTimestamp(guardianDocId);
            // NEW: Subscribe to alerts to track unviewed alerts
            _subscribeToAlerts(guardianDocId);
          }
        } else {
          // User logged out
          setState(() {
            _safeZones = [];
            _entryNotificationsEnabled = true;
            _currentUserName = null;
            _guardianDocId = null;
            _pairedDeviceId = null;
            _childName = null;
            _childLocations.clear();
            _unviewedAlertCount = 0;
            _viewedAlertIds.clear();
          });
          _trackingSubscription?.cancel();
          _alertsSubscription?.cancel();
        }
      }
    });
  }

  // NEW: Load paired device ID and subscribe to real-time tracking data
  Future<void> _loadPairedDeviceAndTracking(String userId) async {
    try {
      final deviceDoc = await FirebaseFirestore.instance
          .collection('guardians')
          .doc(userId)
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
            // Update device data with child name immediately
            _deviceData['name'] = childName ?? deviceId ?? 'Device';
          });
          _subscribeToDeviceTracking(deviceId);
          await _loadTrackingHistory(); // Load location history
        }
      }
    } catch (e) {
      print("Error loading paired device: $e");
    }
  }

  // NEW: Subscribe to real-time tracking data from Firebase Realtime DB
  void _subscribeToDeviceTracking(String deviceId) {
    _trackingSubscription?.cancel();

    final db = FirebaseDatabase.instance;
    final trackingRef = db.ref('tracking/$deviceId');

    _trackingSubscription = trackingRef.onValue.listen(
      (DatabaseEvent event) {
        if (!mounted) return;

        final data = event.snapshot.value as Map<dynamic, dynamic>?;
        if (data != null) {
          final lat = (data['lat'] ?? 0.0) as double;
          final lng = (data['lng'] ?? 0.0) as double;
          final battery = (data['battery'] ?? 0) as int;
          final timestamp = data['timestamp'];

          // NEW: Archive this location to tracking history with timestamp key
          // Skip archiving if coordinates are 0,0 (invalid/uninitialized GPS)
          if (lat != 0.0 || lng != 0.0) {
            final archiveTimestamp =
                timestamp as int? ?? DateTime.now().millisecondsSinceEpoch;
            final historyKey = 'trackingHistory/$deviceId/$archiveTimestamp';
            FirebaseDatabase.instance
                .ref(historyKey)
                .set({
                  'lat': lat,
                  'lng': lng,
                  'battery': battery,
                  'timestamp': archiveTimestamp,
                })
                .then((_) {
                  print(
                    '📌 Archived tracking to: trackingHistory/$deviceId/$archiveTimestamp',
                  );
                })
                .catchError((e) {
                  print('⚠️ Error archiving tracking: $e');
                });
          }

          setState(() {
            // Use the current _childName value (already loaded from Firestore)
            final displayName = _childName ?? _pairedDeviceId ?? 'Device';
            _deviceData = {
              'name': displayName,
              'location': LatLng(lat, lng),
              'battery': battery,
              'status': battery > 20 ? 'Online' : 'Low Battery',
              'color': battery > 20 ? Colors.green : Colors.orange,
              'timestamp': timestamp,
            };
            _isLoadingDevice = false;
            _childLocations.clear();
            _childLocations.add(_deviceData);

            print(
              'DEBUG: Child Name = $_childName, Display Name = $displayName',
            );
          });

          // Move map to device location when new coordinates arrive
          try {
            final loc = LatLng(lat, lng);
            // attempt immediate move; if controller isn't ready this may throw and we'll swallow
            _mapController.move(loc, _mapZoom);
          } catch (e) {
            // If move fails (controller not ready), schedule a retry shortly
            Future.delayed(const Duration(milliseconds: 250), () {
              if (!mounted) return;
              try {
                _mapController.move(LatLng(lat, lng), _mapZoom);
              } catch (_) {}
            });
          }
        }
      },
      onError: (error) {
        print("Error listening to tracking data: $error");
        if (mounted) {
          setState(() {
            _isLoadingDevice = false;
          });
        }
      },
    );
  }

  // NEW: Load last panic alert timestamp from Firestore to prevent resending on app restart
  Future<void> _loadLastPanicAlertTimestamp(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('guardians')
          .doc(userId)
          .collection('settings')
          .doc('sms_tracking')
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        final timestamp = data['lastPanicAlertSmsTimestamp'] as int? ?? 0;
        final processedAlerts = List<String>.from(
          data['processedPanicAlertIds'] as List? ?? [],
        );

        setState(() {
          _lastPanicAlertTimestamp = timestamp;
          _processedPanicAlertIds = processedAlerts.toSet();
        });
        print('✅ Loaded last panic alert timestamp: $_lastPanicAlertTimestamp');
        print(
          '✅ Loaded ${_processedPanicAlertIds.length} previously processed panic alerts',
        );
      } else {
        print('ℹ️ No previous panic alert SMS tracking found');
      }
    } catch (e) {
      print('⚠️ Error loading last panic alert timestamp: $e');
    }
  }

  // NEW: Save panic alert timestamp to Firestore (async with await)
  Future<void> _savePanicAlertTimestamp(String userId, int timestamp) async {
    try {
      await FirebaseFirestore.instance
          .collection('guardians')
          .doc(userId)
          .collection('settings')
          .doc('sms_tracking')
          .set({
            'lastPanicAlertSmsTimestamp': timestamp,
            'lastPanicAlertSmsSentAt': FieldValue.serverTimestamp(),
            'processedPanicAlertIds': _processedPanicAlertIds.toList(),
          }, SetOptions(merge: true));
      print('✅ Saved panic alert timestamp to Firestore: $timestamp');
      print(
        '✅ Saved ${_processedPanicAlertIds.length} processed panic alert IDs',
      );
    } catch (e) {
      print('⚠️ Error saving panic alert timestamp: $e');
    }
  }

  // NEW: Subscribe to alerts to track unviewed alerts
  void _subscribeToAlerts(String userId) {
    try {
      // CRITICAL: Cancel any existing subscription before creating a new one
      _alertsSubscription?.cancel();

      _alertsSubscription = FirebaseDatabase.instance
          .ref('alerts')
          .onValue
          .listen(
            (DatabaseEvent event) async {
              if (!mounted) return;

              int newUnviewedCount = 0;
              int latestPanicTimestamp = 0;
              String? latestPanicDeviceId;
              double latestPanicLat = 0;
              double latestPanicLng = 0;
              String? latestPanicAlertId; // Track the panic alert ID
              final value = event.snapshot.value;

              if (value is Map) {
                // First pass: find the LATEST panic alert by timestamp
                value.forEach((deviceKey, deviceData) {
                  if (deviceData is Map) {
                    deviceData.forEach((timestampKey, alertData) {
                      if (alertData is Map) {
                        final lat = (alertData['lat'] ?? 0.0) as double;
                        final lng = (alertData['lng'] ?? 0.0) as double;
                        if (lat == 0.0 && lng == 0.0) {
                          return;
                        }

                        final actualTimestamp =
                            alertData['timestamp'] as int? ?? 0;
                        final alertStatus =
                            alertData['status']?.toString().toLowerCase() ??
                            'unknown';

                        // Track the latest panic alert by timestamp
                        if ((alertStatus == 'panic' || alertStatus == 'sos') &&
                            actualTimestamp > latestPanicTimestamp) {
                          latestPanicTimestamp = actualTimestamp;
                          latestPanicDeviceId = deviceKey.toString();
                          latestPanicLat = lat;
                          latestPanicLng = lng;
                          // Use just the timestamp as alert ID (matches what's saved in Firestore)
                          latestPanicAlertId = actualTimestamp.toString();
                        }

                        // Count all unviewed alerts
                        final alertId = '$deviceKey-$actualTimestamp';
                        if (!_viewedAlertIds.contains(alertId)) {
                          newUnviewedCount++;
                        }
                      }
                    });
                  }
                });

                // Second pass: only send SMS for the LATEST panic alert if NOT already processed
                if (latestPanicTimestamp > 0 &&
                    latestPanicAlertId != null &&
                    !_processedPanicAlertIds.contains(latestPanicAlertId)) {
                  print(
                    '🚨 Found NEW panic alert: $latestPanicAlertId at $latestPanicTimestamp',
                  );
                  print(
                    '📊 Current processed alerts count: ${_processedPanicAlertIds.length}',
                  );

                  // Cancel any pending debounce timer
                  _panicAlertDebounceTimer?.cancel();

                  // Debounce: wait 1 second before processing to ensure no rapid duplicates
                  _panicAlertDebounceTimer = Timer(const Duration(seconds: 1), () async {
                    if (!mounted) return;

                    // Double-check that it's still not processed (in case another event fired)
                    if (_processedPanicAlertIds.contains(latestPanicAlertId)) {
                      print(
                        '✅ Alert $latestPanicAlertId already in memory, skipping',
                      );
                      return;
                    }

                    // Also check Firestore to be absolutely sure
                    try {
                      final doc = await FirebaseFirestore.instance
                          .collection('guardians')
                          .doc(userId)
                          .collection('settings')
                          .doc('sms_tracking')
                          .get();

                      if (doc.exists && doc.data() != null) {
                        final data = doc.data() as Map<String, dynamic>;
                        final savedAlerts = List<String>.from(
                          data['processedPanicAlertIds'] as List? ?? [],
                        );

                        if (savedAlerts.contains(latestPanicAlertId)) {
                          print(
                            '✅ Alert $latestPanicAlertId already in Firestore, skipping SMS',
                          );
                          // Update local set from Firestore
                          _processedPanicAlertIds = savedAlerts.toSet();
                          return;
                        }
                      }
                    } catch (e) {
                      print('⚠️ Error checking Firestore: $e');
                      // Continue anyway if check fails
                    }

                    // Mark this panic alert as processed BEFORE sending to prevent duplicates
                    _processedPanicAlertIds.add(latestPanicAlertId!);
                    _lastPanicAlertTimestamp = latestPanicTimestamp;

                    // Save to Firestore IMMEDIATELY and WAIT for it to complete
                    // This prevents duplicate SMS if app crashes or restarts
                    await _savePanicAlertTimestamp(
                      userId,
                      latestPanicTimestamp,
                    );

                    print(
                      '🔔 Sending SMS for new panic alert: $latestPanicAlertId',
                    );

                    // Only send SMS AFTER Firestore has saved
                    await _sendPanicAlertSms(
                      deviceId: latestPanicDeviceId!,
                      timestamp: latestPanicTimestamp,
                      latitude: latestPanicLat,
                      longitude: latestPanicLng,
                    );
                  });
                } else if (latestPanicAlertId != null &&
                    _processedPanicAlertIds.contains(latestPanicAlertId)) {
                  print(
                    '✅ Panic alert $latestPanicAlertId already processed, skipping SMS',
                  );
                }
              }

              if (mounted) {
                setState(() {
                  _unviewedAlertCount = newUnviewedCount;
                });
              }
            },
            onError: (error) {
              print('Error listening to alerts in home_screen: $error');
            },
          );
    } catch (e) {
      print('Failed to subscribe to alerts in home_screen: $e');
    }
  }

  // NEW: Send SMS for panic alerts only
  Future<void> _sendPanicAlertSms({
    required String deviceId,
    required int timestamp,
    required double latitude,
    required double longitude,
  }) async {
    try {
      print('📱 Processing SMS for PANIC alert...');

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('❌ No user logged in, skipping SMS');
        return;
      }

      // Get alert timestamp for message
      final alertDateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);

      // Use iProgsms service to send SMS
      // iProgsms API token from custom_otp_service.dart
      const String API_TOKEN = '79f0238238e0cdc03971d886d9485fb33332396d';
      const String SENDER_ID = 'SmartResilience';

      // Send SMS for this panic alert
      await IProgSmsService.sendAlertSms(
        apiKey: API_TOKEN,
        senderId: SENDER_ID,
        alertType: 'panic',
        latitude: latitude,
        longitude: longitude,
        alertTime: alertDateTime,
      );

      print(
        '✅ SMS sent for panic alert: $deviceId at ${alertDateTime.toString()}',
      );
    } catch (e) {
      print('❌ Error sending panic alert SMS: $e');
      // On error, reset the timestamp so we can retry if this alert comes again
      _lastPanicAlertTimestamp = 0;
    }
  }

  // NEW: Mark an alert as viewed
  void markAlertAsViewed(String deviceId, int timestamp) {
    final alertId = '$deviceId-$timestamp';
    if (!_viewedAlertIds.contains(alertId)) {
      setState(() {
        _viewedAlertIds.add(alertId);
        _unviewedAlertCount = (_unviewedAlertCount - 1)
            .clamp(0, double.infinity)
            .toInt();
      });
    }
  }

  Future<void> _loadSafeZones() async {
    if (_guardianDocId == null) {
      print("Cannot load safe zones: Guardian doc ID is null.");
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
          .doc(_guardianDocId!)
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
    if (_guardianDocId == null) {
      print("Cannot load notification settings: Guardian doc ID is null.");
      return;
    }

    try {
      DocumentSnapshot settingsDoc = await FirebaseFirestore.instance
          .collection('guardians')
          .doc(_guardianDocId!)
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
    if (_guardianDocId == null) {
      print("Cannot save notification settings: Guardian doc ID is null.");
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('guardians')
          .doc(_guardianDocId!)
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

  // CRITICAL: Load SMS tracking history from Firestore to prevent resending on app restart
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
    if (_guardianDocId == null) {
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
          userId: _guardianDocId!,
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
        const SizedBox(height: 16),
        _buildReportsButton(),
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

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
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
          _deviceData['timestamp'] != null
              ? "Last updated: ${DateFormat('MMM d, hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(_deviceData['timestamp'] as int))}"
              : "No location data",
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
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter:
                          _deviceData['location'] ?? LatLng(10.6667, 122.95),
                      initialZoom: _mapZoom,
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
                        markers: [
                          if (_deviceData['location'] != null)
                            Marker(
                              point: _deviceData['location'],
                              width: 40,
                              height: 40,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _deviceData['color'],
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    (_deviceData['name'] as String).isNotEmpty
                                        ? (_deviceData['name'] as String)[0]
                                        : 'D',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
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
                          _buildLegendItem(
                            _deviceData['color'],
                            _deviceData['name'],
                          ),
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
    if (_isLoadingDevice) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_childLocations.isEmpty) {
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
        alignment: Alignment.center,
        child: const Text(
          "No device paired yet.",
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

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
        const Text(
          "Current Safe Zones",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
    if (_guardianDocId == null) {
      print("Cannot delete safe zone: Guardian doc ID is null.");
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('guardians')
          .doc(_guardianDocId!)
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
            hasNotification: _unviewedAlertCount > 0,
            notificationCount: _unviewedAlertCount,
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
          _showExportOptions();
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

  Widget _buildReportsButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ReportsScreen()),
          );
        },
        icon: const Icon(Icons.assessment),
        label: const Text(
          "View Reports",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
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

  // NEW: Show export options dialog
  void _showExportOptions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Location Logs'),
        content: const Text('Choose export format:'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _exportLocationHistoryAsCSV();
            },
            child: const Text('CSV'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  // NEW: Export location history as CSV with file download
  Future<void> _exportLocationHistoryAsCSV() async {
    try {
      if (_trackingHistory.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No location history to export.')),
        );
        return;
      }

      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd_HH-mm-ss').format(now);
      final fileName = 'location_history_$dateStr.csv';

      // Prepare CSV data
      List<List<dynamic>> csvData = [];

      // Header
      csvData.add(['Smart Resilience - Location History Export']);
      csvData.add(['Child: ${_childName ?? _pairedDeviceId ?? "Unknown"}']);
      csvData.add([
        'Exported: ${DateFormat('MMM d, yyyy • hh:mm a').format(now)}',
      ]);
      csvData.add([]);

      // Summary
      csvData.add(['SUMMARY']);
      csvData.add(['Total Records', _trackingHistory.length.toString()]);
      if (_trackingHistory.isNotEmpty) {
        final oldestTime = DateTime.fromMillisecondsSinceEpoch(
          _trackingHistory.last['timestamp'] as int,
        );
        final newestTime = DateTime.fromMillisecondsSinceEpoch(
          _trackingHistory.first['timestamp'] as int,
        );
        csvData.add([
          'Date Range',
          '${DateFormat('MMM d, yyyy').format(oldestTime)} to ${DateFormat('MMM d, yyyy').format(newestTime)}',
        ]);
      }
      csvData.add([]);

      // Location history table
      csvData.add(['LOCATION HISTORY']);
      csvData.add([
        'Timestamp',
        'Date & Time',
        'Latitude',
        'Longitude',
        'Battery %',
      ]);

      for (var record in _trackingHistory) {
        final timestamp = record['timestamp'] as int;
        final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final formattedTime = DateFormat(
          'MMM d, yyyy hh:mm a',
        ).format(dateTime);
        final lat = (record['lat'] as double).toStringAsFixed(6);
        final lng = (record['lng'] as double).toStringAsFixed(6);
        final battery = (record['battery'] as int).toString();

        csvData.add([timestamp.toString(), formattedTime, lat, lng, battery]);
      }

      // Convert to CSV string
      String csv = const ListToCsvConverter().convert(csvData);

      // Get the external storage directory (device Downloads)
      // Using /storage/emulated/0/Download for Android to save to actual Downloads folder
      final String downloadsPath = '/storage/emulated/0/Download';
      final Directory downloadsDir = Directory(downloadsPath);

      // Try to create the directory if it doesn't exist
      if (!await downloadsDir.exists()) {
        try {
          await downloadsDir.create(recursive: true);
        } catch (e) {
          print('⚠️ Could not create Downloads directory: $e');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unable to access Downloads directory: $e')),
          );
          return;
        }
      }

      // Create the file path
      final String filePath = '${downloadsDir.path}/$fileName';
      final File file = File(filePath);

      // Write the CSV data to the file
      await file.writeAsString(csv);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Location history exported!\nFile: $fileName\nPath: ${downloadsDir.path}',
          ),
          duration: const Duration(seconds: 5),
        ),
      );

      print('✅ CSV saved to: $filePath');
      print('📊 Total records: ${_trackingHistory.length}');
    } catch (e) {
      print('❌ Error exporting location history: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error exporting logs: $e')));
    }
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
