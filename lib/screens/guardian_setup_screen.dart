import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_resilience_app/screens/success_animation_screen.dart';
import 'package:smart_resilience_app/screens/guardian_login_page.dart';
import 'package:smart_resilience_app/services/custom_otp_service.dart';

class GuardianSetupScreen extends StatefulWidget {
  const GuardianSetupScreen({super.key});

  @override
  State<GuardianSetupScreen> createState() => _GuardianSetupScreenState();
}

class _GuardianSetupScreenState extends State<GuardianSetupScreen> {
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneNumberController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _deviceIdController = TextEditingController();
  final TextEditingController _childNameController = TextEditingController();
  final TextEditingController _childAgeController = TextEditingController();

  bool _codeSent = false;
  bool _isLoading = false;
  int _otpCountdown = 0; // Countdown timer for OTP resend button

  // Role assignment
  String _selectedRole = 'Parent'; // Default role
  final List<String> _guardianRoles = [
    'Parent',
    'Guardian',
    'Sibling',
    'Grandparent',
    'Aunt/Uncle',
    'Caregiver',
    'Other',
  ];

  // Track the current user if already authenticated (i.e., profile completion mode)
  User? _currentUser = FirebaseAuth.instance.currentUser;
  bool get _isProfileCompletionMode => _currentUser != null;

