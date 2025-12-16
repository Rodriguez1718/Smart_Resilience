# Emergency Contacts Implementation

## Overview
Added functionality to allow guardians to add multiple emergency contacts that will be notified via SMS during panic button presses (SOS alerts).

## Changes Made

### 1. Profile Page UI (`lib/screens/profile_page.dart`)

#### New State Variables:
- `List<Map<String, String>> _emergencyContacts` - Stores emergency contacts list
- `TextEditingController _emergencyNameController` - For contact name input
- `TextEditingController _emergencyPhoneController` - For contact phone number input

#### New Methods:

**`_loadEmergencyContacts()`**
- Fetches all emergency contacts from Firestore subcollection
- Reads from `guardians/{userId}/emergency_contacts` collection
- Called on init to populate the UI

**`_addEmergencyContact()`**
- Validates contact name and phone number
- Normalizes phone number to E.164 format (+639XXXXXXXXX)
- Saves to Firestore with timestamp
- Clears input fields and reloads contact list
- Shows success/error feedback via SnackBar

**`_deleteEmergencyContact(String contactId)`**
- Removes contact from Firestore
- Reloads contact list
- Shows confirmation dialog before deletion
- Shows success/error feedback via SnackBar

**`_normalizePhoneNumber(String input)`**
- Converts various phone formats to E.164 format
- Handles Philippine numbers (+639XXXXXXXXX)
- Removes invalid characters
- Standardizes format for SMS sending

#### UI Components:

**Emergency Contacts Section** (`_buildEmergencyContactsSection()`)
- Displays header "Emergency Contacts" with subtitle "(Notified on panic)"
- Add contact form with:
  - Contact name input field
  - Phone number input field (with phone keyboard)
  - "Add Contact" button (deep purple colored)
- List of existing contacts showing:
  - Contact avatar with first letter initial
  - Contact name and phone number
  - Delete icon button with confirmation dialog
- Empty state message when no contacts added

#### Lifecycle:
- `dispose()` - Properly disposes text controllers
- `initState()` - Loads emergency contacts on screen initialization
- Emergency contacts section displayed before Save Changes button

### 2. SMS Service (`lib/services/iprogsms_service.dart`)

#### Updated `sendAlertSms()` Method:

**New Features:**
- Sends SMS to primary guardian phone number (if available and SMS enabled)
- Fetches all emergency contacts from `guardians/{userId}/emergency_contacts` subcollection
- Sends alert SMS to each emergency contact with personalized message
- Includes contact name prefix in message for clarity (e.g., "[Mom]")
- Non-blocking error handling - continues sending to other contacts even if one fails

**Message Format:**
- For PANIC/SOS alerts: "[ContactName]\n🚨 PANIC ALERT!\n{childName} triggered SOS at {time}.\nLocation: {latitude}, {longitude}"
- For ENTRY alerts: "[ContactName]\n📍 ENTRY: {childName} entered a safe zone at {time}.\nLocation: {latitude}, {longitude}"
- For EXIT alerts: "[ContactName]\n⚠️ EXIT: {childName} left a safe zone at {time}.\nLocation: {latitude}, {longitude}"

**Error Handling:**
- Gracefully skips missing phone numbers
- Catches errors per contact to continue with remaining contacts
- Logs errors for debugging

### 3. Firestore Schema

#### New Collection Structure:
```
guardians/{userId}/
  ├── (existing guardian data)
  └── emergency_contacts/
      ├── {documentId1}/
      │   ├── name: string (contact name, e.g., "Mom")
      │   ├── phone: string (E.164 format, e.g., "+639123456789")
      │   └── createdAt: timestamp (server timestamp)
      ├── {documentId2}/
      │   └── ...
```

## How It Works

### Adding Emergency Contact Flow:
1. Guardian opens Profile page
2. Emergency contacts section loads existing contacts
3. Guardian enters name and phone number
4. Guardian taps "Add Contact" button
5. System:
   - Validates inputs
   - Normalizes phone number
   - Saves to Firestore
   - Reloads contact list
   - Shows success message

### Deleting Emergency Contact Flow:
1. Guardian taps delete icon on contact
2. Confirmation dialog appears
3. Guardian confirms deletion
4. System:
   - Deletes from Firestore
   - Reloads contact list
   - Shows success message

### SMS Notification Flow (on Panic):
1. Device triggers panic button (SOS)
2. Alert recorded to Firebase Realtime Database
3. Home screen detects new alert
4. System calls `IProgSmsService.sendAlertSms()`
5. Service:
   - Fetches guardian's SMS preference and phone
   - Fetches all emergency contacts
   - Sends SMS to guardian (if SMS enabled and phone available)
   - Sends SMS to each emergency contact with personalized message
   - Logs success/errors

## User Experience

### Profile Page Changes:
- New "Emergency Contacts" section appears below guardian role selection
- Subtitle "(Notified on panic)" indicates these contacts receive panic notifications
- Clean card-based UI for adding new contacts
- ListView shows all contacts with delete option
- Empty state message when no contacts added

### SMS Notification Changes:
- All registered emergency contacts receive SMS alerts for:
  - Panic/SOS button presses
  - Geofence entry events
  - Geofence exit events
- Messages include contact name prefix for clarity
- SMS setting (enabled/disabled) still controls whether SMS is sent

## Benefits

1. **Multiple Responders** - More than one person can be notified of emergencies
2. **Flexible Contact Management** - Easy to add/remove contacts from profile
3. **Personalized Messages** - Each contact knows which alert is about them
4. **Non-Intrusive** - Doesn't require contacts to install app
5. **Reliable Communication** - SMS works without internet connection

## Technical Notes

- Emergency contacts stored in Firestore subcollection for scalability
- Phone numbers normalized to E.164 format for international compatibility
- SMS sending is non-blocking - continues even if one contact fails
- Timestamps captured for audit trail
- Text controllers properly disposed to prevent memory leaks

## Testing Checklist

- [ ] Add emergency contact - successfully saves to Firestore
- [ ] Delete emergency contact - successfully removes from Firestore
- [ ] Phone number normalization - converts various formats correctly
- [ ] SMS sending - primary guardian receives alert SMS
- [ ] SMS sending - emergency contacts receive alert SMS
- [ ] SMS message format - includes contact name and alert type
- [ ] Empty state - displays correctly when no contacts added
- [ ] Contact list - displays all contacts with proper formatting
- [ ] Error handling - continues with other contacts if one fails
- [ ] Permission - only own contacts can be edited

## Future Enhancements

- SMS receipt confirmation tracking
- Contact availability settings (e.g., quiet hours)
- Contact priority levels (primary vs secondary)
- Integration with push notifications for contacts
- Contact availability status (online/offline)
- Batch SMS sending optimization
