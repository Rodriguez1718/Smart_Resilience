# Twilio SMS Setup Guide

This guide explains how to set up Twilio for SMS notifications in the Smart Resilience app.

## Overview

The Smart Resilience app uses Twilio to send SMS alerts to guardians when critical events occur:
- SOS/Panic alerts from the child
- Geofence entry alerts
- Geofence exit alerts

SMS notifications provide a secondary notification channel (primary is Firebase Cloud Messaging push notifications) to ensure guardians receive critical alerts even if the app is not installed or push notifications are disabled.

## Prerequisites

1. A Twilio account (create one at https://www.twilio.com)
2. Twilio trial account includes $15 free credit (sufficient for testing)
3. Verified phone numbers (on trial accounts, you can only send SMS to verified numbers)
4. Firebase project with Cloud Functions enabled
5. Access to Firebase CLI

## Step 1: Create a Twilio Account

1. Go to https://www.twilio.com
2. Sign up for a free account
3. Complete the verification process
4. Create a new Twilio phone number in the console:
   - Dashboard → Phone Numbers → Buy a Number
   - Choose a phone number (any region works for testing)
   - Select SMS capability
   - Save the phone number (you'll need this later)

**Important for Philippines Users:**
- Twilio phone numbers are based in the US/International carriers
- Guardian phone numbers must be in E.164 format: `+639XXXXXXXXX` (for PH numbers)
- Twilio's SMS delivery to PH numbers works well but may vary by carrier

## Step 2: Get Twilio Credentials

1. From Twilio console, go to Account menu → API keys & tokens
2. Copy your:
   - **Account SID** (starts with "AC...")
   - **Auth Token** (treat this as a password - keep it secret!)
3. Note your **Twilio Phone Number** (the one you purchased)

## Step 3: Set Firebase Functions Configuration

Set the Twilio credentials in Firebase Functions configuration:

```bash
firebase functions:config:set twilio.account_sid="ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" twilio.auth_token="your_auth_token_here" twilio.phone_number="+1234567890"
```

Replace:
- `ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx` with your actual Account SID
- `your_auth_token_here` with your actual Auth Token
- `+1234567890` with your Twilio phone number (include + and country code)

**Example for Philippines:**
```bash
firebase functions:config:set twilio.account_sid="ACxxxxxxxxxx" twilio.auth_token="abcdef123456" twilio.phone_number="+15551234567"
```

## Step 4: Verify Environment Variables

To verify the configuration was set correctly:

```bash
firebase functions:config:get
```

You should see output like:
```json
{
  "twilio": {
    "account_sid": "ACxxxxxxxxxx",
    "auth_token": "abcdef123456",
    "phone_number": "+15551234567"
  }
}
```

## Step 5: Verify Guardian Phone Numbers

Guardian phone numbers are automatically stored when setting up the app:

1. In `lib/screens/guardian_setup_screen.dart`:
   - Phone numbers are normalized to E.164 format
   - `09XXXXXXXXX` → `+639XXXXXXXXX` (Philippines)
   - Stored in Firestore: `guardians/{userId}` → `phoneNumber` field
   - SMS toggle stored as: `guardians/{userId}` → `smsEnabled` boolean

2. Verify in Firebase Console:
   - Go to Firestore Database
   - Navigate to `guardians` collection
   - Check each guardian document has `phoneNumber` and `smsEnabled` fields

**Twilio Trial Account Limitation:**
- On trial accounts, you can **only send SMS to verified phone numbers**
- Upgrade your account or add the guardian's phone number as a verified number in Twilio console
- To verify a number: Dashboard → Phone Numbers → Verify Caller ID

## Step 6: Install Dependencies

Install the Twilio npm package in Cloud Functions:

```bash
cd functions
npm install
```

This installs the `twilio` package specified in `functions/package.json`.

## Step 7: Deploy Cloud Functions

Deploy the updated Cloud Functions with Twilio integration:

```bash
firebase deploy --only functions
```

This uploads the updated `functions/index.js` which includes the Twilio SMS sending logic.

## Step 8: Test SMS Delivery

1. **Prepare a test device:**
   - Have the child tracking device running (Arduino/ESP32 with GPS)
   - Have the Flutter app open on guardian phone
   - Ensure SMS is enabled in Settings

2. **Trigger a test alert:**
   - Manually update the Firebase Realtime Database:
     - Path: `alerts/{deviceId}/{timestamp}`
     - Add: `{ "type": "panic", "location": {...}, "timestamp": ... }`
   - OR trigger SOS from device firmware if available

3. **Check both channels:**
   - **Push Notification:** Should appear immediately on guardian's device
   - **SMS:** Should arrive 1-2 seconds after push notification
   - Both should contain alert details (type, location info)

4. **Monitor logs:**
   ```bash
   firebase functions:log
   ```
   Look for entries from `sendAlertNotification` function showing both FCM and SMS sending.

## SMS Message Templates

The app sends different messages based on alert type:

### SOS/Panic Alert
```
🚨 PANIC ALERT! Your child triggered SOS at [Time]. Location: [Address]. Device: [Name]
```

### Geofence Entry Alert
```
📍 ENTRY: Your child entered a safe zone [Zone Name] at [Time]. Device: [Name]
```

### Geofence Exit Alert
```
⚠️ EXIT: Your child left the safe zone [Zone Name] at [Time]. Device: [Name]
```

## Troubleshooting

### SMS Not Sending
1. **Check Twilio Account Status:**
   - Ensure account is active and has credit
   - Trial accounts have limited credits

2. **Check Phone Number Verification (Trial Accounts):**
   - On trial, must verify receiving number in Twilio console
   - Go to Verify Caller ID and add the guardian's phone number

3. **Check Firebase Functions Logs:**
   ```bash
   firebase functions:log
   ```
   - Look for `SMS failed:` error messages
   - Check phone number format (must be E.164: `+639XXXXXXXXX`)

4. **Check Firestore Guardian Document:**
   - Verify `smsEnabled: true` is set
   - Verify `phoneNumber` field exists and is in correct format

5. **Check Cloud Functions Configuration:**
   ```bash
   firebase functions:config:get
   ```
   - Ensure `twilio.account_sid`, `auth_token`, `phone_number` are all set

### SMS Delivery Delay
- Twilio typically delivers SMS within 1-3 seconds
- Carrier routing can add delays
- Push notifications arrive first (instant)

### Wrong Phone Number Format
- Guardian phone numbers must be E.164 format: `+639XXXXXXXXX`
- The `guardian_setup_screen.dart` automatically normalizes Philippine numbers
- For other countries, ensure proper E.164 formatting

## Security Notes

⚠️ **IMPORTANT:**
- **Never commit `Auth Token` to version control**
- Use Firebase Functions config to store secrets
- Auth Token is treated like a password - rotate it periodically
- In production, consider using Firebase Secrets Manager

## Cost Considerations

**Twilio Pricing:**
- SMS outbound: ~$0.0075 per message (varies by country)
- Trial account: $15 free credit
- Estimated cost: ~1,200 SMS messages with trial credit

**For Production:**
- Monitor usage in Twilio console
- Set up billing alerts
- Consider bulk SMS pricing for high-volume applications

## Firebase Functions Environment

The `index.js` Cloud Function:
1. Listens to Firebase Realtime Database: `alerts/{deviceId}/{timestamp}`
2. Reads guardian data from Firestore: `guardians/{guardianId}`
3. Sends FCM push notification (existing)
4. Sends SMS via Twilio (new)
5. Gracefully handles SMS failures (doesn't fail push notification)

**Code Location:** `functions/index.js` → `sendAlertNotification` function

## Next Steps

After completing this setup:

1. ✅ Set Twilio environment variables
2. ✅ Verify guardian phone numbers in Firestore
3. ✅ Deploy Cloud Functions
4. ✅ Test SMS delivery
5. ✅ Monitor logs for any issues
6. ✅ Educate guardians about SMS notification feature

## Additional Resources

- Twilio Console: https://www.twilio.com/console
- Twilio Docs: https://www.twilio.com/docs/sms
- Firebase Functions Config: https://firebase.google.com/docs/functions/config-env
- E.164 Phone Number Format: https://en.wikipedia.org/wiki/E.164
