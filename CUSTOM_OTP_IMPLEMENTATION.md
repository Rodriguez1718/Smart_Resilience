# Option 2: Custom iProgsms OTP Implementation

## Overview
Option 2 replaces Firebase Phone Authentication with a **custom OTP system that sends codes via iProgsms**. Guardian data still saves to Firebase normally - we're only changing the OTP delivery mechanism.

## How It Works

### 1. Registration Flow
```
Guardian Registration
    ↓
Enter Full Name + Phone Number + Device ID + Child Info
    ↓
Click "Send OTP"
    ↓
CustomOtpService generates 6-digit OTP
    ↓
OTP sent to phone via iProgsms API
    ↓
Guardian enters OTP (5-minute expiration)
    ↓
OTP verified locally
    ↓
Firebase account created (anonymous auth)
    ↓
Guardian profile saved to Firestore
```

### 2. Key Differences from Option 1

| Aspect | Option 1 (Firebase Auth) | Option 2 (Custom OTP) |
|--------|--------------------------|------------------------|
| OTP Provider | Firebase SMS | iProgsms |
| Phone Auth Type | Phone-based | Anonymous + Custom |
| OTP Storage | Firebase backend | Local in-memory Map |
| OTP Validity | Standard | 5 minutes |
| Guardian Data | Firestore ✓ | Firestore ✓ |
| SMS Alerts | iProgsms ✓ | iProgsms ✓ |
| Firebase Billing | Minimal | Minimal |

## Files Created/Modified

### NEW: `lib/services/custom_otp_service.dart`
Complete custom OTP service for iProgsms:

**Key Methods:**
- `sendOtp()` - Generate OTP, send via iProgsms, store temporarily
- `verifyOtp()` - Check if entered OTP matches stored OTP
- `clearOtp()` - Remove OTP after successful verification
- `_normalizePhoneNumber()` - Convert local format to E.164

**OTP Storage:**
```dart
static final Map<String, OtpData> _otpStore = {};
// Structure: {'+639XXXXXXXXX': OtpData(otp, createdAt, expiresAt, fullName)}
```

**OTP Validity:**
- Generated: 6-digit random code
- Expiry: 5 minutes from sending
- Status: Shows countdown in UI

### MODIFIED: `lib/screens/guardian_setup_screen.dart`
Replaced Firebase Phone Auth with custom OTP:

**Changes:**
1. **Imports:** Added `import 'package:smart_resilience_app/services/custom_otp_service.dart';`
2. **State Variables:** 
   - Removed: `String? _verificationId;`
   - Added: `int _otpCountdown = 0;` (for UI countdown display)
3. **Methods:**
   - Replaced: `FirebaseAuth.verifyPhoneNumber()` with `CustomOtpService.sendOtp()`
   - Replaced: `PhoneAuthProvider.credential()` with `CustomOtpService.verifyOtp()`
   - Added: `_startOtpCountdown()` - Displays countdown timer
   - Removed: `_signInAndFinalizeProfile()` (no longer needed)
4. **Firebase Account Creation:**
   ```dart
   // After OTP verified, create anonymous account
   UserCredential userCredential = 
       await FirebaseAuth.instance.signInAnonymously();
   ```
5. **UI Improvements:**
   - Countdown timer: "OTP expires in 4:52"
   - Resend button: "Resend in 4:52" (disabled until countdown expires)
   - Max length on OTP field: 6 digits
   - Red text when OTP about to expire

## Guardian Data Flow

**Everything still saves to Firebase exactly the same:**

```dart
// Firestore - guardians/{userId}
{
  'fullName': 'John Doe',
  'phoneNumber': '+639123456789',        // E.164 format
  'role': 'Parent',
  'smsEnabled': true,                     // Enables SMS alerts
  'createdAt': Timestamp(...),
  'lastLogin': Timestamp(...),
  'hasCompletedSetup': true
}
```

**Also saved:**
- `paired_device` subcollection: deviceId, childName, childAge
- `geofences` subcollection: placeholder
- `settings` subcollection: placeholder

## Testing the Implementation

