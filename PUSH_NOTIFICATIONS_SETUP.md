# Push Notifications Setup Guide

## Overview
The Smart Resilience app now supports **push notifications** that work even when the app is closed. Alerts (panic, entry, exit) are automatically sent to guardians' devices via Firebase Cloud Messaging (FCM).

## How It Works

### 1. **App Side (Flutter)**
- **MessagingService** (`lib/services/messaging_service.dart`):
  - Initializes Firebase Cloud Messaging in `main.dart`
  - Handles foreground notifications (when app is open)
  - Handles background notifications (when app is closed via `@pragma('vm:entry-point')` handler)
  - Manages FCM token lifecycle

- **AlertScreen** (`lib/screens/alert_screen.dart`):
  - Requests FCM token from the device
  - Stores the token in Firestore at `guardians/{userId}/fcmToken`
  - Subscribes to user-specific topic for targeted notifications

### 2. **Backend (Firebase Cloud Function)**
- **sendAlertNotification** (`functions/index.js`):
  - Triggered when any alert is written to Realtime Database (`alerts/{deviceId}/{timestamp}`)
  - Finds the guardian who owns the device
  - Retrieves their FCM token from Firestore
  - Sends FCM push notification with:
    - Title and body based on alert type (panic/entry/exit)
    - Device coordinates
    - Alert metadata
  - Handles invalid tokens by cleaning up Firestore

### 3. **Flow Diagram**
```
Device triggers alert
         ↓
Alert written to RTDB: alerts/{deviceId}/{timestamp}
         ↓
Cloud Function triggered: sendAlertNotification
         ↓
Query Firestore for guardian owning this device
         ↓
Get FCM token from guardians/{userId}/fcmToken
         ↓
Send FCM message via Firebase Cloud Messaging
         ↓
Device receives notification (even if app is closed)
         ↓
NotificationService shows pop-up with user's preferences
```

## Setup Requirements

### 1. **Android Configuration**
The app already has the necessary Android permissions in `android/app/src/main/AndroidManifest.xml`:
- `android.permission.POST_NOTIFICATIONS` (for Android 13+)
- `android.permission.VIBRATE`

### 2. **iOS Configuration**
For iOS, you need:
1. Enable Push Notifications in Xcode
2. Add APNs certificates to Firebase Console
3. Update `ios/Podfile` to include Firebase Messaging

### 3. **Firebase Cloud Functions**
The Cloud Function is already deployed. To redeploy after changes:
```bash
cd functions
firebase deploy --only functions:sendAlertNotification
```

### 4. **Firestore Security Rules**
Ensure guardians can read/write their own `fcmToken`:
```javascript
match /guardians/{userId} {
  allow read, write: if request.auth.uid == userId;
}
```

## Notification Settings

Users can control how they receive notifications in the **Settings** screen:
- **Sound Alert**: Play notification sound
- **Vibrate Only**: Silent vibration only
- **Both Sound & Vibration**: Maximum alert feedback

These settings are saved in Firestore at:
`guardians/{userId}/settings/notifications`

The NotificationService reads these preferences and applies them to both:
- Local notifications (when app is in foreground)
- Push notifications (when app is in background)

## Testing

### Test from Emulator/Device:
1. Open the app and log in
2. Go to Settings screen
3. Click "Preview Alert Feedback" to test local notifications
4. Close the app completely
5. Trigger an alert from your device (panic button or geofence)
6. You should see a push notification on your device

### Test with Firebase Console:
1. Go to Firebase Console → Cloud Messaging
2. Send a test message to a user by their FCM token
3. Message should appear on device even if app is closed

## Troubleshooting

### Notifications not showing on Android
- Check Android version (13+ requires POST_NOTIFICATIONS permission)
- Verify FCM token was stored: Check Firestore at `guardians/{userId}/fcmToken`
- Check Cloud Function logs in Firebase Console

### Notifications not showing on iOS
- Verify APNs certificates are configured in Firebase Console
- Check iOS notification settings: Settings → [App Name] → Notifications
- Enable "Allow Notifications"

### Invalid FCM Token
- The Cloud Function automatically removes invalid tokens
- Reopen the app to request a new token
- Token is automatically stored when alert_screen loads

## Files Modified/Created

### New Files:
- `lib/services/messaging_service.dart` - FCM initialization and handling
- `PUSH_NOTIFICATIONS_SETUP.md` - This documentation

### Modified Files:
- `lib/main.dart` - Added MessagingService initialization
- `lib/screens/alert_screen.dart` - Added FCM token request/storage
- `functions/index.js` - Added Cloud Function for sending notifications

## Security Considerations

1. **FCM Tokens** are stored per guardian in Firestore
2. **Cloud Function** validates that only the device owner receives notifications
3. **Notification data** includes minimal sensitive information (coordinates only)
4. **Tokens are automatically refreshed** by Firebase SDK

## Future Enhancements

Possible improvements:
- [ ] Custom notification sounds per alert type
- [ ] Notification grouping for multiple alerts
- [ ] Device-specific notification settings
- [ ] Rich notifications with location map preview
- [ ] In-app notification badge counter
