const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

exports.proxyToFirebase = functions.https.onRequest(async (req, res) => {
    try {
        const deviceId = req.body.deviceId;
        const path = req.body.path; // e.g., 'alerts/child_01'
        const data = req.body.data; // JSON payload

        if (!deviceId || !path || !data) {
            return res.status(400).send("Missing required fields");
        }

        const dbRef = admin.database().ref(path);
        await dbRef.set(data);

        return res.status(200).send({ success: true });
    } catch (err) {
        console.error("Error in proxy:", err);
        return res.status(500).send({ success: false, error: err.message });
    }
});

// NEW: Send FCM notification when an alert is created
exports.sendAlertNotification = functions.database
    .ref('alerts/{deviceId}/{timestamp}')
    .onCreate(async (snapshot, context) => {
        try {
            const alert = snapshot.val();
            const deviceId = context.params.deviceId;

            console.log(`New alert detected for device ${deviceId}:`, alert);

            // Get all guardians to find who owns this device
            const guardiansSnapshot = await admin.firestore()
                .collection('guardians')
                .get();

            for (const guardianDoc of guardiansSnapshot.docs) {
                const guardianData = guardianDoc.data();
                const pairedDeviceId = guardianData.pairedDeviceId;

                // Check if this guardian owns the device that triggered the alert
                if (pairedDeviceId === deviceId) {
                    const fcmToken = guardianData.fcmToken;
                    if (!fcmToken) {
                        console.log(`Guardian ${guardianDoc.id} has no FCM token`);
                        continue;
                    }

                    // Build the notification message
                    let title = '🔔 Alert';
                    let body = 'New alert from your device';
                    let smsBody = 'Alert from your child\'s device';

                    if (alert.status === 'sos' || alert.status === 'panic') {
                        title = '🚨 PANIC ALERT!';
                        body = `Your device triggered a panic button!\nLocation: ${alert.lat?.toFixed(4)}, ${alert.lng?.toFixed(4)}`;
                        smsBody = `🚨 PANIC ALERT!\nYour child triggered SOS at ${new Date().toLocaleTimeString()}\nLat: ${alert.lat?.toFixed(4)} | Lng: ${alert.lng?.toFixed(4)}`;
                    } else if (alert.status === 'entry') {
                        title = '📍 Geofence Entry';
                        body = `Your device entered a geofence.\nLocation: ${alert.lat?.toFixed(4)}, ${alert.lng?.toFixed(4)}`;
                        smsBody = `📍 ENTRY: Your child entered a safe zone\nLocation: ${alert.lat?.toFixed(4)}, ${alert.lng?.toFixed(4)}`;
                    } else if (alert.status === 'exit') {
                        title = '⚠️ Geofence Exit';
                        body = `Your device exited a geofence.\nLocation: ${alert.lat?.toFixed(4)}, ${alert.lng?.toFixed(4)}`;
                        smsBody = `⚠️ EXIT: Your child left a safe zone\nLocation: ${alert.lat?.toFixed(4)}, ${alert.lng?.toFixed(4)}`;
                    }

                    const message = {
                        notification: {
                            title: title,
                            body: body,
                        },
                        data: {
                            deviceId: deviceId,
                            status: alert.status,
                            latitude: alert.lat?.toString() || '0',
                            longitude: alert.lng?.toString() || '0',
                            timestamp: context.params.timestamp,
                        },
                        token: fcmToken,
                    };

                    // Send the message
                    try {
                        await admin.messaging().send(message);
                        console.log(`FCM notification sent to ${guardianDoc.id}`);
                    } catch (error) {
                        console.error(`Error sending FCM to ${guardianDoc.id}:`, error);

                        // If token is invalid, remove it from Firestore
                        if (error.code === 'messaging/invalid-registration-token' ||
                            error.code === 'messaging/registration-token-not-registered') {
                            await guardianDoc.ref.update({
                                fcmToken: admin.firestore.FieldValue.delete(),
                            });
                            console.log(`Removed invalid FCM token for ${guardianDoc.id}`);
                        }
                    }

                    // NEW: Send SMS via iProgsms if enabled and phone number exists
                    // NOTE: SMS is now handled by the Flutter app directly
                    // This Cloud Function focuses on FCM push notifications only
                }
            }

            return null;
        } catch (error) {
            console.error('Error in sendAlertNotification:', error);
            return null;
        }
    });
