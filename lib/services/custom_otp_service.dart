import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

class CustomOtpService {
  // iProgsms Configuration - Updated to match API v1
  static const String API_ENDPOINT =
      'https://www.iprogsms.com/api/v1/sms_messages';
  static const String API_TOKEN = '79f0238238e0cdc03971d886d9485fb33332396d';

  // Store OTP temporarily (In production, use Redis or Firestore)
  static final Map<String, OtpData> _otpStore = {};

  /// Generate a 6-digit random OTP
  static String _generateOtp() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  /// Send OTP via iProgsms
  static Future<bool> sendOtp({
    required String phoneNumber,
    required String fullName,
  }) async {
    try {
      // Keep phone number in local format for iProgsms API
      String phone = phoneNumber.trim();
      if (phone.startsWith('+63')) {
        phone = '0' + phone.substring(3); // +639123456789 -> 09123456789
      }

      // Generate OTP
      String otp = _generateOtp();

      // Create message
      String message =
          'Your Smart Resilience OTP is: $otp. Valid for 5 minutes.';

      print('[CustomOtpService] Sending OTP to $phone via iProgsms');

      // Send via iProgsms using correct API v1 format
      final response = await http
          .post(
            Uri.parse(API_ENDPOINT),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'api_token': API_TOKEN,
              'phone_number': phone,
              'message': message,
            }),
          )
          .timeout(const Duration(seconds: 10));

      print('[CustomOtpService] Response status: ${response.statusCode}');
      print('[CustomOtpService] Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Normalize to E.164 for storage
        String normalizedPhone = _normalizePhoneNumber(phone);

        // Store OTP with timestamp (valid for 5 minutes)
        _otpStore[normalizedPhone] = OtpData(
          otp: otp,
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
          fullName: fullName,
        );

        print('[CustomOtpService] ✅ OTP sent successfully to $phone');
        print('[DEBUG] OTP: $otp'); // DEBUG: Print OTP to console for testing
        return true;
      } else {
        print(
          '[CustomOtpService] ❌ Failed to send OTP: ${response.statusCode}',
        );
        print('[CustomOtpService] Response: ${response.body}');
        return false;
      }
    } catch (e) {
      print('[CustomOtpService] Error sending OTP: $e');
      return false;
    }
  }

  /// Verify the OTP entered by user
  static bool verifyOtp({required String phoneNumber, required String otp}) {
    try {
      String normalizedPhone = _normalizePhoneNumber(phoneNumber);

      if (!_otpStore.containsKey(normalizedPhone)) {
        print('[CustomOtpService] No OTP found for $normalizedPhone');
        return false;
      }

      OtpData otpData = _otpStore[normalizedPhone]!;

      // Check if OTP is expired
      if (DateTime.now().isAfter(otpData.expiresAt)) {
        print('[CustomOtpService] OTP expired for $normalizedPhone');
        _otpStore.remove(normalizedPhone);
        return false;
      }

      // Check if OTP matches
      if (otpData.otp == otp) {
        print('[CustomOtpService] OTP verified for $normalizedPhone');
        return true;
      } else {
        print('[CustomOtpService] Invalid OTP for $normalizedPhone');
        return false;
      }
    } catch (e) {
      print('[CustomOtpService] Error verifying OTP: $e');
      return false;
    }
  }

  /// Get stored OTP data (for debugging or additional info)
  static OtpData? getOtpData(String phoneNumber) {
    String normalizedPhone = _normalizePhoneNumber(phoneNumber);
    return _otpStore[normalizedPhone];
  }

  /// Clear OTP after successful verification
  static void clearOtp(String phoneNumber) {
    String normalizedPhone = _normalizePhoneNumber(phoneNumber);
    _otpStore.remove(normalizedPhone);
    print('[CustomOtpService] OTP cleared for $normalizedPhone');
  }

  /// Normalize phone number to E.164 format
  static String _normalizePhoneNumber(String input) {
    String phone = input.trim();
    if (phone.isEmpty) return phone;

    // Remove all non-numeric characters except +
    phone = phone.replaceAll(RegExp(r'[^\d+]'), '');

    // If already has +, return as-is
    if (phone.startsWith('+')) return phone;

    // If starts with 0, remove it (Filipino format)
    if (phone.startsWith('0')) phone = phone.substring(1);

    // Add +63 for Philippines
    if (phone.length == 10 && phone.startsWith('9')) {
      return '+63$phone';
    }

    // Default: Add +63 prefix
    return '+63$phone';
  }
}

/// Model to store OTP data
class OtpData {
  final String otp;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String fullName;

  OtpData({
    required this.otp,
    required this.createdAt,
    required this.expiresAt,
    required this.fullName,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  int get secondsRemaining =>
      expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 999999);
}
