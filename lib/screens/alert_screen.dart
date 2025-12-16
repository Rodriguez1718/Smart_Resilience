// lib/screens/alert_screen.dart

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import Firebase Auth
import 'package:cloud_firestore/cloud_firestore.dart'; // Import Cloud Firestore
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import shared preferences
import 'package:smart_resilience_app/widgets/profile_avatar.dart';
import 'dart:async'; // Import for StreamSubscription
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart'; // For date/time formatting
import 'package:smart_resilience_app/screens/alert_map_screen.dart'; // Import alert map screen
import 'package:smart_resilience_app/services/notification_service.dart'; // Import NotificationService
import 'package:smart_resilience_app/services/messaging_service.dart'; // Import MessagingService for FCM

// Simple model for alerts read from RTDB
class AlertEntry {
  final String deviceId;
  final String status;
  final double lat;
  final double lng;
  final int timestamp;
  final String? childName; // NEW: Store child name

  AlertEntry({
    required this.deviceId,
    required this.status,
    required this.lat,
    required this.lng,
    required this.timestamp,
    this.childName,
  });
}

// import 'package:smart_resilience_app/screens/fullscreen_map.dart'; // Uncomment if using "View Map"
// import 'package:latlong2/latlong.dart'; // Uncomment if using "View Map"

class AlertScreen extends StatefulWidget {
  final Function(String deviceId, int timestamp)?
  onAlertViewed; // NEW: Callback when alert is viewed

  const AlertScreen({super.key, this.onAlertViewed});

