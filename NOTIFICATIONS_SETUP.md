# Foreground Push Setup Notes

1. **APNs key**
   - In Apple Developer → Keys, create or reuse an APNs Auth Key (`.p8`).
   - Record `Key ID`, `Team ID`, keep the downloaded `.p8` secure.

2. **Firebase Console**
   - Project Settings → Cloud Messaging → iOS app.
   - Upload the APNs key (`.p8`) and fill Key ID + Team ID.
   - Ensure the bundle identifier matches `com.nickkenkel.messageai`.

3. **Xcode project**
   - Capabilities: `Push Notifications` + `Background Modes` → `Remote notifications`.
   - `GoogleService-Info.plist` must be included in the main target.

4. **Code**
   - `NotificationService` handles permission prompts, token registration, and foreground banners.
   - FCM token and APNs token prints to console (`[NotificationService] FCM token:`).

5. **Testing**
   - Simulator: tokens work with APNs sandbox for foreground data messages.
   - Physical device: run on device to receive actual APNs pushes.
   - Use Firebase Console or `curl` with the FCM v1 API to send a message while app is in foreground/background.

   | Scenario | Steps | Expected |
   | --- | --- | --- |
   | Foreground alert (simulator) | Send notification with `notification` payload while app active | In-app banner (UNNotification), console logs token + receipt |
   | Foreground alert (device) | Same payload on physical device | Native banner + sound |
   | Background wake (device) | Lock device, send notification | Banner on lock screen, tap should relaunch app (routing TBD) |
   | Token rotation | Kill & relaunch app | New token printed if it changes |
   | Permissions denied | Deny prompt, trigger registration | No crash; authorization status remains `.denied` |

6. **Next steps**
   - Handle notification tap routing (navigate to conversation ID).
   - Sync FCM tokens to Firestore to target specific users.
   - Add badge count updates when new messages arrive.
