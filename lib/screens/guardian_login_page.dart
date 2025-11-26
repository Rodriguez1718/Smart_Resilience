// lib/screens/guardian_login_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import Firebase Auth
import 'package:cloud_firestore/cloud_firestore.dart'; // Import Cloud Firestore
import 'package:smart_resilience_app/screens/main_navigation.dart'; // Ensure this path is correct
import 'package:smart_resilience_app/screens/guardian_setup_screen.dart'; // Import GuardianSetupScreen
import 'package:smart_resilience_app/screens/success_animation_screen.dart'; // Import SuccessAnimationScreen

class GuardianLoginPage extends StatefulWidget {
  const GuardianLoginPage({super.key});

  @override
  State<GuardianLoginPage> createState() => _GuardianLoginPageState();
}

class _GuardianLoginPageState extends State<GuardianLoginPage> {
  final TextEditingController _phoneNumberController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _fullNameController =
      TextEditingController(); // For new user registration
  String? _verificationId;
  bool _codeSent =
      false; // Controls whether to show OTP input or phone number input
  bool _isLoading = false; // For showing loading indicators
  bool _needsProfileCompletion =
      false; // NEW: To track if profile completion is needed after auth

  @override
  void dispose() {
    _phoneNumberController.dispose();
    _otpController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  // Function to send OTP to the provided phone number
  Future<void> _sendOtp() async {
    if (_phoneNumberController.text.isEmpty) {
      _showSnackBar('Please enter your phone number.');
      return;
    }

    // Format phone number to E.164 format (e.g., +639123456789)
    String phoneNumber = _phoneNumberController.text.trim();
    phoneNumber = _normalizePhoneNumber(phoneNumber);

    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // This callback is fired when auto-retrieval (Android) or instant verification succeeds.
          setState(() {
            _isLoading = false;
          });
          _showSnackBar('Phone number automatically verified!');
          await _signInWithCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          // This callback is fired when verification fails (e.g., invalid phone number)
          setState(() {
            _isLoading = false;
          });
          print('Phone verification failed: ${e.message}');
          _showSnackBar('Verification failed: ${e.message}');
        },
        codeSent: (String verificationId, int? resendToken) {
          // This callback is fired when the SMS code is successfully sent.
          setState(() {
            _verificationId = verificationId;
            _codeSent = true; // Show the OTP input field
            _isLoading = false;
          });
          _showSnackBar('OTP sent to your phone.');
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          // This callback is fired when auto-retrieval times out.
          setState(() {
            _verificationId = verificationId;
            _isLoading = false;
          });
          _showSnackBar('OTP auto-retrieval timed out. Please enter manually.');
        },
        timeout: const Duration(seconds: 60), // OTP validity period
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('Error sending OTP: $e');
      _showSnackBar('Error sending OTP: $e');
    }
  }

  // Normalize phone number to E.164 for the Philippines (+63).
  // Accepts inputs like:
  // - "+639123456789" -> returned unchanged
  // - "9123456789" -> "+639123456789"
  // - "09123456789" -> "+639123456789"
  String _normalizePhoneNumber(String input) {
    String phone = input.trim();
    if (phone.isEmpty) return phone;
    if (phone.startsWith('+')) return phone;
    if (phone.startsWith('0')) phone = phone.substring(1);
    return '+63$phone';
  }

  // Function to verify the entered OTP
  Future<void> _verifyOtp() async {
    if (_otpController.text.isEmpty || _verificationId == null) {
      _showSnackBar('Please enter the OTP.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otpController.text,
      );
      await _signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('Error verifying OTP: ${e.message}');
      _showSnackBar('Invalid OTP. Please try again. ${e.message}');
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('Error during OTP verification: $e');
      _showSnackBar('An unexpected error occurred during OTP verification.');
    }
  }

  // Function to sign in with the credential and check/create Firestore profile
  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential);
      User? user = userCredential.user;

      if (user != null) {
        // Check if guardian profile exists in Firestore using the user's UID
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('guardians')
            .doc(user.uid)
            .get();

        final data = userDoc.data() as Map<String, dynamic>?;

        // Determine if profile completion is needed
        if (!userDoc.exists ||
            data == null ||
            !data.containsKey('fullName') ||
            data['fullName'] == null) {
          // Profile is incomplete or doesn't exist, redirect to setup/completion
          _showSnackBar('Welcome! Please complete your profile.');
          if (mounted) {
            // Redirect to GuardianSetupScreen to complete profile
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) =>
                    const GuardianSetupScreen(), // This screen will handle profile completion
              ),
            );
          }
        } else {
          // Existing user with a complete profile: update last login and navigate to SuccessAnimationScreen
          await FirebaseFirestore.instance
              .collection('guardians')
              .doc(user.uid)
              .set({
                'lastLogin': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));

          String? userName =
              data['fullName'] as String?; // Safely access fullName
          _showSnackBar('Welcome back, ${userName ?? 'User'}!');
          if (mounted) {
            // CHANGED: Navigate to SuccessAnimationScreen instead of MainNavigation directly
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) =>
                    const SuccessAnimationScreen(), // Redirect to SuccessAnimationScreen
              ),
            );
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('Firebase Auth Error after sign-in: ${e.message}');
      _showSnackBar('Authentication failed: ${e.message}');
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('Error signing in with credential: $e');
      _showSnackBar('An unexpected error occurred during sign-in.');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // This method is for saving the full name ONLY when _needsProfileCompletion is true
  // It's called from within this page's UI when the user enters their name.
  Future<void> _saveProfileAndNavigate() async {
    if (_fullNameController.text.isEmpty) {
      _showSnackBar('Please enter your full name.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackBar('Error: No authenticated user found.');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Update the existing guardian profile document with the full name
      await FirebaseFirestore.instance
          .collection('guardians')
          .doc(user.uid)
          .set({
            'fullName': _fullNameController.text.trim(),
            'phoneNumber':
                user.phoneNumber ??
                _normalizePhoneNumber(_phoneNumberController.text.trim()),
            // Ensure phone number is also saved/updated (normalized to +63...)
            'lastLogin': FieldValue.serverTimestamp(),
            'hasCompletedSetup': true, // Mark setup as complete
          }, SetOptions(merge: true));

      // Ensure subcollections exist for the new user
      await FirebaseFirestore.instance
          .collection('guardians')
          .doc(user.uid)
          .collection('geofences')
          .doc('initial_geofence_placeholder') // Using a placeholder document
          .set({
            'createdAt': FieldValue.serverTimestamp(),
            'isPlaceholder': true,
          }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('guardians')
          .doc(user.uid)
          .collection('settings')
          .doc('initial_settings_placeholder') // Using a placeholder document
          .set({
            'createdAt': FieldValue.serverTimestamp(),
            'isPlaceholder': true,
          }, SetOptions(merge: true));

      _showSnackBar('Profile saved successfully! Welcome!');
      if (mounted) {
        // Navigate to success animation after profile is fully saved
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const SuccessAnimationScreen(),
          ),
        );
      }
    } catch (e) {
      print('Error saving new guardian profile: $e');
      _showSnackBar('Failed to save profile: $e');
    } finally {
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
    return Scaffold(
      backgroundColor: Colors.grey[50], // Consistent background color
      appBar: _buildAppBar(), // Use the consistent AppBar
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildLoginContentCard(), // Main content wrapped in a card
          const SizedBox(height: 24),
          // "Don't have an account?" button, only visible if not in profile completion flow
          if (!_needsProfileCompletion &&
              !_codeSent) // Only show if not in OTP or profile completion
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Don't have an account?"),
                TextButton(
                  onPressed: () {
                    // Navigate to GuardianSetupScreen for new registrations
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const GuardianSetupScreen(),
                      ),
                    );
                  },
                  child: const Text("Sign Up"),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // --- Reusable AppBar from GuardianSetupScreen ---
  AppBar _buildAppBar() {
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
      actions: const [],
    );
  }

  // --- Main content card, inspired by GuardianSetupScreen's card ---
  Widget _buildLoginContentCard() {
    return Container(
      padding: const EdgeInsets.all(20),
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
            _needsProfileCompletion
                ? "Complete Your Profile"
                : "Guardian Login",
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _needsProfileCompletion
                ? "Please provide your full name to complete setup."
                : (_codeSent
                      ? "Enter the OTP sent to your phone."
                      : "Enter your phone number to receive an OTP."),
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 24),
          if (_needsProfileCompletion) ...[
            // UI for new user to enter full name after successful phone auth
            _buildTextField(
              controller: _fullNameController,
              labelText: "Full Name",
              hintText: "Enter your full name",
              enabled: true, // Always enabled for profile completion
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : _saveProfileAndNavigate, // Call new save method
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade500,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 3,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "Complete Setup",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ] else ...[
            // UI for phone number and OTP input
            _buildTextField(
              controller: _phoneNumberController,
              labelText: "Phone Number",
              hintText: "e.g., 9123456789 (no leading 0)",
              keyboardType: TextInputType.phone,
              enabled:
                  !_codeSent, // Disable if code sent to prevent changing number
              prefixText: '+63 ',
            ),
            const SizedBox(height: 16),
            if (_codeSent) ...[
              _buildTextField(
                controller: _otpController,
                labelText: "OTP",
                hintText: "Enter 6-digit code",
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        Colors.blue.shade500, // Different color for verify
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 3,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "Verify OTP",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              // Optional: Resend OTP button
              TextButton(
                onPressed: _isLoading ? null : _sendOtp, // Allow resend
                child: const Text('Resend OTP'),
              ),
            ] else ...[
              // Initial state: only phone number and send OTP button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _sendOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade500,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 3,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "Send OTP",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // --- Reusable TextField from GuardianSetupScreen ---
  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    TextInputType keyboardType = TextInputType.text,
    bool enabled = true, // Added enabled parameter for consistency
    String? prefixText,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      enabled: enabled, // Apply enabled state
      decoration: InputDecoration(
        prefixText: prefixText,
        prefixStyle: TextStyle(color: Colors.black87),
        labelText: labelText,
        hintText: hintText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.green.shade500, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
