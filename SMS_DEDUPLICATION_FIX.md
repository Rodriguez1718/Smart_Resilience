# SMS Deduplication Fix - CRITICAL FIX APPLIED

## Problem Statement
Panic alerts were being sent as SMS multiple times, even after app restart, wasting SMS credits.

## Root Cause Analysis
The issue was a **race condition** in the alert subscription listener where:

1. Multiple database change events could fire for the same alert
2. Each event would trigger a new debounce timer independently
3. If timers weren't properly tracked, multiple SMS could be sent for the same alert
4. The `_lastProcessedAlertId` variable was declared but never used in the critical check

## Solution Implemented

### Level 1: In-Memory Deduplication
- **Set**: `_processedPanicAlertIds` tracks all alerts that have had SMS sent
- **Check**: Before starting debounce, verify alert NOT in set with `!_processedPanicAlertIds.contains(latestPanicAlertId)`

### Level 2: Processing State Guard (NEW FIX)
```dart
// CRITICAL: If we're already processing this exact alert, skip it
if (_lastProcessedAlertId == latestPanicAlertId) {
  print('⚠️ Already processing $latestPanicAlertId, skipping duplicate');
  return;
}

// Mark this as the alert we're now processing
_lastProcessedAlertId = latestPanicAlertId;
```

This prevents multiple concurrent timers from starting for the same alert.

### Level 3: In-Debounce Verification
```dart
// Double-check that it's still not processed (in case another event fired)
if (_processedPanicAlertIds.contains(latestPanicAlertId)) {
  print('✅ Alert $latestPanicAlertId already in memory, skipping');
  _lastProcessedAlertId = null;
  return;
}
```

### Level 4: Firestore Source-of-Truth Check
```dart
// Check Firestore to be absolutely sure this alert wasn't sent in a previous app session
final doc = await FirebaseFirestore.instance
    .collection('guardians')
    .doc(userId)
    .collection('settings')
    .doc('sms_tracking')
    .get();

if (doc.exists && doc.data() != null) {
  final data = doc.data() as Map<String, dynamic>;
  final savedAlerts = List<String>.from(
    data['processedPanicAlertIds'] as List? ?? [],
  );

  if (savedAlerts.contains(latestPanicAlertId)) {
    print('✅ Alert $latestPanicAlertId already in Firestore, skipping SMS');
    _processedPanicAlertIds = savedAlerts.toSet();
    _lastProcessedAlertId = null;
    return;
  }
}
```

This ensures alerts from previous app sessions (after crash/restart) are not re-sent.

### Level 5: Safe-Fail Behavior
```dart
catch (e) {
  print('⚠️ Error checking Firestore: $e');
  // If we can't verify in Firestore, DON'T send SMS to be safe
  _lastProcessedAlertId = null;
  return;
}
```

If we can't verify the alert status, we skip sending to avoid waste.

### Level 6: Atomic Save Before Send
```dart
// Mark this panic alert as processed BEFORE sending
_processedPanicAlertIds.add(latestPanicAlertId!);
_lastPanicAlertTimestamp = latestPanicTimestamp;

// Save to Firestore IMMEDIATELY and WAIT for it to complete
await _savePanicAlertTimestamp(userId, latestPanicTimestamp);

// Only send SMS AFTER Firestore has saved
await _sendPanicAlertSms(...);

// Clear the processing flag now that SMS is sent
_lastProcessedAlertId = null;
```

This ensures Firestore persistence happens BEFORE SMS is sent.

## Key Changes Made

### File: `lib/screens/home_screen.dart`

1. **Added Guard at Line ~484**:
   - Check `_lastProcessedAlertId == latestPanicAlertId` before creating debounce timer
   - Prevents multiple timers from firing for the same alert

2. **Set Processing Flag at Line ~495**:
   - `_lastProcessedAlertId = latestPanicAlertId;` before creating timer

3. **Clear Flag on Double-Check at Line ~510**:
   - `_lastProcessedAlertId = null;` when alert already in memory

