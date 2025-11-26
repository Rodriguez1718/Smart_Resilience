// lib/screens/settings_screen.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:smart_resilience_app/services/notification_service.dart'; // Import your NotificationService
import 'package:firebase_auth/firebase_auth.dart'; // Import Firebase Auth
import 'package:cloud_firestore/cloud_firestore.dart'; // Import Cloud Firestore
import 'package:smart_resilience_app/screens/profile_page.dart'; // Import ProfilePage
import 'package:smart_resilience_app/widgets/profile_avatar.dart';
import 'dart:async'; // Import for StreamSubscription

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // States for the toggle switches
  // Ensure these initial values match your desired default state or
  // are loaded from persistent storage (e.g., SharedPreferences, Firebase)
  bool _soundAlertEnabled = true;
  bool _vibrateOnlyEnabled = true;
  bool _bothSoundVibrationEnabled = true;

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

        // Potentially load notification settings here if they depend on user ID
        _loadNotificationSettings();
      } else {
        // User logged out, clear data
        setState(() {
          _currentUserName = null;
          _currentUserPhotoUrl = null;
          // Reset settings to default if user logs out
          _soundAlertEnabled = true;
          _vibrateOnlyEnabled = true;
          _bothSoundVibrationEnabled = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel(); // Cancel the subscription
    _profileDocSubscription?.cancel(); // Cancel profile doc listener
    super.dispose();
  }

  Future<void> _loadNotificationSettings() async {
    if (_currentUser == null) {
      print("Cannot load notification settings: User ID is null.");
      return;
    }

    try {
      DocumentSnapshot settingsDoc = await FirebaseFirestore.instance
          .collection('guardians')
          .doc(_currentUser!.uid)
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
            _soundAlertEnabled =
                true; // Default to true if only placeholder exists
            _vibrateOnlyEnabled = true;
            _bothSoundVibrationEnabled = true;
          });
          // Optionally, save the default setting to replace the placeholder
          await _saveNotificationSettings(
            sound: true,
            vibrate: true,
            both: true,
          ); // Save initial defaults
        } else {
          setState(() {
            _soundAlertEnabled = data['soundAlertEnabled'] ?? true;
            _vibrateOnlyEnabled = data['vibrateOnlyEnabled'] ?? true;
            _bothSoundVibrationEnabled =
                data['bothSoundVibrationEnabled'] ?? true;
          });
        }
      } else {
        // If settings doc doesn't exist at all, assume default true and save it
        setState(() {
          _soundAlertEnabled = true;
          _vibrateOnlyEnabled = true;
          _bothSoundVibrationEnabled = true;
        });
        await _saveNotificationSettings(sound: true, vibrate: true, both: true);
      }
    } catch (e) {
      print("Error loading notification settings: $e");
    }
  }

  Future<void> _saveNotificationSettings({
    bool? sound,
    bool? vibrate,
    bool? both,
  }) async {
    if (_currentUser == null) {
      print("Cannot save notification settings: User ID is null.");
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('guardians')
          .doc(_currentUser!.uid)
          .collection('settings')
          .doc('notifications')
          .set({
            'soundAlertEnabled': sound ?? _soundAlertEnabled,
            'vibrateOnlyEnabled': vibrate ?? _vibrateOnlyEnabled,
            'bothSoundVibrationEnabled': both ?? _bothSoundVibrationEnabled,
            'lastUpdated': FieldValue.serverTimestamp(),
            'isPlaceholder': false, // Mark as not a placeholder once saved
          }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification settings updated!')),
      );
    } catch (e) {
      print("Error saving notification settings: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error saving notification settings: $e")),
      );
    }
  }

  Widget _buildSettingsContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildAlertFeedbackPreferencesSection(),
        const SizedBox(height: 16),
        _buildSoundAlertToggle(),
        const SizedBox(height: 8),
        _buildVibrateOnlyToggle(),
        const SizedBox(height: 8),
        _buildBothSoundVibrationToggle(),
        const SizedBox(height: 24),
        _buildLocationSettingsSection(),
        const SizedBox(height: 16),
        _buildGeofenceSettingsSection(),
        const SizedBox(height: 16),
        _buildPrivacySettingsSection(),
        const SizedBox(height: 16),
        _buildAppSettingsSection(),
        const SizedBox(height: 24),
        _buildPreviewAlertFeedbackButton(),
        const SizedBox(height: 16),
      ],
    );
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
      // REMOVE backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(initial), // Pass the initial for the avatar
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.green.shade100, // Light green
              Colors.blue.shade100, // Light blue (mixes well with green)
              Colors.green.shade50, // Even lighter green
            ],
          ),
        ),
        child: _buildSettingsContent(),
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
                Icons.location_on, // Changed icon to settings
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

  Widget _buildAlertFeedbackPreferencesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Notification Settings",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          "Configure how you receive alerts and notifications",
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildSettingToggleCard({
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
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
                Text(
                  description,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.green, // Matching the green from home_screen
          ),
        ],
      ),
    );
  }

  Widget _buildSoundAlertToggle() {
    return _buildSettingToggleCard(
      title: "Sound Alert",
      description: "Play notification sound when alerts are triggered",
      value: _soundAlertEnabled,
      onChanged: (bool value) {
        setState(() {
          _soundAlertEnabled = value;
          // You might want to add logic here to make these toggles mutually exclusive
          // For example, if Sound Alert is enabled, disable "Vibrate Only" and "Both".
          // Or, as per your UI, they are independent.
        });
        print("Sound Alert: $value");
        _saveNotificationSettings(sound: value); // Save this specific setting
      },
    );
  }

  Widget _buildVibrateOnlyToggle() {
    return _buildSettingToggleCard(
      title: "Vibrate Only",
      description: "Use vibration for silent notifications",
      value: _vibrateOnlyEnabled,
      onChanged: (bool value) {
        setState(() {
          _vibrateOnlyEnabled = value;
        });
        print("Vibrate Only: $value");
        _saveNotificationSettings(vibrate: value); // Save this specific setting
      },
    );
  }

  Widget _buildBothSoundVibrationToggle() {
    return _buildSettingToggleCard(
      title: "Both Sound & Vibration",
      description: "Maximum alert feedback for critical notifications",
      value: _bothSoundVibrationEnabled,
      onChanged: (bool value) {
        setState(() {
          _bothSoundVibrationEnabled = value;
        });
        print("Both Sound & Vibration: $value");
        _saveNotificationSettings(both: value); // Save this specific setting
      },
    );
  }

  Widget _buildPreviewAlertFeedbackButton() {
    return SizedBox(
      width: double.infinity, // Make it take full width
      child: ElevatedButton(
        onPressed: () {
          print("Preview Alert Feedback pressed!");
          // Determine the notification settings based on the toggles
          bool playSound = _soundAlertEnabled;
          bool vibrate = _vibrateOnlyEnabled;
          bool both = _bothSoundVibrationEnabled;

          // Call the NotificationService to show the notification
          // Pass the determined preferences to the service
          NotificationService.showAlarmNotification(
            title: "Test Alert",
            body: "This is a preview of your alert feedback.",
            playSound: playSound,
            vibrate: vibrate,
            both: both,
          );

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Playing alert feedback preview...')),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor:
              Colors.blue, // A distinct color for the action button
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 3,
        ),
        child: const Text(
          "Preview Alert Feedback",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildLocationSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Location Settings",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _buildSettingToggleCard(
          title: "High Accuracy Location",
          description: "Use GPS for precise location tracking",
          value: true,
          onChanged: (value) {
            // TODO: Implement location accuracy setting
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Location accuracy: ${value ? "High" : "Standard"}',
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        _buildSettingToggleCard(
          title: "Background Location",
          description: "Track location when app is in background",
          value: true,
          onChanged: (value) {
            // TODO: Implement background location setting
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Background tracking: ${value ? "Enabled" : "Disabled"}',
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildGeofenceSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Safe Zone Settings",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _buildSettingToggleCard(
          title: "Entry Notifications",
          description: "Get notified when child enters a safe zone",
          value: true,
          onChanged: (value) {
            // TODO: Implement geofence entry notifications
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Entry notifications: ${value ? "Enabled" : "Disabled"}',
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        _buildSettingToggleCard(
          title: "Exit Notifications",
          description: "Get notified when child leaves a safe zone",
          value: true,
          onChanged: (value) {
            // TODO: Implement geofence exit notifications
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Exit notifications: ${value ? "Enabled" : "Disabled"}',
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPrivacySettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Privacy & Security",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _buildSettingToggleCard(
          title: "Data Encryption",
          description: "Encrypt location data for enhanced security",
          value: true,
          onChanged: (value) {
            // TODO: Implement data encryption setting
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Data encryption: ${value ? "Enabled" : "Disabled"}',
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        _buildSettingToggleCard(
          title: "Location History",
          description: "Store location history for route tracking",
          value: true,
          onChanged: (value) {
            // TODO: Implement location history setting
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Location history: ${value ? "Enabled" : "Disabled"}',
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAppSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "App Settings",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _buildSettingToggleCard(
          title: "Auto-Update Location",
          description: "Automatically refresh location every 5 minutes",
          value: true,
          onChanged: (value) {
            // TODO: Implement auto-update setting
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Auto-update: ${value ? "Enabled" : "Disabled"}'),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        _buildSettingToggleCard(
          title: "Battery Optimization",
          description: "Optimize app for better battery life",
          value: false,
          onChanged: (value) {
            // TODO: Implement battery optimization setting
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Battery optimization: ${value ? "Enabled" : "Disabled"}',
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        _buildSettingToggleCard(
          title: "Dark Mode",
          description: "Use dark theme for better visibility",
          value: false,
          onChanged: (value) {
            // TODO: Implement dark mode setting
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Dark mode: ${value ? "Enabled" : "Disabled"}'),
              ),
            );
          },
        ),
      ],
    );
  }
}
