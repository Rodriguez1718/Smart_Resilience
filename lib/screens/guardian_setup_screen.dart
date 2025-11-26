// lib/screens/guardian_setup_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Import Cloud Firestore
import 'package:firebase_auth/firebase_auth.dart'; // Import Firebase Auth
import 'package:smart_resilience_app/screens/success_animation_screen.dart'; // Import your SuccessAnimationScreen
import 'package:smart_resilience_app/screens/guardian_login_page.dart'; // Import GuardianLoginPage for navigation

class GuardianSetupScreen extends StatefulWidget {
  const GuardianSetupScreen({super.key});

  @override
  State<GuardianSetupScreen> createState() => _GuardianSetupScreenState();
}

class _GuardianSetupScreenState extends State<GuardianSetupScreen> {
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneNumberController = TextEditingController();
  final TextEditingController _otpController =
      TextEditingController(); // For OTP input

  String? _verificationId; // Stores the verification ID from Firebase
  bool _codeSent = false; // Controls UI whether OTP input should be shown
  bool _isLoading = false; // To show loading state during save or OTP process

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneNumberController.dispose();
    _otpController.dispose(); // Dispose OTP controller
    super.dispose();
  }

  // Function to send OTP to the provided phone number
  Future<void> _sendOtp() async {
    if (_phoneNumberController.text.isEmpty) {
      _showSnackBar('Please enter your phone number.');
      return;
    }
    if (_fullNameController.text.isEmpty) {
      _showSnackBar('Please enter your full name.');
      return;
    }

    String phoneNumber = _phoneNumberController.text.trim();
    if (!phoneNumber.startsWith('+')) {
      phoneNumber =
          '+63$phoneNumber'; // Assuming Philippines as default country. Adjust if needed.
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          setState(() {
            _isLoading = false;
          });
          _showSnackBar('Phone number automatically verified!');
          await _signInAndSaveProfile(
            credential,
          ); // Proceed to sign in and save profile
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() {
            _isLoading = false;
          });
          print('Phone verification failed: ${e.message}');
          _showSnackBar('Verification failed: ${e.message}');
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _codeSent = true; // Show the OTP input field
            _isLoading = false;
          });
          _showSnackBar('OTP sent to your phone.');
        },
        codeAutoRetrievalTimeout: (String verificationId) {
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
      await _signInAndSaveProfile(
        credential,
      ); // Proceed to sign in and save profile
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

  // Combined function to sign in with credential and save/update guardian profile
  Future<void> _signInAndSaveProfile(PhoneAuthCredential credential) async {
    try {
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential);
      User? user = userCredential.user;

      if (user != null) {
        // Save guardian profile to 'guardians' collection using the authenticated user's UID.
        // This ensures the Firestore document is directly linked to the Firebase Auth user.
        await FirebaseFirestore.instance
            .collection('guardians')
            .doc(user.uid)
            .set(
              {
                'fullName': _fullNameController.text.trim(),
                'phoneNumber':
                    user.phoneNumber ?? _phoneNumberController.text.trim(),
                'createdAt': FieldValue.serverTimestamp(),
                'lastLogin': FieldValue.serverTimestamp(),
                'hasCompletedSetup': true, // Mark setup as complete
              },
              SetOptions(merge: true),
            ); // Use merge:true to update if doc exists

        // NEW: Create a dummy document in the 'geofences' subcollection
        // This ensures the 'geofences' collection path exists for the user immediately.
        await FirebaseFirestore.instance
            .collection('guardians')
            .doc(user.uid)
            .collection('geofences')
            .doc(
              'initial_geofence_placeholder',
            ) // Use a unique ID for the placeholder
            .set(
              {
                'createdAt': FieldValue.serverTimestamp(),
                'isPlaceholder': true, // Mark it as a placeholder
              },
              SetOptions(merge: true),
            ); // Use merge:true in case it somehow already exists

        // NEW: Create a dummy document in the 'settings' subcollection as well
        // This ensures the 'settings' collection path exists for the user immediately.
        await FirebaseFirestore.instance
            .collection('guardians')
            .doc(user.uid)
            .collection('settings')
            .doc(
              'initial_settings_placeholder',
            ) // Use a unique ID for the placeholder
            .set({
              'createdAt': FieldValue.serverTimestamp(),
              'isPlaceholder': true, // Mark it as a placeholder
            }, SetOptions(merge: true));

        _showSnackBar('Profile created and saved successfully! Welcome!');
        if (mounted) {
          // Navigate to the SuccessAnimationScreen after successful save.
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) =>
                  const SuccessAnimationScreen(), // Redirect to the animation screen
            ),
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      print(
        'Firebase Auth Error during sign-in and profile save: ${e.message}',
      );
      _showSnackBar('Authentication failed: ${e.message}');
    } catch (e) {
      print('Error during sign-in or profile save: $e');
      _showSnackBar('An unexpected error occurred: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // The original _onNextStepPressed now initiates the OTP sending process
  void _onNextStepPressed() {
    _sendOtp();
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
      backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildGuardianInformationCard(),
          const SizedBox(height: 24),
          // Optional: Add a "Already have an account?" button to go to login page
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Already have an account?"),
              TextButton(
                onPressed: () {
                  // Navigate to GuardianLoginPage
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const GuardianLoginPage(), // Assuming you have this import
                    ),
                  );
                },
                child: const Text("Login"),
              ),
            ],
          ),
        ],
      ),
    );
  }

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

  Widget _buildGuardianInformationCard() {
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
            "Guardian Information",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _codeSent
                ? "Enter the OTP sent to your phone." // Updated text for OTP phase
                : "Let's start by setting up your guardian profile",
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 24),
          _buildTextField(
            controller: _fullNameController,
            labelText: "Full Name",
            hintText: "Enter your full name",
            enabled: !_codeSent, // Disable name input once OTP is sent
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _phoneNumberController,
            labelText: "Phone Number",
            hintText:
                "e.g., +639123456789 (include country code)", // Hint for E.164 format
            keyboardType: TextInputType.phone,
            enabled: !_codeSent, // Disable phone input once OTP is sent
          ),
          const SizedBox(height: 32),
          if (_codeSent) ...[
            // Show OTP input field if code has been sent
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
                onPressed: _isLoading ? null : _verifyOtp, // Verify OTP
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
            TextButton(
              onPressed: _isLoading ? null : _sendOtp, // Allow resend
              child: const Text('Resend OTP'),
            ),
          ] else
            // Show "Next Step" button initially
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : _onNextStepPressed, // Trigger _sendOtp
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
                        "Next Step",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    TextInputType keyboardType = TextInputType.text,
    bool enabled = true, // Added enabled parameter for consistency
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      enabled: enabled, // Apply enabled state
      decoration: InputDecoration(
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
