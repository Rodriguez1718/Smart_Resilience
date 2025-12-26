// lib/screens/settings_screen.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:smart_resilience_app/services/notification_service.dart'; // Import your NotificationService
import 'package:firebase_auth/firebase_auth.dart'; // Import Firebase Auth
import 'package:cloud_firestore/cloud_firestore.dart'; // Import Cloud Firestore
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _smsEnabled = true; // NEW: SMS toggle state

  User? _currentUser;
  String? _guardianDocId; // Store the guardian document ID
  String? _currentUserName; // To store the user's full name for the AppBar
  String? _currentUserPhotoUrl; // To store the user's profile photo URL
  StreamSubscription<User?>?
  _authStateSubscription; // Declare nullable subscription
  StreamSubscription<DocumentSnapshot>? _profileDocSubscription;
  // NEW: Notification settings listener
  StreamSubscription<DocumentSnapshot>? _notificationSettingsSub;

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
                    _smsEnabled =
                        data['smsEnabled'] ?? true; // NEW: Load SMS state
                  });
                }
              });

          // Initialize notification settings if they don't exist
          _initializeNotificationSettings(guardianDocId);
          // Load notification settings
          _loadNotificationSettings();
        }
      } else {
        // User logged out, clear data
        setState(() {
          _currentUserName = null;
          _currentUserPhotoUrl = null;
          _guardianDocId = null;
          // Reset settings to default if user logs out
          _soundAlertEnabled = true;
          _vibrateOnlyEnabled = true;
          _bothSoundVibrationEnabled = true;
          _smsEnabled = true; // NEW: Reset SMS state on logout
        });
      }
    });
  }

  Future<void> _loadGuardianDocId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final docId = prefs.getString('guardianDocId');
      if (docId != null && docId.isNotEmpty) {
        setState(() {
          _guardianDocId = docId;
        });
        print('✅ SettingsScreen: Loaded guardian doc ID: $docId');
      }
    } catch (e) {
      print('❌ SettingsScreen: Error loading guardian doc ID: $e');
    }
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel(); // Cancel the subscription
    _profileDocSubscription?.cancel(); // Cancel profile doc listener
    _notificationSettingsSub
        ?.cancel(); // NEW: Cancel notification settings listener
    super.dispose();
  }

  // NEW: Initialize notification settings document if it doesn't exist
  Future<void> _initializeNotificationSettings(String userId) async {
    try {
      final settingsRef = FirebaseFirestore.instance
          .collection('guardians')
          .doc(userId)
          .collection('settings')
          .doc('notifications');

      // Check if the document exists
      final docSnapshot = await settingsRef.get();

      if (!docSnapshot.exists) {
        // Document doesn't exist, create it with default values
        await settingsRef.set({
          'soundAlertEnabled': true,
          'vibrateOnlyEnabled': true,
          'bothSoundVibrationEnabled': true,
          'lastUpdated': FieldValue.serverTimestamp(),
          'isPlaceholder': false,
        });
        print("Notification settings initialized for user: $userId");
      }
    } catch (e) {
      print("Error initializing notification settings: $e");
    }
  }

  Future<void> _loadNotificationSettings() async {
    if (_guardianDocId == null) {
      print("Cannot load notification settings: Guardian doc ID is null.");
      return;
    }

    try {
      // Cancel existing subscription if any
      await _notificationSettingsSub?.cancel();

      // Listen to the notification settings document in real-time
      _notificationSettingsSub = FirebaseFirestore.instance
          .collection('guardians')
          .doc(_guardianDocId!)
          .collection('settings')
          .doc('notifications')
          .snapshots()
          .listen(
            (settingsDoc) {
              if (!mounted) return;

              if (settingsDoc.exists && settingsDoc.data() != null) {
                final data = settingsDoc.data() as Map<String, dynamic>;
                // Check for the placeholder and actual data
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
                // If settings doc doesn't exist at all, assume default true
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
        _buildSMSAlertToggle(), // NEW: SMS toggle section
        const SizedBox(height: 24),
        _buildPreviewAlertFeedbackButton(),
        const SizedBox(height: 24),
        _buildAppFeedbackButton(), // NEW: Feedback button
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
                if (_guardianDocId != null) {
                  final doc = await FirebaseFirestore.instance
                      .collection('guardians')
                      .doc(_guardianDocId)
                      .get();
                  if (doc.exists && doc.data() != null) {
                    final data = doc.data() as Map<String, dynamic>;
                    setState(() {
                      _currentUserName =
                          data['fullName'] ??
                          _currentUser?.phoneNumber ??
                          'Guardian';
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

  // NEW: SMS Alert Toggle
  Widget _buildSMSAlertToggle() {
    return _buildSettingToggleCard(
      title: "SMS Alerts",
      description: "Send text messages for critical alerts",
      value: _smsEnabled,
      onChanged: (bool value) {
        setState(() {
          _smsEnabled = value;
        });
        print("SMS Alerts: $value");
        // Save SMS setting to guardians root document
        if (_currentUser != null) {
          FirebaseFirestore.instance
              .collection('guardians')
              .doc(_currentUser!.uid)
              .update({'smsEnabled': value})
              .catchError((error) {
                print("Error updating SMS setting: $error");
              });
        }
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

  // NEW: App Feedback Button
  Widget _buildAppFeedbackButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _showFeedbackDialog,
        icon: const Icon(Icons.feedback),
        label: const Text(
          "Send Feedback",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 3,
        ),
      ),
    );
  }

  // NEW: Show feedback dialog
  void _showFeedbackDialog() {
    final feedbackController = TextEditingController();
    String selectedCategory = 'General';
    final categories = ['General', 'Bug Report', 'Feature Request', 'Other'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Send Feedback'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Help us improve Smart Resilience',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 16),
                // Category Dropdown
                const Text(
                  'Category',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                DropdownButton<String>(
                  value: selectedCategory,
                  isExpanded: true,
                  items: categories.map((String category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(category),
                    );
                  }).toList(),
                  onChanged: (String? value) {
                    if (value != null) {
                      setState(() {
                        selectedCategory = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                // Feedback Text Field
                const Text(
                  'Your Feedback',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: feedbackController,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: 'Please share your thoughts...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (feedbackController.text.trim().isNotEmpty) {
                  _submitFeedback(feedbackController.text, selectedCategory);
                  Navigator.of(context).pop();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter your feedback')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  // NEW: Submit feedback to Firestore
  Future<void> _submitFeedback(String feedbackText, String category) async {
    if (_guardianDocId == null) {
      print("❌ Cannot submit feedback: Guardian doc ID is not available");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: User information not available')),
      );
      return;
    }

    try {
      final feedbackData = {
        'userId': _guardianDocId,
        'userPhone': _currentUser?.phoneNumber ?? 'Unknown',
        'userName': _currentUserName ?? 'Guardian',
        'category': category,
        'feedbackText': feedbackText,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'unread', // For admin to mark as read
      };

      print('📝 Submitting feedback data: $feedbackData');

      // Store feedback in both locations for redundancy and admin access
      // 1. In user's subcollection (for user reference)
      print('📝 Writing to guardians/$_guardianDocId/feedback/...');
      await FirebaseFirestore.instance
          .collection('guardians')
          .doc(_guardianDocId!)
          .collection('feedback')
          .add(feedbackData);
      print('✅ Successfully wrote to guardians collection');

      // 2. In top-level admin_feedback collection (for easy admin access)
      print('📝 Writing to admin_feedback/...');
      await FirebaseFirestore.instance
          .collection('admin_feedback')
          .add(feedbackData);
      print('✅ Successfully wrote to admin_feedback collection');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thank you! Your feedback has been submitted.'),
          backgroundColor: Colors.green,
        ),
      );
      print("✅ Feedback submitted successfully");
    } catch (e, stackTrace) {
      print("❌ Error submitting feedback: $e");
      print("❌ Stack trace: $stackTrace");
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error submitting feedback: $e')));
    }
  }
}
