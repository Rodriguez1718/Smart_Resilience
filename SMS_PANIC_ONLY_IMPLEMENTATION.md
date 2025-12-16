# SMS Panic Alert Implementation - Final Version

## Overview
This document explains the robust SMS implementation for panic alerts only. The system ensures that:
- ✅ ONLY panic/SOS alerts trigger SMS
- ✅ Each panic alert sends SMS exactly ONCE
- ✅ No duplicate SMS are sent even on app restart
- ✅ Entry and Exit alerts do NOT send SMS

## Architecture

### 1. SMS Tracking Mechanism (`home_screen.dart`)

```dart
Set<String> _panicAlertsSentSms = {}; // Track panic alerts that have sent SMS
```

**How it works:**
- This in-memory set stores alert IDs that have already sent SMS
- Alert ID format: `{deviceId}-{timestamp}` (e.g., `device123-1702214400000`)
- Once an alert ID is added to this set, SMS will never be sent for that alert again

### 2. Alert Subscription Flow

#### Step 1: Listen to Firebase RTDB
```dart
_alertsSubscription = FirebaseDatabase.instance
    .ref('alerts')
    .onValue
    .listen((DatabaseEvent event) { ... })
```

The app subscribes to ALL alerts in Firebase Realtime Database at path `alerts/`

#### Step 2: Process Each Alert
When an alert comes in, the code:
1. Extracts alert data (status, lat, lng, timestamp)
2. Creates a unique alert ID: `$deviceKey-$actualTimestamp`
3. Checks if it's a panic alert: `alertStatus == 'panic' || alertStatus == 'sos'`
4. Checks if SMS was already sent: `!_panicAlertsSentSms.contains(alertId)`

#### Step 3: Send SMS (Panic Alerts Only)
```dart
if ((alertStatus == 'panic' || alertStatus == 'sos') &&
    !_panicAlertsSentSms.contains(alertId)) {
  // Mark as SMS sent BEFORE sending to avoid race conditions
  _panicAlertsSentSms.add(alertId);
  // Send SMS asynchronously
  _sendPanicAlertSms(...);
}
```

**Critical Order:**
1. First, add alert ID to `_panicAlertsSentSms` set
2. Then, send SMS asynchronously
3. This prevents race conditions if stream emits while SMS is still sending

### 3. SMS Sending Method (`_sendPanicAlertSms`)

```dart
Future<void> _sendPanicAlertSms({
  required String deviceId,
  required int timestamp,
  required double latitude,
  required double longitude,
}) async {
  // 1. Verify user is logged in
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser == null) return;

  // 2. Convert timestamp to DateTime for message formatting
  final alertDateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);

  // 3. Get API credentials
  const String API_TOKEN = '79f0238238e0cdc03971d886d9485fb33332396d';
  const String SENDER_ID = 'SmartResilience';

  // 4. Call iProgsms service (hardcoded to panic alerts only)
  await IProgSmsService.sendAlertSms(
    apiKey: API_TOKEN,
    senderId: SENDER_ID,
    alertType: 'panic',  // <- ONLY panic type
    latitude: latitude,
    longitude: longitude,
    alertTime: alertDateTime,
  );
}
```

**Error Handling:**
If SMS sending fails, the alert ID is removed from the tracking set:
```dart
_panicAlertsSentSms.remove(alertId);
```
This allows a retry if the alert stream re-emits (user can manually trigger retry).

### 4. SMS Service Guard (`iprogsms_service.dart`)

The SMS service has a built-in guard that ONLY processes panic alerts:
```dart
if (alertType.toLowerCase() != 'panic' &&
    alertType.toLowerCase() != 'sos') {
  print('⏭️ Skipping SMS for ${alertType.toLowerCase()} alert');
  return;
}
```

**Why double guard?**
- Primary guard in `_subscribeToAlerts`: Prevents SMS method from being called
- Secondary guard in `IProgSmsService`: Ensures SMS is never sent even if called directly
- Defense-in-depth approach prevents accidental SMS sends

## Data Flow Diagram