  @override
  void initState() {
    super.initState();
    // If a user is already signed in (came from login page after phone auth),
    // we use their existing phone number and skip the OTP process.
    if (_isProfileCompletionMode) {
      _phoneNumberController.text = _currentUser!.phoneNumber ?? 'N/A';

      // FIX: Delay the SnackBar call until after the first frame is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSnackBar('Welcome back! Please complete your profile details.');
      });
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneNumberController.dispose();
    _otpController.dispose();
    _deviceIdController.dispose();
    _childNameController.dispose();
    _childAgeController.dispose();
    super.dispose();
  }

  // --- Utility Functions ---

  // Normalizes phone number to E.164 format (+639xxxxxxxxx) for the Philippines.
  String _normalizePhoneNumber(String input) {
    String phone = input.trim();
    if (phone.isEmpty) return phone;
    phone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (phone.startsWith('+')) return phone;
    if (phone.startsWith('0')) phone = phone.substring(1);
    if (phone.length == 10 && phone.startsWith('9')) {
      return '+63$phone';
    }
    return '+63$phone';
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // --- Authentication/Setup Logic ---

  Future<void> _sendOtp() async {
    if (_fullNameController.text.isEmpty) {
      _showSnackBar('Please enter your full name.');
      return;
    }
    if (_phoneNumberController.text.isEmpty) {
      _showSnackBar('Please enter your phone number.');
      return;
    }
    if (_deviceIdController.text.isEmpty) {
      _showSnackBar('Please enter the device ID.');
      return;
    }

    String phoneNumber = _normalizePhoneNumber(_phoneNumberController.text);
    _phoneNumberController.text =
        phoneNumber; // Update display to normalized format

    setState(() {
      _isLoading = true;
    });

    try {
      // Send OTP via custom iProgsms service
      bool otpSent = await CustomOtpService.sendOtp(
        phoneNumber: phoneNumber,
        fullName: _fullNameController.text.trim(),
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
        print('[Guardian Setup] OTP verified successfully');

        // Use Firebase Auth UID as the guardian document ID
        // First, sign in with OTP to get the actual Firebase Auth user
        String normalizedPhone = _normalizePhoneNumber(
          _phoneNumberController.text,
        );

        // Create a custom auth user with phone number as identifier
        // For now, we'll use a phone-based lookup, but after sign-in we'll use Auth UID
        String userId =
            'user_${normalizedPhone.replaceAll(RegExp(r"[^0-9]"), "")}';

        print('[Guardian Setup] Generated userId: $userId');

        // Clear the OTP after successful verification
        CustomOtpService.clearOtp(_phoneNumberController.text);

        // Finalize the profile with guardian data (pass userId directly)
        await _finalizeProfile(userId);
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

  // This function is the single exit point, saving the profile and navigating.
  Future<void> _finalizeProfile(String userId) async {
    if (userId.isEmpty) {
      _showSnackBar('Invalid user ID for profile finalization.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      print(
        '[Guardian Setup] Starting profile finalization for userId: $userId',
      );

      // 0. Sign in anonymously to get proper Firebase authentication
      print('[Guardian Setup] Signing in anonymously for Firestore access...');
      UserCredential userCredential = await FirebaseAuth.instance
          .signInAnonymously();
      String authUid = userCredential.user?.uid ?? userId;
      print(
        '[Guardian Setup] ✅ Anonymous sign-in successful with UID: $authUid',
      );

      // Use the actual Firebase Auth UID for the guardian document
      String finalUserId = authUid;
      print(
        '[Guardian Setup] Using Auth UID as guardian document ID: $finalUserId',
      );

      // 1. Save guardian profile with role and SMS preference
      String normalizedPhone = _normalizePhoneNumber(
        _phoneNumberController.text,
      );

      print('[Guardian Setup] Saving guardian profile to Firestore...');
      await FirebaseFirestore.instance
          .collection('guardians')
          .doc(finalUserId)
          .set({
            'fullName': _fullNameController.text.trim(),
            'phoneNumber': normalizedPhone, // Use normalized phone number
            'role': _selectedRole, // Save the selected role
            'smsEnabled': true, // Enable SMS by default
            'createdAt': FieldValue.serverTimestamp(),
            'lastLogin': FieldValue.serverTimestamp(),
            'hasCompletedSetup': true, // Mark setup as complete
          }, SetOptions(merge: true));

      print('[Guardian Setup] Guardian profile saved successfully');

      // 2. Create placeholder documents for subcollections
      print('[Guardian Setup] Creating subcollections...');
      await FirebaseFirestore.instance
          .collection('guardians')
          .doc(finalUserId)
          .collection('geofences')
          .doc('initial_geofence_placeholder')
          .set({'isPlaceholder': true}, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('guardians')
          .doc(finalUserId)
          .collection('settings')
          .doc('initial_settings_placeholder')
          .set({'isPlaceholder': true}, SetOptions(merge: true));

      // ----------------------------------------------------------
      // 3. PAIR THE DEVICE TO THIS GUARDIAN WITH CHILD INFO 🔥🔥🔥
      // ----------------------------------------------------------
      final deviceId = _deviceIdController.text.trim();
      final childName = _childNameController.text.trim();
      final childAge = int.tryParse(_childAgeController.text.trim()) ?? 0;

      await FirebaseFirestore.instance
          .collection('guardians')
          .doc(finalUserId)
          .collection('paired_device')
          .doc('device_info')
          .set({
            'deviceId': deviceId,
            'childName': childName,
            'childAge': childAge,
            'pairedAt': FieldValue.serverTimestamp(),
          });

      // Save guardian document ID and phone number to local storage for future lookups
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('guardianDocId', finalUserId);
      await prefs.setString('guardianPhoneNumber', normalizedPhone);
      print(
        '[Guardian Setup] ✅ Saved guardian ID to local storage: $finalUserId',
      );

      print('[Guardian Setup] ✅ Profile setup complete!');
      _showSnackBar('Profile setup complete! You are ready to go.');
      if (mounted) {
        // Navigate to the SuccessAnimationScreen after successful save.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const SuccessAnimationScreen(),
          ),
        );
      }
    } catch (e) {
      print('[Guardian Setup] ❌ Error during profile save: $e');
      print('[Guardian Setup] Error type: ${e.runtimeType}');

      // Check if it's an App Check error
      if (e.toString().contains('AppCheckProvider')) {
        print('[Guardian Setup] App Check error detected');
        _showSnackBar('App Check not configured. Please contact support.');
      } else {
        debugPrint('Error during profile save: $e');
        _showSnackBar('An unexpected error occurred during profile save: $e');
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Handles signing in with credential (for new users) and then finalizes profile.
  // Not used in profile completion mode.
  // The primary button handler.
  void _onNextStepPressed() {
    if (_fullNameController.text.isEmpty) {
      _showSnackBar('Please enter your full name before continuing.');
      return;
    }
    if (_deviceIdController.text.isEmpty) {
      _showSnackBar('Please enter the device ID before continuing.');
      return;
    }
    if (_childNameController.text.isEmpty) {
      _showSnackBar('Please enter the child\'s name before continuing.');
      return;
    }
    if (_childAgeController.text.isEmpty) {
      _showSnackBar('Please enter the child\'s age before continuing.');
      return;
    }
    if (_selectedRole.isEmpty) {
      _showSnackBar('Please select a role before continuing.');
      return;
    }

    if (_isProfileCompletionMode) {
      // Case 2: User is already signed in and just needs to save the name.
      // Generate userId from phone number
      String normalizedPhone = _normalizePhoneNumber(
        _phoneNumberController.text,
      );
      String userId =
          'user_${normalizedPhone.replaceAll(RegExp(r"[^0-9]"), "")}';
      _finalizeProfile(userId);
    } else {
      // Case 1: New user signup - proceed to OTP sending.
      _sendOtp();
    }
  }

  // --- UI Building ---

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
          // Link to the Login page, hidden in profile completion mode
          if (!_isProfileCompletionMode)
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
                        builder: (context) => const GuardianLoginPage(),
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
          Text(
            _isProfileCompletionMode
                ? "Complete Your Profile"
                : "Guardian Information",
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _isProfileCompletionMode
                ? "Just one step left: enter your full name and save."
                : (_codeSent
                      ? "Enter the OTP sent to your phone."
                      : "Let's start by setting up your guardian profile"),
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 24),

          // Full Name Input
          _buildTextField(
            controller: _fullNameController,
            labelText: "Full Name",
            hintText: "Enter your full name",
            // Always enabled for setup or completion
          ),
          const SizedBox(height: 16),

          // Phone Number Input (Disabled if already authenticated or code sent)
          _buildTextField(
            controller: _phoneNumberController,
            labelText: "Phone Number",
            hintText: "e.g., +639123456789",
            keyboardType: TextInputType.phone,
            enabled: !_isProfileCompletionMode && !_codeSent,
          ),
          const SizedBox(height: 16),

          // Device ID Input (Disabled if code sent)
          _buildTextField(
            controller: _deviceIdController,
            labelText: "Device ID",
            hintText: "e.g., child_01",
            enabled: !_codeSent,
          ),
          const SizedBox(height: 16),

          // Child Name Input
          _buildTextField(
            controller: _childNameController,
            labelText: "Child's Name",
            hintText: "Enter the child's name",
            enabled: !_codeSent,
          ),
          const SizedBox(height: 16),

          // Child Age Input
          _buildTextField(
            controller: _childAgeController,
            labelText: "Child's Age",
            hintText: "e.g., 12",
            keyboardType: TextInputType.number,
            enabled: !_codeSent,
          ),
          const SizedBox(height: 16),

          // Role Selection Dropdown
          _buildRoleDropdown(),
          const SizedBox(height: 32),

          if (_codeSent && !_isProfileCompletionMode) ...[
            // OTP Input (Only shown for new sign-ups after sending code)
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
                  backgroundColor: Colors.blue.shade500,
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
                        "Verify OTP & Create Profile",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            TextButton(
              onPressed: (_isLoading || _otpCountdown > 0) ? null : _sendOtp,
              child: Text(
                _otpCountdown > 0
                    ? 'Resend in ${(_otpCountdown ~/ 60)}:${(_otpCountdown % 60).toString().padLeft(2, '0')}'
                    : 'Resend OTP',
              ),
            ),
          ] else
            // Next Step / Complete Setup Button (for both initial send and final save)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _onNextStepPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isProfileCompletionMode
                      ? Colors
                            .green
                            .shade600 // Green for finishing
                      : Colors.green.shade500, // Green for starting
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 3,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        _isProfileCompletionMode
                            ? "Complete Setup"
                            : "Send OTP",
                        style: const TextStyle(
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
    bool enabled = true,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      enabled: enabled,
      maxLength: maxLength,
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

  Widget _buildRoleDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Guardian Role",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey[100],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButton<String>(
            value: _selectedRole,
            onChanged: (String? newValue) {
              setState(() {
                _selectedRole = newValue ?? 'Parent';
              });
            },
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: _guardianRoles.map<DropdownMenuItem<String>>((String value) {
              return DropdownMenuItem<String>(value: value, child: Text(value));
            }).toList(),
          ),
        ),
      ],
    );
  }
}