4. **Clear Flag on Firestore Hit at Line ~534**:
   - `_lastProcessedAlertId = null;` when alert found in Firestore

5. **Clear Flag on Error at Line ~541**:
   - `_lastProcessedAlertId = null;` when Firestore check fails

6. **Clear Flag After SMS at Line ~572**:
   - `_lastProcessedAlertId = null;` after successful SMS send

7. **Clear Flag on Already-Processed at Line ~582**:
   - `_lastProcessedAlertId = null;` when alert already in local set

## Alert ID Format Standardization

Alert IDs are created using all three components:
```dart
latestPanicAlertId = '$deviceKey-$timestampKey-$actualTimestamp'
```

This ensures:
- **Uniqueness**: Three components guarantee unique identification
- **Consistency**: Same format everywhere (Firestore save & comparison)
- **Traceability**: Easy to trace in logs

Example: `child_01-1728086-1765350252920`

## Debounce Timer Settings

- **Duration**: 1 second (reduced from 2 seconds for faster response)
- **Purpose**: Catch rapid duplicate events from Firebase
- **Cancellation**: Previous timer is cancelled before starting new one

## Verification Logging

The code now prints comprehensive debug logs:

```
⚠️ Already processing child_01-1728086-1765350252920, skipping duplicate
🚨 Found NEW panic alert: child_01-1728086-1765350252920 at 1765350252920
📊 Current processed alerts count: 47
✅ Alert child_01-1728086-1765350252920 already in Firestore, skipping SMS
✅ Alert child_01-1728086-1765350252920 already in memory, skipping
🔔 Sending SMS for new panic alert: child_01-1728086-1765350252920
```

## Test Protocol

To verify the fix is working:

1. **Trigger a panic alert** - should see "Found NEW panic alert" log
2. **Close and reopen the app** - should see "Alert already in Firestore, skipping SMS" instead of sending again
3. **Trigger another panic alert** - should send SMS for this new alert
4. **Monitor SMS logs** - confirm only ONE SMS per unique alert

## Expected Behavior After Fix

```
Scenario 1: Panic alert triggered
✅ SMS sent once
✅ Alert ID added to _processedPanicAlertIds
✅ Alert ID saved to Firestore with all processed IDs
✅ _lastProcessedAlertId cleared

Scenario 2: Same alert fires again before debounce completes
✅ _lastProcessedAlertId check catches it and returns early
✅ NO SMS sent
✅ Print: "Already processing {alertId}, skipping duplicate"

Scenario 3: App restarts
✅ _loadLastPanicAlertTimestamp() runs first
✅ Loads all processed alert IDs from Firestore
✅ Populates _processedPanicAlertIds set
✅ When same alert found in stream, Firestore check catches it
✅ NO SMS sent
✅ Print: "Alert already in Firestore, skipping SMS"

Scenario 4: New panic alert after app restart
✅ New alert has different timestamp, new alert ID
✅ Not in _processedPanicAlertIds
✅ Not in Firestore sms_tracking
✅ SMS is sent
✅ Alert saved to Firestore
```

## Cost Impact

- **Before Fix**: Same alert could trigger multiple SMS charges (wasted credits)
- **After Fix**: Each unique panic alert triggers EXACTLY ONE SMS

## Files Modified

- `lib/screens/home_screen.dart` - Added 6 `_lastProcessedAlertId` null assignments and 1 guard check

## Testing Checklist

- [ ] Trigger panic alert - verify SMS sent once
- [ ] Close/restart app - verify NO duplicate SMS
- [ ] Trigger second panic alert - verify SMS sent (should be NEW alert)
- [ ] Check Firestore `guardians/{userId}/settings/sms_tracking` for alert IDs
- [ ] Verify console logs show correct messages
- [ ] Test with airplane mode - ensure graceful handling

## Notes

- This fix uses a multi-level approach because different bugs could occur at different stages
- The `_lastProcessedAlertId` guard prevents the timer race condition at the source
- The Firestore check ensures app restart doesn't trigger old alerts
- The error handling ensures we fail SAFE (no SMS) rather than fail OPEN (send SMS)
