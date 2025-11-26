import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart'; // For debugPrint
import 'package:permission_handler/permission_handler.dart';

// Top-level function for background notifications (required for Android when app is terminated)
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) async {
  debugPrint('Background notification tapped: ${response.payload}');
  // Implement any logic you need when a notification is tapped while the app is terminated.
  // For example, navigating to a specific screen or processing data.
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin
  _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  static Future<void> initializeNotifications() async {
    // Request notification permission for Android 13+
    // It's crucial to request this permission for notifications to show up.
    // Ensure you have android.permission.POST_NOTIFICATIONS in your AndroidManifest.xml
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher'); // Your app icon

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          // No iOS initialization settings as we only target Android
        );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        // Handle notification tap here when app is in foreground/background (but not terminated)
        debugPrint('Notification tapped: ${response.payload}');
        // Example: You can navigate to a specific screen based on the payload
      },
      // This is crucial for handling taps when the app is terminated on Android.
      // It must be a top-level or static function.
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );
  }

  static Future<void> showAlarmNotification({
    required String title,
    required String body,
    bool playSound = true,
    bool vibrate = true,
    bool both = false, // Added for explicit 'both' control
  }) async {
    bool finalPlaySoundAndroid = false;
    bool finalEnableVibrationAndroid = false;

    if (both) {
      finalPlaySoundAndroid = true;
      finalEnableVibrationAndroid = true;
    } else if (playSound) {
      finalPlaySoundAndroid = true;
      finalEnableVibrationAndroid = false;
    } else if (vibrate) {
      finalPlaySoundAndroid = false;
      finalEnableVibrationAndroid = true;
    } else {
      // If none of the specific options are selected, default to no sound/vibration
      finalPlaySoundAndroid = false;
      finalEnableVibrationAndroid = false;
    }

    final AndroidNotificationDetails
    androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'alarm_channel', // ID for the notification channel
      'Alarm Notifications', // Name of the channel visible to the user
      channelDescription: 'Notifications for critical alerts.',
      importance: Importance.max, // Makes it a heads-up notification (pop-up)
      priority: Priority.high,
      ticker:
          'ticker', // Optional: text shown in status bar for older Android versions
      fullScreenIntent:
          true, // This makes it a full-screen or heads-up notification
      playSound: finalPlaySoundAndroid,
      enableVibration: finalEnableVibrationAndroid,
      // You can also add custom sound, vibration patterns here if needed
      // sound: RawResourceAndroidNotificationSound('your_custom_sound'),
      // vibrationPattern: Int64List.fromList([0, 1000, 500, 2000]),
    );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      // No iOS details as we only target Android
    );

    await _flutterLocalNotificationsPlugin.show(
      0, // Unique notification ID. Use different IDs for different notifications if you want them to stack.
      title,
      body,
      platformChannelSpecifics,
      payload: 'alert_preview', // Custom data that can be retrieved on tap
    );
  }
}