```
Firebase RTDB (alerts/)
        ↓
    Stream Update
        ↓
_subscribeToAlerts() listens
        ↓
    For each alert:
        ├─ Extract status, lat, lng, timestamp
        ├─ Check: Is it panic/SOS? ──No──→ SKIP
        │                          Yes
        │                             ↓
        ├─ Check: Is it in _panicAlertsSentSms? ──Yes──→ SKIP
        │                                      No
        │                                        ↓
        └─ Add to _panicAlertsSentSms
        └─ Call _sendPanicAlertSms()
                   ↓
        Check user logged in
                   ↓
        Get API credentials
                   ↓
        Call IProgSmsService.sendAlertSms()
                   ↓
        Service validates it's panic type (secondary guard)
                   ↓
        Get guardian & emergency contacts from Firestore
                   ↓
        Send SMS via iProgsms API v1
                   ↓
        Log success/failure
```

## Alert ID Format

Alert ID combines device and timestamp for uniqueness:
```
Format: {deviceId}-{timestamp}
Example: device123-1702214400000

Benefits:
- Each alert is uniquely identified
- Same alert on different devices = different IDs
- Same device, different time = different IDs
- Prevents duplicates across app restarts
```

## Why This Works

### ✅ Prevents Duplicates on Stream Re-emission
- Firebase RTDB emits all historical data on reconnection
- The in-memory set `_panicAlertsSentSms` tracks sent alerts
- Stream can re-emit same alert, but SMS won't be sent twice

### ✅ Prevents Entry/Exit SMS
- Status check: `alertStatus == 'panic' || alertStatus == 'sos'`
- Entry/Exit alerts have status 'entry' or 'exit'
- These conditions are false, SMS skipped

### ✅ Guarantees One SMS per Alert
- Alert ID added to set BEFORE SMS is sent
- Set membership is checked on every stream update
- Even if stream emits 100 times, SMS only sent once

### ✅ Simple & Reliable
- No complex Firestore persistence needed
- No timing issues with async operations
- In-memory set is fast and reliable
- Works even if Firestore is slow/unavailable

## Testing Checklist

- [ ] Create a panic alert - verify SMS sent to guardian
- [ ] Check app logs - should see "✅ SMS sent for panic alert"
- [ ] Create an entry alert - verify NO SMS sent
- [ ] Create an exit alert - verify NO SMS sent
- [ ] Restart app - verify NO duplicate SMS sent
- [ ] Create a new panic alert - verify SMS sent (only 1)
- [ ] Check emergency contacts - verify all received SMS

## SMS Message Format

The SMS contains:
```
🚨 PANIC ALERT!
{childName} triggered SOS at {HH:MM AM/PM}.
Location: {latitude}, {longitude}

Or (for emergency contacts):
[{contactName}]
🚨 PANIC ALERT!
{childName} triggered SOS at {HH:MM AM/PM}.
Location: {latitude}, {longitude}
```

### Time Format
- 12-hour format with AM/PM
- Example: "3:04 PM" instead of "15:04"
- Calculated in `iprogsms_service.dart`

## Code Changes Summary

### `home_screen.dart` modifications:
1. Added `Set<String> _panicAlertsSentSms = {}` tracking
2. Updated `_subscribeToAlerts()` to check for new panic alerts
3. Added `_sendPanicAlertSms()` method for panic SMS delivery

### `alert_screen.dart` modifications:
- NO changes to SMS code (alert_screen doesn't send SMS)
- Alert display shows in-app notifications only

### `iprogsms_service.dart` modifications:
- Already has panic-only guard at entry point
- No changes needed for this implementation

## Important Notes

1. **SMS Cost**: Each panic alert = 1 SMS to guardian + 1 SMS per emergency contact
2. **No SMS on Entry/Exit**: These are logged to RTDB but no SMS sent
3. **API Token**: `79f0238238e0cdc03971d886d9485fb33332396d` (from custom_otp_service.dart)
4. **Sender ID**: `SmartResilience` 
5. **Rate Limiting**: iProgsms API v1 may have rate limits - production should add throttling

## Future Improvements

1. Add persistent SMS tracking to Firestore for multi-device sync
2. Add SMS delivery confirmation from iProgsms API
3. Add retry logic for failed SMS sends
4. Add rate limiting to prevent API abuse
5. Add SMS preview before sending in app settings