  @override
  State<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends State<AlertScreen> {
  String _selectedFilter = 'Panic'; // Changed back to 'Panic' as default

  User? _currentUser;
  String? _currentUserName; // To store the user's full name for the AppBar
  String? _currentUserPhotoUrl; // To store the user's profile photo URL
  StreamSubscription<User?>?
  _authStateSubscription; // Declare nullable subscription
  StreamSubscription<DocumentSnapshot>? _profileDocSubscription;
  // Realtime Database alert subscription
  StreamSubscription<DatabaseEvent>? _alertsSub;
  DatabaseReference? _alertsRef;
  // Safezone and tracking subscriptions
  StreamSubscription<QuerySnapshot>? _safeZonesSub;
  StreamSubscription<DatabaseEvent>? _trackingSub;
  // NEW: Notification settings listener
  StreamSubscription<DocumentSnapshot>? _notificationSettingsSub;

  List<AlertEntry> _alerts = [];
  List<Map<String, dynamic>> _safeZones = [];
  Map<String, dynamic>? _currentDeviceLocation;
  Map<String, bool> _previousSafeZoneStatus =
      {}; // Track previous safezone status
  Map<String, String> _deviceNameCache = {}; // NEW: Cache for device names
  String?
  _guardianDocId; // Store the actual guardian document ID from Firestore

  // Notification settings
  bool _soundAlertEnabled = true;
  bool _vibrateOnlyEnabled = true;
  bool _bothSoundVibrationEnabled = true;

  Set<String> _shownAlertIds = {}; // Track shown alerts to avoid duplicates
  Set<String> _expandedDateSections =
      {}; // Track which date sections are expanded

  // Date and time filter variables
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  TimeOfDay? _selectedStartTime;
  TimeOfDay? _selectedEndTime;

  @override
  void initState() {
    super.initState();

    // Load guardian document ID from local storage
    _loadGuardianDocId();

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
          print('🔐 Auth User UID: ${user.uid}');
          print('🔐 Auth User Email: ${user.email}');
          print('🔐 Auth User Phone: ${user.phoneNumber}');

          // Get guardian document ID from local storage (it was saved during login/signup)
          final prefs = await SharedPreferences.getInstance();
          final storedGuardianId = prefs.getString('guardianDocId');
          if (storedGuardianId != null) {
            setState(() {
              _guardianDocId = storedGuardianId;
            });
            print('🔐 Using guardian doc ID: $storedGuardianId');
          }

          // Listen to guardian document so profile changes propagate to this screen
          if (_guardianDocId != null) {
            await _profileDocSubscription?.cancel();
            _profileDocSubscription = FirebaseFirestore.instance
                .collection('guardians')
                .doc(_guardianDocId!)
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
          }
          // Load safeZones FIRST, then subscribe to tracking
          // This ensures zones are loaded before location updates arrive
          _loadSafeZones();
          // Add a small delay to allow safe zones to load before tracking starts
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && _guardianDocId != null) {
              _subscribeToTracking(_guardianDocId!);
            }
          });
          // NEW: Preload child names
          _preloadChildNames();
          // NEW: Request FCM token and store in Firestore
          if (_guardianDocId != null) {
            _requestAndStoreFCMToken(_guardianDocId!);
          }
        } else {
          // User logged out, clear data
          setState(() {
            _currentUserName = null;
            _currentUserPhotoUrl = null;
            _guardianDocId = null;
          });
        }
      }
    });

    // Subscribe to realtime alerts globally (shows incoming panic/SOS alerts)
    _subscribeToAlerts();
    // NEW: Load notification settings on init
    _loadNotificationSettings();
    // NEW: Load shown alert IDs to prevent showing duplicate notifications on app restart
    if (_currentUser != null) {
      _loadShownAlertIds(_currentUser!.uid);
    }
  }

  // NEW: Load shown alert IDs from Firestore to prevent duplicate notifications
  Future<void> _loadShownAlertIds(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('guardians')
          .doc(userId)
          .collection('settings')
          .doc('sms_tracking')
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        final shownAlerts = List<String>.from(
          data['processedPanicAlertIds'] as List? ?? [],
        );

        setState(() {
          _shownAlertIds = shownAlerts.toSet();
        });
        print('✅ Loaded ${_shownAlertIds.length} previously shown alert IDs');
      }
    } catch (e) {
      print('⚠️ Error loading shown alert IDs: $e');
    }
  }

  // NEW: Save shown alert IDs to Firestore to prevent duplicate notifications on restart
  Future<void> _saveShownAlertIds(String userId) async {
    try {
      await FirebaseFirestore.instance
          .collection('guardians')
          .doc(userId)
          .collection('settings')
          .doc('sms_tracking')
          .set({
            'processedPanicAlertIds': _shownAlertIds.toList(),
          }, SetOptions(merge: true));
    } catch (e) {
      print('⚠️ Error saving shown alert IDs: $e');
    }
  }

  // NEW: Load notification settings from Firestore (listen in real-time)
  Future<void> _loadNotificationSettings() async {
    if (_currentUser == null) {
      return;
    }

    try {
      // Cancel existing subscription if any
      await _notificationSettingsSub?.cancel();

      // Listen to the notification settings document in real-time
      _notificationSettingsSub = FirebaseFirestore.instance
          .collection('guardians')
          .doc(_currentUser!.uid)
          .collection('settings')
          .doc('notifications')
          .snapshots()
          .listen(
            (settingsDoc) {
              if (!mounted) return;

              if (settingsDoc.exists && settingsDoc.data() != null) {
                final data = settingsDoc.data() as Map<String, dynamic>;
                if (data['isPlaceholder'] == true) {
                  setState(() {
                    _soundAlertEnabled = true;
                    _vibrateOnlyEnabled = true;
                    _bothSoundVibrationEnabled = true;
                  });
                } else {
                  setState(() {
                    _soundAlertEnabled = data['soundAlertEnabled'] ?? true;
                    _vibrateOnlyEnabled = data['vibrateOnlyEnabled'] ?? true;
                    _bothSoundVibrationEnabled =
                        data['bothSoundVibrationEnabled'] ?? true;
                  });
                }
              } else {
                // Default settings if none exist
                setState(() {
                  _soundAlertEnabled = true;
                  _vibrateOnlyEnabled = true;
                  _bothSoundVibrationEnabled = true;
                });
              }
            },
            onError: (e) {
              print("Error listening to notification settings: $e");
            },
          );
    } catch (e) {
      print("Error loading notification settings: $e");
    }
  }

  Future<void> _showNotification(String title, String body) async {
    // Use the NotificationService with user's preferred settings
    await NotificationService.showAlarmNotification(
      title: title,
      body: body,
      playSound: _soundAlertEnabled,
      vibrate: _vibrateOnlyEnabled,
      both: _bothSoundVibrationEnabled,
    );
  }

  // NEW: Request FCM token and store in Firestore
  Future<void> _requestAndStoreFCMToken(String userId) async {
    try {
      final token = await MessagingService.getToken();
      if (token != null) {
        // Store the FCM token in Firestore so Cloud Functions can send messages
        await FirebaseFirestore.instance
            .collection('guardians')
            .doc(userId)
            .update({
              'fcmToken': token,
              'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
            });
        print('FCM token stored: $token');

        // Also subscribe to user-specific topic
        await MessagingService.subscribeToTopic('user_$userId');
      }
    } catch (e) {
      print('Error requesting/storing FCM token: $e');
    }
  }

  Future<void> _loadGuardianDocId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final docId = prefs.getString('guardianDocId');
      if (docId != null && docId.isNotEmpty) {
        setState(() {
          _guardianDocId = docId;
        });
        print('✅ Loaded guardian document ID from local storage: $docId');
      }
    } catch (e) {
      print('❌ Error loading guardian doc ID: $e');
    }
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel(); // Cancel the subscription
    _profileDocSubscription?.cancel();
    _alertsSub?.cancel();
    _safeZonesSub?.cancel();
    _trackingSub?.cancel();
    _notificationSettingsSub
        ?.cancel(); // NEW: Cancel notification settings listener
    super.dispose();
  }

  Future<void> _loadSafeZones() async {
    if (_guardianDocId == null) return;

    print('🔄 Loading safe zones for guardian: $_guardianDocId');
    try {
      await _safeZonesSub?.cancel();
      _safeZonesSub = FirebaseFirestore.instance
          .collection('guardians')
          .doc(_guardianDocId!)
          .collection('geofences')
          .snapshots()
          .listen((snapshot) {
            if (!mounted) return;
            setState(() {
              _safeZones = snapshot.docs
                  .map((doc) {
                    final data = doc.data();
                    if (data['isPlaceholder'] == true) {
                      return null;
                    }
                    return {
                      'id': doc.id,
                      'name': data['name'] ?? 'Unnamed Zone',
                      'lat': data['lat'] as double,
                      'lng': data['lng'] as double,
                      'radius': data['radius'] as double,
                    };
                  })
                  .whereType<Map<String, dynamic>>()
                  .toList();
              print('✅ Loaded ${_safeZones.length} safe zones');
              for (var zone in _safeZones) {
                print(
                  '   - ${zone['name']}: (${zone['lat']}, ${zone['lng']}) Radius: ${zone['radius']}m',
                );
              }
            });
            // Check current location against safezones
            if (_currentDeviceLocation != null) {
              print('🔄 Current location available, checking zones');
              _checkSafeZoneStatus();
            } else {
              print('⚠️ No current location yet, waiting for tracking data');
            }
          });
    } catch (e) {
      print('❌ Error loading safeZones: $e');
    }
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
          }
        }
      }
    } catch (e) {
      print('Error preloading child names: $e');
    }
  }

  void _subscribeToTracking(String userId) {
    print('🔄 Subscribing to tracking for user: $userId');
    try {
      // Get the paired device ID from the paired_device subcollection
      FirebaseFirestore.instance
          .collection('guardians')
          .doc(userId)
          .collection('paired_device')
          .doc('device_info')
          .get()
          .then((doc) {
            if (doc.exists && doc.data() != null) {
              final pairedDeviceId =
                  (doc.data() as Map<String, dynamic>)['deviceId'] as String?;
              if (pairedDeviceId != null && pairedDeviceId.isNotEmpty) {
                print('✅ Found paired device: $pairedDeviceId');
                // Subscribe to this device's tracking data
                _trackingSub = FirebaseDatabase.instance
                    .ref('tracking/$pairedDeviceId')
                    .onValue
                    .listen((DatabaseEvent event) {
                      if (event.snapshot.exists) {
                        final value =
                            event.snapshot.value as Map<dynamic, dynamic>;
                        final lat =
                            double.tryParse(value['lat']?.toString() ?? '0') ??
                            0.0;
                        final lng =
                            double.tryParse(value['lng']?.toString() ?? '0') ??
                            0.0;

                        print('📍 Location update received: $lat, $lng');

                        // Skip if coordinates are 0,0 (invalid/uninitialized GPS)
                        if (lat == 0.0 && lng == 0.0) {
                          print('⚠️ Skipping invalid GPS coordinates (0,0)');
                          return;
                        }

                        // NEW: Archive this location to tracking history with timestamp key
                        final timestamp =
                            value['timestamp'] as int? ??
                            DateTime.now().millisecondsSinceEpoch;
                        final historyKey =
                            'trackingHistory/$pairedDeviceId/$timestamp';
                        FirebaseDatabase.instance
                            .ref(historyKey)
                            .set({
                              'lat': lat,
                              'lng': lng,
                              'battery': value['battery'] ?? 0,
                              'timestamp': timestamp,
                            })
                            .then((_) {
                              print('📌 Archived location to: $historyKey');
                            })
                            .catchError((e) {
                              print('⚠️ Error archiving location: $e');
                            });

                        setState(() {
                          _currentDeviceLocation = {
                            'lat': lat,
                            'lng': lng,
                            'timestamp': timestamp,
                          };
                        });
                        print('🔄 Checking safe zones with new location');
                        _checkSafeZoneStatus();
                      } else {
                        print('⚠️ No tracking data exists for $pairedDeviceId');
                      }
                    });
              } else {
                print('❌ No device ID found in paired_device collection');
              }
            } else {
              print('❌ paired_device/device_info document not found');
            }
          });
    } catch (e) {
      print('❌ Error subscribing to tracking: $e');
    }
  }

  void _checkSafeZoneStatus() {
    if (_currentDeviceLocation == null || _safeZones.isEmpty) {
      print(
        '⚠️ Cannot check safe zones: location=${_currentDeviceLocation != null}, zones=${_safeZones.length}',
      );
      return;
    }

    final deviceLat = _currentDeviceLocation!['lat'] as double;
    final deviceLng = _currentDeviceLocation!['lng'] as double;

    print(
      '📍 Checking ${_safeZones.length} zones against device location: $deviceLat, $deviceLng',
    );

    for (var zone in _safeZones) {
      final zoneLat = zone['lat'] as double;
      final zoneLng = zone['lng'] as double;
      final radius = zone['radius'] as double;
      final zoneId = zone['id'] as String;
      final zoneName = zone['name'] as String;

      // Calculate distance using Haversine formula
      final distance = _calculateDistance(
        deviceLat,
        deviceLng,
        zoneLat,
        zoneLng,
      );
      final isInside = distance <= radius;

      print('  📌 Zone: $zoneName (ID: $zoneId)');
      print('    Position: $zoneLat, $zoneLng');
      print(
        '    Distance: ${distance.toStringAsFixed(2)}m, Radius: ${radius.toStringAsFixed(2)}m',
      );
      print('    Status: ${isInside ? 'INSIDE ✓' : 'OUTSIDE ✗'}');

      // Check if this zone status is already tracked
      final hasTrackedStatus = _previousSafeZoneStatus.containsKey(zoneId);
      final previousStatus = _previousSafeZoneStatus[zoneId] ?? false;

      print(
        '    Previous status: ${hasTrackedStatus ? previousStatus : 'NOT TRACKED (first time)'}',
      );

      if (hasTrackedStatus && previousStatus != isInside) {
        // Status CHANGED - trigger entry/exit event
        _previousSafeZoneStatus[zoneId] = isInside;

        if (isInside) {
          print('    ✅ ENTRY DETECTED - Recording event');
          _recordSafeZoneEvent(zoneId, zoneName, 'entry', deviceLat, deviceLng);
        } else {
          print('    ⚠️ EXIT DETECTED - Recording event');
          _recordSafeZoneEvent(zoneId, zoneName, 'exit', deviceLat, deviceLng);
        }
      } else if (!hasTrackedStatus) {
        // First time tracking this zone
        _previousSafeZoneStatus[zoneId] = isInside;

        // If device is ALREADY INSIDE on first detection, trigger entry event
        if (isInside) {
          print('    ✅ INITIAL ENTRY DETECTED - Recording event');
          _recordSafeZoneEvent(zoneId, zoneName, 'entry', deviceLat, deviceLng);
        } else {
          // Device is outside on first detection - just initialize
          print(
            '    ℹ️ Device outside on first detection - initialized as outside',
          );
        }
      } else {
        print(
          '    ℹ️ Status unchanged (already ${isInside ? 'inside' : 'outside'})',
        );
      }
    }
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371000; // Radius of the earth in meters
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a =
        (sin(dLat / 2) * sin(dLat / 2)) +
        (cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRad(double degree) {
    return degree * (3.14159265359 / 180);
  }

  Future<void> _recordSafeZoneEvent(
    String zoneId,
    String zoneName,
    String eventType,
    double lat,
    double lng,
  ) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Get the paired device ID from the paired_device subcollection
      final pairedDeviceDoc = await FirebaseFirestore.instance
          .collection('guardians')
          .doc(_currentUser!.uid)
          .collection('paired_device')
          .doc('device_info')
          .get();

      if (!pairedDeviceDoc.exists) {
        print('❌ No paired device found');
        return;
      }

      final deviceId =
          (pairedDeviceDoc.data() as Map<String, dynamic>)['deviceId']
              as String?;

      if (deviceId == null) {
        print('❌ Device ID is null');
        return;
      }

      // Record to alerts like the SOS button
      await FirebaseDatabase.instance.ref('alerts/$deviceId/$timestamp').set({
        'status': eventType.toUpperCase() == 'ENTRY' ? 'entry' : 'exit',
        'lat': lat,
        'lng': lng,
        'timestamp': timestamp,
        'safeZoneId': zoneId,
        'safeZoneName': zoneName,
      });

      print('Recorded safezone $eventType for $zoneName');

      // NEW: Show notification for geofence entry/exit events
      if (eventType.toLowerCase() == 'entry') {
        await _showNotification(
          '📍 Geofence Entry',
          'Device entered $zoneName\nLocation: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
        );
      } else if (eventType.toLowerCase() == 'exit') {
        await _showNotification(
          '⚠️ Geofence Exit',
          'Device exited $zoneName\nLocation: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
        );
      }
    } catch (e) {
      print('Error recording safezone event: $e');
    }
  }

  void _subscribeToAlerts() {
    try {
      _alertsRef = FirebaseDatabase.instance.ref('alerts');
      _alertsSub = _alertsRef!.onValue.listen(
        (DatabaseEvent event) {
          final value = event.snapshot.value;
          final List<AlertEntry> list = [];

          if (value is Map) {
            // Iterate through devices
            value.forEach((deviceKey, deviceData) {
              if (deviceData is Map) {
                // Iterate through timestamps (alerts for each device)
                deviceData.forEach((timestampKey, alertData) {
                  if (alertData is Map) {
                    final status = alertData['status']?.toString() ?? '';
                    final lat =
                        double.tryParse(alertData['lat']?.toString() ?? '') ??
                        0.0;
                    final lng =
                        double.tryParse(alertData['lng']?.toString() ?? '') ??
                        0.0;

                    // Skip alerts with invalid GPS coordinates (0,0)
                    if (lat == 0.0 && lng == 0.0) {
                      print(
                        'Skipping alert with invalid GPS coordinates (0,0)',
                      );
                      return;
                    }

                    final tsRaw = alertData['timestamp'];
                    int ts = 0;
                    if (tsRaw is int)
                      ts = tsRaw;
                    else if (tsRaw is String)
                      ts = int.tryParse(tsRaw) ?? 0;

                    final alertId = '$deviceKey-$timestampKey-$ts';
                    final alert = AlertEntry(
                      deviceId: deviceKey.toString(),
                      status: status,
                      lat: lat,
                      lng: lng,
                      timestamp: ts,
                      childName:
                          _deviceNameCache[deviceKey
                              .toString()], // NEW: Include child name
                    );

                    list.add(alert);

                    // Show notification if this is a new alert
                    if (!_shownAlertIds.contains(alertId)) {
                      _shownAlertIds.add(alertId);
                      // Save shown alert IDs to Firestore to prevent duplicate notifications
                      if (_currentUser != null) {
                        _saveShownAlertIds(_currentUser!.uid);
                      }
                      _showAlertNotification(alert);
                    }
                  }
                });
              }
            });
          }

          if (mounted) {
            setState(() {
              // Sort by timestamp (newest first)
              list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
              _alerts = list;
            });
          }
        },
        onError: (e) {
          print('RTDB alerts subscription error: $e');
        },
      );
    } catch (e) {
      print('Failed to subscribe to RTDB alerts: $e');
    }
  }

  void _showAlertNotification(AlertEntry alert) {
    final bool isEmergency =
        alert.status.toLowerCase() == 'sos' ||
        alert.status.toLowerCase() == 'panic';

    String title;
    String body;

    if (isEmergency) {
      title = '🚨 PANIC ALERT!';
      body =
          'Device ${alert.childName ?? alert.deviceId} triggered panic button!\nLocation: ${alert.lat.toStringAsFixed(4)}, ${alert.lng.toStringAsFixed(4)}';
      // SMS is handled by home_screen.dart - no SMS call here to avoid duplicates
    } else if (alert.status.toLowerCase() == 'entry') {
      title = '📍 Geofence Entry';
      body =
          'Device ${alert.childName ?? alert.deviceId} entered a geofence.\nLocation: ${alert.lat.toStringAsFixed(4)}, ${alert.lng.toStringAsFixed(4)}';
    } else if (alert.status.toLowerCase() == 'exit') {
      title = '⚠️ Geofence Exit';
      body =
          'Device ${alert.childName ?? alert.deviceId} exited a geofence.\nLocation: ${alert.lat.toStringAsFixed(4)}, ${alert.lng.toStringAsFixed(4)}';
    } else {
      title = '🔔 Alert';
      body =
          'Alert from device ${alert.childName ?? alert.deviceId}.\nLocation: ${alert.lat.toStringAsFixed(4)}, ${alert.lng.toStringAsFixed(4)}';
    }

    _showNotification(title, body);
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      initialDateRange: _selectedStartDate != null && _selectedEndDate != null
          ? DateTimeRange(start: _selectedStartDate!, end: _selectedEndDate!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _selectedStartDate = picked.start;
        _selectedEndDate = picked.end;
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

  bool _isAlertInDateTimeRange(AlertEntry alert) {
    if (_selectedStartDate == null &&
        _selectedEndDate == null &&
        _selectedStartTime == null &&
        _selectedEndTime == null) {
      return true; // No filters applied
    }

    final alertDateTime = DateTime.fromMillisecondsSinceEpoch(alert.timestamp);

    // Check date range
    if (_selectedStartDate != null &&
        alertDateTime.isBefore(_selectedStartDate!)) {
      return false;
    }
    if (_selectedEndDate != null) {
      final endOfDay = _selectedEndDate!.add(const Duration(days: 1));
      if (alertDateTime.isAfter(endOfDay)) {
        return false;
      }
    }

    // Check time range
    if (_selectedStartTime != null || _selectedEndTime != null) {
      final alertTime = TimeOfDay.fromDateTime(alertDateTime);
      final alertMinutes = alertTime.hour * 60 + alertTime.minute;

      if (_selectedStartTime != null) {
        final startMinutes =
            _selectedStartTime!.hour * 60 + _selectedStartTime!.minute;
        if (alertMinutes < startMinutes) {
          return false;
        }
      }

      if (_selectedEndTime != null) {
        final endMinutes =
            _selectedEndTime!.hour * 60 + _selectedEndTime!.minute;
        if (alertMinutes > endMinutes) {
          return false;
        }
      }
    }

    return true;
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
            const SizedBox(height: 16),
            _buildDateTimeFilterCard(),
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

  Widget _buildAlertCardFromEntry(AlertEntry alert) {
    final DateTime ts = alert.timestamp > 0
        ? DateTime.fromMillisecondsSinceEpoch(alert.timestamp)
        : DateTime.now();
    final timeText = alert.timestamp > 0
        ? DateFormat('MMM d, hh:mm a').format(ts)
        : 'Just now';

    final bool isEmergency =
        alert.status.toLowerCase() == 'sos' ||
        alert.status.toLowerCase() == 'panic';
    final bool isEntry = alert.status.toLowerCase() == 'entry';
    final bool isExit = alert.status.toLowerCase() == 'exit';

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
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isEmergency
                            ? Colors.red.shade100
                            : isEntry
                            ? Colors.green.shade100
                            : isExit
                            ? Colors.orange.shade100
                            : Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isEmergency
                            ? Icons.warning_rounded
                            : isEntry
                            ? Icons.login_rounded
                            : isExit
                            ? Icons.logout_rounded
                            : Icons.info_outline,
                        color: isEmergency
                            ? Colors.red.shade700
                            : isEntry
                            ? Colors.green.shade700
                            : isExit
                            ? Colors.orange.shade700
                            : Colors.blue.shade700,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEmergency
                              ? 'Panic Button'
                              : isEntry
                              ? 'Geofence Entry'
                              : isExit
                              ? 'Geofence Exit'
                              : 'Alert from ${alert.childName ?? alert.deviceId}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          timeText,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (isEmergency)
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
              '${alert.lat.toStringAsFixed(6)}, ${alert.lng.toStringAsFixed(6)}',
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      isEmergency ? 'High Priority' : 'Normal',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isEmergency ? Colors.red : Colors.grey,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AlertMapScreen(
                          lat: alert.lat,
                          lng: alert.lng,
                          alertStatus: alert.status,
                          deviceId: alert.deviceId,
                          childName: alert.childName,
                          timestamp: DateTime.fromMillisecondsSinceEpoch(
                            alert.timestamp,
                          ),
                          otherAlerts: null,
                          onAlertViewed:
                              widget.onAlertViewed, // NEW: Pass the callback
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
                  _selectedEndDate != null ||
                  _selectedStartTime != null ||
                  _selectedEndTime != null)
                TextButton(
                  onPressed: _clearDateTimeFilters,
                  child: const Text(
                    'Clear',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Date Range
          GestureDetector(
            onTap: _selectDateRange,
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
                    _selectedStartDate != null && _selectedEndDate != null
                        ? '${DateFormat('MMM d').format(_selectedStartDate!)} - ${DateFormat('MMM d').format(_selectedEndDate!)}'
                        : 'Select Date Range',
                    style: TextStyle(
                      color: _selectedStartDate != null
                          ? Colors.black87
                          : Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  const Icon(
                    Icons.calendar_today,
                    size: 18,
                    color: Colors.grey,
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
                        Text(
                          _selectedStartTime != null
                              ? _selectedStartTime!.format(context)
                              : 'Start Time',
                          style: TextStyle(
                            color: _selectedStartTime != null
                                ? Colors.black87
                                : Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                        const Icon(
                          Icons.access_time,
                          size: 16,
                          color: Colors.grey,
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
                        Text(
                          _selectedEndTime != null
                              ? _selectedEndTime!.format(context)
                              : 'End Time',
                          style: TextStyle(
                            color: _selectedEndTime != null
                                ? Colors.black87
                                : Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                        const Icon(
                          Icons.access_time,
                          size: 16,
                          color: Colors.grey,
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

  Widget _buildRecentAlertsSection() {
    // Build from realtime alerts list with filtering
    final filteredAlerts = _alerts.where((a) {
      // Filter by alert type
      bool typeMatch = true;
      if (_selectedFilter == 'Panic') {
        typeMatch =
            a.status.toLowerCase() == 'sos' ||
            a.status.toLowerCase() == 'panic';
      } else if (_selectedFilter == 'Entry') {
        typeMatch = a.status.toLowerCase() == 'entry';
      } else if (_selectedFilter == 'Exit') {
        typeMatch = a.status.toLowerCase() == 'exit';
      }

      // Filter by date and time range
      bool dateTimeMatch = _isAlertInDateTimeRange(a);

      return typeMatch && dateTimeMatch;
    }).toList();

    // Group alerts by date
    Map<String, List<AlertEntry>> alertsByDate = {};
    for (var alert in filteredAlerts) {
      final date = DateTime.fromMillisecondsSinceEpoch(alert.timestamp);
      final dateKey = DateFormat('MMM d, yyyy').format(date);

      if (!alertsByDate.containsKey(dateKey)) {
        alertsByDate[dateKey] = [];
      }
      alertsByDate[dateKey]!.add(alert);
    }

    // Sort dates in descending order (newest first)
    final sortedDates = alertsByDate.keys.toList()
      ..sort((a, b) {
        final dateA = DateFormat('MMM d, yyyy').parse(a);
        final dateB = DateFormat('MMM d, yyyy').parse(b);
        return dateB.compareTo(dateA);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Recent Alerts",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (filteredAlerts.isEmpty)
          _buildEmptyAlertsMessage()
        else
          Column(
            children: sortedDates.map((dateKey) {
              final isExpanded = _expandedDateSections.contains(dateKey);
              final alertsForDate = alertsByDate[dateKey] ?? [];

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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '$dateKey (${alertsForDate.length} alerts)',
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
                      // Alerts for this date (shown when expanded)
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
                            children: alertsForDate
                                .map(
                                  (alert) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _buildAlertCardFromEntry(alert),
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
