# Data & Synchronisation Pipeline

This reference explains how recordings and metadata travel through the app and interact with backend services.

## Local storage layout
- **SQLite database** – Two tables (`recordings`, `recording_parts`) capture session metadata and segment-level GPS traces. Status flags track whether an item is pending, uploaded, or confirmed by the backend.[assets/databaseScheme.sql (lines 1–22)](assets/databaseScheme.sql#L1-L22)[lib/database/databaseNew.dart (lines 112–240)](lib/database/databaseNew.dart#L112-L240)
- **Audio files** – Raw PCM WAV files are written under the platform-specific application documents directory using timestamp-based filenames.[lib/database/databaseNew.dart (lines 31–49)](lib/database/databaseNew.dart#L31-L49)[lib/recording/waw.dart (lines 1–160)](lib/recording/waw.dart#L1-L160)
- **Secure storage** – JWT access tokens, refresh tokens, and FCM device tokens are stored with `flutter_secure_storage` so they survive restarts and background execution.[lib/firebase/firebase.dart (lines 57–160)](lib/firebase/firebase.dart#L57-L160)[lib/auth/authorizator.dart (lines 1–160)](lib/auth/authorizator.dart#L1-L160)

## Upload lifecycle
1. **Queue** – When a recording session ends, the SQLite row is marked as pending upload. The Workmanager background task or the user manually initiating sync will pick it up.[lib/database/databaseNew.dart (lines 240–360)](lib/database/databaseNew.dart#L240-L360)
2. **Prepare payload** – Audio is optionally transcoded, dialect metadata is attached, and request bodies are constructed using host URLs derived from `Config`.[lib/config/config.dart (lines 1–160)](lib/config/config.dart#L1-L160)[lib/PostRecordingForm/addDialect.dart (lines 1–160)](lib/PostRecordingForm/addDialect.dart#L1-L160)
3. **Authenticate** – API requests attach JWT credentials read from secure storage. Tokens are refreshed using the authorizator when expired.[lib/auth/authorizator.dart (lines 80–160)](lib/auth/authorizator.dart#L80-L160)[lib/database/databaseNew.dart (lines 240–360)](lib/database/databaseNew.dart#L240-L360)
4. **Transmit** – The HTTP client uploads data. Failures are logged and retried by future background runs; once successful, `upload_status` flips to `1` so the entry is hidden from the pending queue.[lib/database/databaseNew.dart (lines 240–360)](lib/database/databaseNew.dart#L240-L360)[assets/databaseScheme.sql (lines 1–22)](assets/databaseScheme.sql#L1-L22)
5. **Acknowledge** – Server-side dialect confirmations or notifications are stored locally and surfaced through the notification list, ensuring observers know when experts reviewed their uploads.[lib/database/databaseNew.dart (lines 360–440)](lib/database/databaseNew.dart#L360-L440)[lib/notificationPage/notifList.dart (lines 1–160)](lib/notificationPage/notifList.dart#L1-L160)

## Background execution
- **Workmanager jobs** – `callback_dispatcher.dart` registers periodic background tasks for uploads, notification refresh, and maintenance clean-up. Tasks run even when the app is closed, respecting the platform’s scheduling constraints.[lib/callback_dispatcher.dart (lines 1–160)](lib/callback_dispatcher.dart#L1-L160)[lib/main.dart (lines 84–151)](lib/main.dart#L84-L151)
- **Foreground service** – `FlutterForegroundTask` keeps the recording service alive for long-running captures on Android, providing a persistent notification to satisfy OS requirements.[lib/main.dart (lines 104–151)](lib/main.dart#L104-L151)
- **Firebase messaging** – Background FCM handlers cache push notifications in SQLite so that the in-app notification screen can display them even if the user missed the original toast.[lib/firebase/firebase.dart (lines 18–160)](lib/firebase/firebase.dart#L18-L160)[lib/notificationPage/notifications.dart (lines 1–160)](lib/notificationPage/notifications.dart#L1-L160)

## Data privacy considerations
- All recordings and metadata are governed by the GPL-3.0-or-later licence included in the repository’s root, and personal data must follow institutional policies when exported.[LICENSE (lines 1–190)](LICENSE#L1-L190)
- Sensitive credentials (JWT tokens, Firebase keys) never live in Git; use environment-specific secret management when building production releases.[lib/auth/authorizator.dart (lines 1–160)](lib/auth/authorizator.dart#L1-L160)[lib/config/config.dart (lines 1–160)](lib/config/config.dart#L1-L160)

## Troubleshooting sync issues
| Symptom | Likely cause | Suggested action |
| --- | --- | --- |
| Pending uploads never clear | Device offline or API host misconfigured | Verify `Config.host` and network connectivity, then trigger a manual sync from the recordings list.[lib/config/config.dart (lines 1–160)](lib/config/config.dart#L1-L160)[lib/database/databaseNew.dart (lines 240–360)](lib/database/databaseNew.dart#L240-L360) |
| Push notifications missing | FCM token not registered or Google Play Services outdated | Call `addDevice()` again (e.g., via hot restart) and ensure Play Services are available.[lib/firebase/firebase.dart (lines 95–160)](lib/firebase/firebase.dart#L95-L160)[lib/main.dart (lines 52–99)](lib/main.dart#L52-L99) |
| Background jobs not firing | Workmanager disabled or OS battery optimisations killing tasks | Reinstall the app, check Workmanager logs, and advise users to whitelist the app from battery optimisations.[lib/callback_dispatcher.dart (lines 1–160)](lib/callback_dispatcher.dart#L1-L160)[lib/main.dart (lines 84–151)](lib/main.dart#L84-L151) |