### 1. Setup Requirements
```
✓ iProgsms account created
✓ iProgsms API key: 79f0238238e0cdc03971d886d9485fb33332396d
✓ iProgsms account has sufficient credits (₱100+)
✓ App has internet connection
```

### 2. Test Registration Flow
```
1. Launch app → Guardian Setup Screen
2. Enter:
   - Full Name: John Doe
   - Phone Number: 09123456789 (or +639123456789)
   - Device ID: child_01
   - Child Name: Maria
   - Child Age: 12
   - Role: Parent
3. Click "Send OTP"
4. Check phone for OTP SMS (from iProgsms)
5. Check console for DEBUG: OTP printed
6. Enter OTP in app
7. Click "Verify OTP & Create Profile"
8. Success! Profile appears in Firestore
```

### 3. Verify Firebase Saved Correctly
```
Firestore → guardians collection → {userId} document
{
  fullName: 'John Doe'
  phoneNumber: '+639123456789'
  role: 'Parent'
  smsEnabled: true
  createdAt: (timestamp)
  hasCompletedSetup: true
}
```

## Console Debug Output

When testing, you'll see console logs:

```
[CustomOtpService] OTP sent successfully to +639123456789
[DEBUG] OTP: 123456
[CustomOtpService] OTP verified for +639123456789
[CustomOtpService] OTP cleared for +639123456789
```

The `[DEBUG] OTP: XXXXXX` line helps you quickly test without waiting for SMS.

## Important Notes

### 1. OTP Storage (Development vs Production)
**Current (Development):** OTP stored in-memory Map
```dart
static final Map<String, OtpData> _otpStore = {};
```

**Limitation:** OTPs lost if app restarts during registration

**For Production:** Consider moving OTP storage to Firestore:
```dart
// Store in: otp_requests/{phoneNumber}
// Read for verification
// Delete after verification or expiry
```

### 2. Phone Number Normalization
Both local and international formats work:
```
09123456789   → +639123456789  ✓
09123456789   → +639123456789  ✓
+639123456789 → +639123456789  ✓
```

### 3. OTP Expiration
- **5 minutes:** Hard expiration
- **UI Countdown:** Shows remaining time
- **Can't Resend:** Until countdown completes or manually implement resend-without-wait

### 4. Error Handling
If iProgsms fails (network, API error):
- Returns `false` from `sendOtp()`
- Shows: "Failed to send OTP. Please try again."
- User can retry without data loss

## Troubleshooting

| Issue | Solution |
|-------|----------|
| OTP not received | Check iProgsms account balance, verify phone number |
| Can't click "Verify" | Enter exactly 6 digits, OTP must not be expired |
| Can't click "Resend" | Wait for countdown to complete |
| Firebase data not saving | Check Firestore rules allow read/write to `guardians/{uid}` |
| App crashes on OTP verify | Check internet connection, verify iProgsms API key |

## API Integration Details

### iProgsms API Call (Custom OTP Service)
```
POST https://api.iprogsms.com/api/send-sms
Body:
{
  apikey: '79f0238238e0cdc03971d886d9485fb33332396d'
  senderid: 'SmartRes'
  phonenumber: '+639123456789'
  message: 'Your Smart Resilience OTP is: 123456. Valid for 5 minutes.'
}
```

### Firebase Authentication
```dart
// Anonymous account (for storing data only)
UserCredential userCredential = 
    await FirebaseAuth.instance.signInAnonymously();
// user.uid used for Firestore document ID
```

## Next Steps

1. **Test registration** with real phone number
2. **Verify SMS delivery** from iProgsms
3. **Check Firestore** to confirm data saved
4. **Test SMS alerts** from home_screen.dart
5. **Optional:** Migrate OTP storage to Firestore for production

## Summary

✅ Guardian data **still saves to Firebase** exactly as before  
✅ OTP **sent via iProgsms** instead of Firebase  
✅ **5-minute expiration** with countdown UI  
✅ **Custom validation** - no Firebase Phone Auth dependency  
✅ **Cheaper** - iProgsms billing only, minimal Firebase usage  
✅ **Simpler** - no phone auth complexity, direct SMS for everything  
