# Quick Reference - SMS Panic Alerts

## What Changed

### ✅ Now Working:
- Panic alerts (status='panic' or status='sos') trigger SMS automatically
- SMS sent to guardian's phone number from Firestore
- SMS also sent to all emergency contacts in `emergency_contacts` subcollection
- Each panic alert sends SMS exactly ONCE (no duplicates)
- SMS uses 12-hour time format (e.g., "3:04 PM")

### ❌ Still Disabled:
- Entry alerts (status='entry') - NO SMS
- Exit alerts (status='exit') - NO SMS
- These are logged to alerts but SMS skipped

## How to Test

### Test 1: Single Panic Alert
1. Trigger a panic button on the device
2. Check logs: `✅ SMS sent for panic alert`
3. Check phone: Verify SMS received
4. Open app again: Verify NO duplicate SMS

### Test 2: Entry Alert
1. Configure a geofence
2. Device enters geofence
3. Check logs: No SMS sending logs
4. Verify NO SMS received (correct behavior)

### Test 3: Multiple Panic Alerts
1. Trigger panic alert 1 - SMS sent ✅
2. Trigger panic alert 2 - SMS sent ✅
3. Restart app
4. Verify NO duplicate SMS sent (total: 2, not 4)

## Code Locations

### Main SMS Logic
- **File**: `lib/screens/home_screen.dart`
- **Method**: `_subscribeToAlerts()` (lines ~296-375)
- **Tracking**: `Set<String> _panicAlertsSentSms` (line ~43)

### SMS Sender
- **File**: `lib/screens/home_screen.dart`
- **Method**: `_sendPanicAlertSms()` (lines ~375-418)

### SMS Service (Guard)
- **File**: `lib/services/iprogsms_service.dart`
- **Method**: `sendAlertSms()` (lines ~87-220)
- **Guard**: Lines 90-96 prevent non-panic alerts

## SMS Recipients

### Primary: Guardian
- Phone: From `guardians.phoneNumber` in Firestore
- Message: Contains alert details + location

### Secondary: Emergency Contacts
- Query: `guardians/{uid}/emergency_contacts` collection
- Each contact: Gets personalized message with their name

## Logs to Watch

**Success**: 
```
📱 Processing SMS for PANIC alert...
✅ SMS sent for panic alert: device123 at 2024-12-10 15:04:32.000
```

**Skipped**:
```
⏭️ Skipping SMS for entry alert - only panic alerts send SMS
```

**Error**:
```
❌ Error sending panic alert SMS: [error details]
```

## Alert ID Format

Each alert tracked as: `{deviceId}-{timestamp}`

Example: `ABC123XYZ-1702214400000`

Once SMS sent for this ID, SMS never sent again (even on app restart).

## Critical Safety Guards

**Guard 1** (in home_screen.dart):
```dart
if ((alertStatus == 'panic' || alertStatus == 'sos') &&
    !_panicAlertsSentSms.contains(alertId)) {
```

**Guard 2** (in iprogsms_service.dart):
```dart
if (alertType.toLowerCase() != 'panic' &&
    alertType.toLowerCase() != 'sos') {
  return; // Skip SMS
}
```

Both guards must pass for SMS to send.

## Configuration

### API Credentials
- **API Token**: `79f0238238e0cdc03971d886d9485fb33332396d`
- **Sender ID**: `SmartResilience`
- **Endpoint**: `https://www.iprogsms.com/api/v1/sms_messages`

### Required Firestore Fields
```
guardians/{uid}/
  ├─ phoneNumber (string) - Guardian's phone
  ├─ childName (string) - Used in SMS message
  └─ emergency_contacts/ (collection)
     └─ {contactId}/
        ├─ name (string)
        └─ phone (string)
```

## Troubleshooting

### SMS Not Sending
1. Check logs for error messages
2. Verify `guardians.phoneNumber` is set in Firestore
3. Verify alert status is exactly 'panic' or 'sos'
4. Check internet connectivity
5. Verify iProgsms API token is valid

### Duplicate SMS on App Restart
This should NOT happen - if it does:
1. Check `_panicAlertsSentSms` is being populated
2. Verify alert IDs are consistent (same deviceId-timestamp)
3. Check if stream is re-emitting old alerts

### Wrong SMS Recipients
1. Check `guardians.phoneNumber` in Firestore
2. Check `emergency_contacts` collection entries
3. Verify phone format (should work with 09XX or +639XX)

## SMS Cost Estimate

Per panic alert:
- Guardian SMS: 1 credit
- Per emergency contact: 1 credit each
- Example: 1 guardian + 2 emergency contacts = 3 credits per alert

## Disable SMS (if needed)

To temporarily disable SMS for testing:
1. In `_subscribeToAlerts()`, comment out `_sendPanicAlertSms()` call
2. Rebuild app
3. Test without SMS charges

To permanently disable:
1. Remove the call to `_sendPanicAlertSms()`
2. Remove the `_panicAlertsSentSms` set
3. Remove the `_sendPanicAlertSms()` method
