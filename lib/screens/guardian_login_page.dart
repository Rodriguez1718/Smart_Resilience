import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_resilience_app/screens/main_navigation.dart';
import 'package:smart_resilience_app/screens/guardian_setup_screen.dart';
import 'package:smart_resilience_app/screens/success_animation_screen.dart';
import 'package:smart_resilience_app/services/custom_otp_service.dart';

class GuardianLoginPage extends StatefulWidget {
  const GuardianLoginPage({super.key});

  @override
  State<GuardianLoginPage> createState() => _GuardianLoginPageState();
}

class _GuardianLoginPageState extends State<GuardianLoginPage> {
  final TextEditingController _phoneNumberController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  // Note: Removed _fullNameController and related logic, as the navigation
  // to GuardianSetupScreen now handles the profile completion outside of this page.

  String? _verificationId;
  bool _codeSent =
      false; // Controls whether to show OTP input or phone number input
  bool _isLoading = false; // For showing loading indicators
  int _otpCountdown = 0; // Countdown timer for OTP resend button

  @override
  void dispose() {
    _phoneNumberController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Sign out any existing user to ensure fresh login with phone number
    FirebaseAuth.instance.signOut();
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
      // Send OTP via custom iProgsms service
      bool otpSent = await CustomOtpService.sendOtp(
        phoneNumber: phoneNumber,
        fullName: 'Guardian', // Placeholder name for login
      );

      if (otpSent) {
        setState(() {
          _codeSent = true;
          _isLoading = false;
          _otpCountdown = 300; // 5 minutes countdown
          _startOtpCountdown(); // Start countdown timer
        });
        _showSnackBar('OTP sent to your phone. Valid for 5 minutes.');
      } else {
        setState(() {
          _isLoading = false;
        });
        _showSnackBar('Failed to send OTP. Please try again.');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint('Error sending OTP: $e');
      _showSnackBar('Error sending OTP: $e');
    }
  }

  /// Start countdown timer for OTP expiration
  void _startOtpCountdown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _codeSent) {
        setState(() {
          _otpCountdown--;
        });
        if (_otpCountdown > 0) {
          _startOtpCountdown();
        }
      }
    });
  }

  // Normalize phone number to E.164 for the Philippines (+63).
  String _normalizePhoneNumber(String input) {
    String phone = input.trim();
    if (phone.isEmpty) return phone;
    // Remove all non-digit characters except for a leading '+'
    phone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (phone.startsWith('+')) return phone;
    if (phone.startsWith('0')) phone = phone.substring(1);
    // Assuming Philippine mobile numbers (10 digits after country code 63)
    if (phone.length == 10 && phone.startsWith('9')) {
      return '+63$phone';
    }
    return '+63$phone'; // Defaulting to +63 prepended
  }

  // Function to verify the entered OTP
  Future<void> _verifyOtp() async {
    if (_otpController.text.isEmpty) {
      _showSnackBar('Please enter the OTP.');
      return;
    }

    if (_otpController.text.length != 6) {
      _showSnackBar('OTP must be 6 digits.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Verify OTP using custom service
      bool isValid = CustomOtpService.verifyOtp(
        phoneNumber: _phoneNumberController.text,
        otp: _otpController.text,
      );

      if (isValid) {
        print('[Guardian Login] OTP verified successfully');

        // Clear the OTP after successful verification
        CustomOtpService.clearOtp(_phoneNumberController.text);

        // Sign in anonymously to get Firestore access
        UserCredential anonAuth = await FirebaseAuth.instance
            .signInAnonymously();
        String anonUid = anonAuth.user?.uid ?? '';
        print('[Guardian Login] Anonymous auth UID: $anonUid');

        // Check if guardian profile exists
        String normalizedPhone = _normalizePhoneNumber(
          _phoneNumberController.text,
        );

        // Query Firestore for existing guardian with this phone
        QuerySnapshot snapshot = await FirebaseFirestore.instance
            .collection('guardians')
            .where('phoneNumber', isEqualTo: normalizedPhone)
            .limit(1)
            .get();

        if (snapshot.docs.isNotEmpty) {
          // Existing guardian found
          String userId = snapshot.docs.first.id;
          final guardianData =
              snapshot.docs.first.data() as Map<String, dynamic>?;
          String? userName = guardianData?['fullName'] as String?;

          print('[Guardian Login] Found guardian document with ID: $userId');

          // Save to local storage for future use
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('guardianDocId', userId);
          await prefs.setString('guardianPhoneNumber', normalizedPhone);
          print('[Guardian Login] Saved guardian ID to local storage: $userId');

          // Update lastLogin with the guardian's actual document ID
          await FirebaseFirestore.instance
              .collection('guardians')
              .doc(userId)
              .set({
                'lastLogin': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));

          print('[Guardian Login] Existing guardian found: $userId');
          _showSnackBar('Welcome back, ${userName ?? 'User'}!');
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => const SuccessAnimationScreen(),
              ),
            );
          }
        } else {
          // New guardian - redirect to setup screen
          print('[Guardian Login] No guardian found, redirecting to setup');
          _showSnackBar('Profile not found. Please complete setup.');
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => const GuardianSetupScreen(),
              ),
            );
          }
        }
      } else {
        setState(() {
          _isLoading = false;
        });
        _showSnackBar('Invalid or expired OTP. Please try again.');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint('Error during OTP verification: $e');
      _showSnackBar('An unexpected error occurred: $e');
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

        // Determine if profile completion is needed (checking for 'fullName')
        if (!userDoc.exists || data == null || data['fullName'] == null) {
          // Profile is incomplete or doesn't exist, redirect to setup/completion
          _showSnackBar('Welcome! Please complete your profile.');
          if (mounted) {
            // Redirect to GuardianSetupScreen to complete profile
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => const GuardianSetupScreen(),
              ),
            );
          }
        } else {
          // Existing user with a complete profile: update last login and navigate
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
            // Navigate to SuccessAnimationScreen
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
      debugPrint('Firebase Auth Error after sign-in: ${e.message}');
      _showSnackBar('Authentication failed: ${e.message}');
    } catch (e) {
      debugPrint('Error signing in with credential: $e');
      _showSnackBar('An unexpected error occurred during sign-in.');
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
          // "Don't have an account?" button
          if (!_codeSent) // Only show if not in OTP
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
          const Text(
            "Guardian Login",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _codeSent
                ? "Enter the OTP sent to your phone."
                : "Enter your phone number to receive an OTP. (Philippines +63)",
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 24),

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
              maxLength: 6,
            ),
            const SizedBox(height: 8),
            // Countdown timer info
            Text(
              _otpCountdown > 0
                  ? 'OTP expires in ${(_otpCountdown ~/ 60)}:${(_otpCountdown % 60).toString().padLeft(2, '0')}'
                  : 'OTP expired',
              style: TextStyle(
                color: _otpCountdown > 30 ? Colors.grey[600] : Colors.red,
                fontSize: 12,
              ),
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
            // Resend OTP button
            TextButton(
              onPressed: (_isLoading || _otpCountdown > 0) ? null : _sendOtp,
              child: Text(
                _otpCountdown > 0
                    ? 'Resend in ${(_otpCountdown ~/ 60)}:${(_otpCountdown % 60).toString().padLeft(2, '0')}'
                    : 'Resend OTP',
              ),
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
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      enabled: enabled, // Apply enabled state
      maxLength: maxLength,
      decoration: InputDecoration(
        prefixText: prefixText,
        prefixStyle: const TextStyle(color: Colors.black87),
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
