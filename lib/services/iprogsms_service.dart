import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class IProgSmsService {
  // iProgsms API endpoint - Updated to API v1
  static const String API_ENDPOINT =
      'https://www.iprogsms.com/api/v1/sms_messages';

  /// Send SMS via iProgsms API
  ///
  /// Parameters:
  /// - apiKey: Your iProgsms API Token
  /// - phoneNumber: Recipient phone number (09XXXXXXXXX or +639XXXXXXXXX)
  /// - message: SMS message body
  /// - senderId: Sender ID (your name or company) - not used in v1 API
  static Future<bool> sendSms({
    required String apiKey,
    required String phoneNumber,
    required String message,
    required String senderId,
  }) async {
    try {
      // Convert phone number to local format for iProgsms API v1
      String phone = phoneNumber.trim();
      print('DEBUG: Original phone from Firestore: "$phoneNumber"');

      if (phone.startsWith('+63')) {
        phone = '0' + phone.substring(3); // +639123456789 -> 09123456789
      } else if (!phone.startsWith('0')) {
        phone = '0' + phone; // fallback
      }

      print('DEBUG: Final phone format: $phone (length: ${phone.length})');

      final Map<String, dynamic> payload = {
        'api_token': apiKey,
        'phone_number': phone,
        'message': message,
      };

      print('📱 Sending SMS to $phone via iProgsms');
      print('   Message: $message');
      print('   Message length: ${message.length} characters');
      print('   Payload: ${jsonEncode(payload)}');

      final response = await http
          .post(
            Uri.parse(API_ENDPOINT),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      print('iProgsms Response: ${response.statusCode}');
      print('iProgsms Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        print(
          'Parsed response: status=${responseData['status']}, message=${responseData['message']}',
        );

        // iProgsms v1 returns success when status is 200 or message_id exists
        if (responseData['status'] == 200 ||
            responseData['status'] == '200' ||
            responseData['message_id'] != null ||
            responseData['success'] == true ||
            responseData['status'] == 'success' ||
            responseData['status'] == '1' ||
            responseData['message']?.toString().toLowerCase().contains(
                  'success',
                ) ==
                true) {
          print('✅ SMS sent successfully to $phone');
          print('   Message ID: ${responseData['message_id']}');
          return true;
        } else {
          print('❌ SMS API returned error: ${responseData['message']}');
          return false;
        }
      } else {
        print('❌ SMS API error: HTTP ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Exception sending SMS: $e');
      return false;
    }
  }

  /// Send SMS alert for a new alert (called from home_screen)
  ///
  /// Gets guardian's phone number and SMS preference from Firestore
  /// Also sends to all emergency contacts
  /// ONLY SENDS SMS FOR PANIC ALERTS - Entry/Exit alerts are skipped
  static Future<void> sendAlertSms({
    required String apiKey,
    required String senderId,
    required String alertType,
    required double latitude,
    required double longitude,
    required DateTime alertTime,
  }) async {
    try {
      // CRITICAL: Only send SMS for panic/SOS alerts - reject all other alert types
      if (alertType.toLowerCase() != 'panic' &&
          alertType.toLowerCase() != 'sos') {
        print(
          '⏭️ Skipping SMS for ${alertType.toLowerCase()} alert - only panic alerts send SMS',
        );
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user logged in, skipping SMS');
        return;
      }

      // Get guardian data from Firestore
      final guardianDoc = await FirebaseFirestore.instance
          .collection('guardians')
          .doc(user.uid)
          .get();

      if (!guardianDoc.exists) {
        print('Guardian document not found');
        return;
      }

      final guardianData = guardianDoc.data() as Map<String, dynamic>;
      final smsEnabled =
          guardianData['smsEnabled'] as bool? ??
          true; // DEFAULT TO TRUE FOR PANIC ALERTS
      final phoneNumber = guardianData['phoneNumber'] as String?;
      final childName = guardianData['childName'] as String? ?? 'Your child';

      print('📱 SMS Settings: enabled=$smsEnabled, phoneNumber=$phoneNumber');

      // For panic/SOS alerts, ALWAYS send SMS regardless of setting
      // For other alerts, respect the smsEnabled setting
      if (!smsEnabled &&
          alertType.toLowerCase() != 'panic' &&
          alertType.toLowerCase() != 'sos') {
        print('SMS disabled for non-panic alerts');
        return;
      }

      // Check if phone number exists for panic alerts
      if ((alertType.toLowerCase() == 'panic' ||
              alertType.toLowerCase() == 'sos') &&
          (phoneNumber == null || phoneNumber.isEmpty)) {
        print('❌ No phone number for panic alert - cannot send SMS');
        return;
      }

      // Build SMS message based on alert type (using 12-hour format)
      final hour12 = alertTime.hour % 12 == 0 ? 12 : alertTime.hour % 12;
      final amPm = alertTime.hour >= 12 ? 'PM' : 'AM';
      final timeFormatted =
          '$hour12:${alertTime.minute.toString().padLeft(2, '0')} $amPm';

      String smsBody = '';
      switch (alertType.toLowerCase()) {
        case 'panic':
        case 'sos':
          smsBody =
              'PANIC ALERT! $childName triggered SOS at $timeFormatted.\nLocation: $latitude, $longitude';
          break;
        case 'entry':
          smsBody =
              'ENTRY: $childName entered a safe zone at $timeFormatted.\nLocation: $latitude, $longitude';
          break;
        case 'exit':
          smsBody =
              'EXIT: $childName left a safe zone at $timeFormatted.\nLocation: $latitude, $longitude';
          break;
        default:
          smsBody = 'Alert: $alertType for $childName at $timeFormatted';
      }

      // NEW: Send to primary guardian phone if available
      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        print('📱 Sending primary guardian SMS to: $phoneNumber');
        await sendSms(
          apiKey: apiKey,
          phoneNumber: phoneNumber,
          message: smsBody,
          senderId: senderId,
        );
      } else {
        print('⚠️ No guardian phone number available for SMS');
      }

      // NEW: Get and send to all emergency contacts
      try {
        final emergencyContactsSnapshot = await FirebaseFirestore.instance
            .collection('guardians')
            .doc(user.uid)
            .collection('emergency_contacts')
            .get();

        print(
          '📱 Found ${emergencyContactsSnapshot.docs.length} emergency contacts',
        );

        for (final contactDoc in emergencyContactsSnapshot.docs) {
          final contactPhone = contactDoc.data()['phone'] as String? ?? '';
          if (contactPhone.isNotEmpty) {
            // Add emergency contact name prefix to message for clarity
            final contactName =
                contactDoc.data()['name'] as String? ?? 'Contact';
            final personalizedMessage = '[$contactName]\n$smsBody';

            print(
              '📱 Sending emergency contact SMS to: $contactPhone ($contactName)',
            );
            await sendSms(
              apiKey: apiKey,
              phoneNumber: contactPhone,
              message: personalizedMessage,
              senderId: senderId,
            );
          }
        }
      } catch (e) {
        print('❌ Error sending SMS to emergency contacts: $e');
      }
    } catch (e) {
      print('❌ Error in sendAlertSms: $e');
    }
  }
}
