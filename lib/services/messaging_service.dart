import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:smart_resilience_app/services/notification_service.dart';

// Top-level function for handling background messages (when app is closed or in background)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Handling a background message: ${message.messageId}');
  debugPrint('Message title: ${message.notification?.title}');
  debugPrint('Message body: ${message.notification?.body}');

  // Show local notification even when app is in background
  await NotificationService.showAlarmNotification(
    title: message.notification?.title ?? 'Alert',
    body: message.notification?.body ?? '',
    playSound: true,
    vibrate: true,
    both: false,
  );
}

class MessagingService {
  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;

  /// Initialize Firebase Cloud Messaging
  /// This sets up handlers for foreground and background messages
  static Future<void> initializeMessaging() async {
    try {
      // Request permission to receive notifications (iOS 10.0+)
      await _firebaseMessaging.requestPermission(
        alert: true,
        announcement: true,
        badge: true,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      // Set the background message handler
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      // Handle foreground messages (when app is open)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Got a message whilst in the foreground!');
        debugPrint('Message title: ${message.notification?.title}');
        debugPrint('Message body: ${message.notification?.body}');

        // Show notification when app is in foreground
        NotificationService.showAlarmNotification(
          title: message.notification?.title ?? 'Alert',
          body: message.notification?.body ?? '',
          playSound: true,
          vibrate: true,
          both: false,
        );
      });

      // Handle notification taps
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('A new onMessageOpenedApp event was published!');
        debugPrint('Message title: ${message.notification?.title}');
        debugPrint('Message body: ${message.notification?.body}');
        // You can navigate to a specific screen based on the message data
      });

      debugPrint('Firebase Messaging initialized successfully');
    } catch (e) {
      debugPrint('Error initializing Firebase Messaging: $e');
    }
  }

  /// Get the FCM token for this device
  /// Store this token in Firestore so Firebase Cloud Functions can send messages to this user
  static Future<String?> getToken() async {
    try {
      String? token = await _firebaseMessaging.getToken();
      debugPrint('FCM Token: $token');
      return token;
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      return null;
    }
  }

  /// Subscribe to a topic so this device receives messages sent to that topic
  static Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      debugPrint('Subscribed to topic: $topic');
    } catch (e) {
      debugPrint('Error subscribing to topic: $e');
    }
  }

  /// Unsubscribe from a topic
  static Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      debugPrint('Unsubscribed from topic: $topic');
    } catch (e) {
      debugPrint('Error unsubscribing from topic: $e');
    }
  }
}
