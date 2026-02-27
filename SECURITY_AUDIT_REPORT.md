# Security Analysis Report - January 21, 2026

### 1. Critical: Hardcoded Firebase Service Account Key
*   **Vulnerability:** Hardcoded Secrets
*   **Vulnerability Type:** Security
*   **Severity:** Critical
*   **Source Location:** `lib/notificationPage/notifications.dart:28`
*   **Line Content:** `final jsonString = await rootBundle.loadString('assets/firebase-secrets.json');`
*   **Description:** The application loads a Firebase Service Account key from `assets/firebase-secrets.json`. Service account keys provide broad administrative access to the Firebase project. Bundling this file in the application assets allows any user to extract the key and gain control over the project.
*   **Recommendation:** **IMMEDIATELY REMOVE** `firebase-secrets.json` from the assets and the repository. Do not send push notifications from the client using a service account. Instead, implement a backend endpoint that handles the notification logic and call that endpoint from the client.

### 2. Critical: Logging of Sensitive Authentication Tokens (JWT)
*   **Vulnerability:** Information Disclosure (Logging)
*   **Vulnerability Type:** Security
*   **Severity:** Critical
*   **Description:** JWT tokens (Bearer tokens) are logged to the console in multiple locations. In a production environment, these logs can be captured by logging systems or viewed via ADB/Xcode, allowing an attacker to hijack user sessions.
*   **Findings:**
    *   **File:** `lib/auth/google_sign_in_service.dart:85`
        *   **Line Content:** `logger.i('google idToken: $idToken');`
    *   **File:** `lib/auth/login.dart:169`
        *   **Line Content:** `logger.i('Login response: ${response.statusCode} | ${response.body}');`
    *   **File:** `lib/database/databaseNew.dart:255`
        *   **Line Content:** `logger.i("token: $token");`
    *   **File:** `lib/firebase/firebase.dart:216`
        *   **Line Content:** `logger.i('JWT Token: $jwt SENDING NEW TOKEN TO SERVER');`
*   **Recommendation:** Remove all logging statements that output JWTs, ID tokens, or raw response bodies from authentication endpoints.

### 3. High: Excessive Data Exposure due to Logic Bug
*   **Vulnerability:** IDOR / Excessive Data Exposure
*   **Vulnerability Type:** Security
*   **Severity:** High
*   **Source Location:** `lib/dialects/ModelHandler.dart:156`
*   **Line Content:** `url.replace(query: 'recordingId=$recordingBEID');`
*   **Description:** The code uses `url.replace(query: ...)` but ignores the return value. `Uri` in Dart is immutable, so the `url` variable remains unchanged. As a result, the `fetchRecordingDialects` function calls the `/recordings/filtered` endpoint without the `recordingId` query parameter. This likely causes the backend to return *all* dialect records for all recordings (potentially belonging to other users), leading to excessive data exposure and bandwidth usage.
*   **Recommendation:** Assign the result of `replace` back to a variable: `url = url.replace(query: ...);` (ensure `url` is not `final` or use a new variable).

### 4. High: Logging of User Location Data
*   **Vulnerability:** Privacy Violation
*   **Vulnerability Type:** Privacy
*   **Severity:** High
*   **Source Location:** `lib/localRecordings/recList.dart:731-732`
*   **Line Content:** `logger.w('All parts: $partsS');`
*   **Data Type:** GPS Coordinates
*   **Description:** The application logs the full JSON representation of `RecordingPart` objects. These objects contain precise GPS coordinates (`gpsLatitudeStart`, `gpsLongitudeStart`), exposing user location history in the logs.
*   **Recommendation:** Remove the log statement or redact location fields before logging.

### 5. High: Logging of PII (User Name)
*   **Vulnerability:** Privacy Violation
*   **Vulnerability Type:** Privacy
*   **Severity:** High
*   **Source Location:** `lib/user/userPage.dart:81`
*   **Line Content:** `logger.i("Loaded name from local storage: $f $l ($n)");`
*   **Data Type:** Name, Nickname
*   **Description:** The application explicitly logs the user's full name and nickname.
*   **Recommendation:** Remove this log statement.

### 6. Medium: Logging of FCM Token
*   **Vulnerability:** Information Disclosure
*   **Vulnerability Type:** Security
*   **Severity:** Medium
*   **Source Location:** `lib/firebase/firebase.dart:211`
*   **Line Content:** `logger.i("Firebase token: $token");`
*   **Description:** The Firebase Cloud Messaging (FCM) token is logged. While not as critical as a JWT, leaking this allows an attacker to send push notifications to the user's device.
*   **Recommendation:** Remove the log statement.

### 7. Low: Potential SQL Injection (Bad Practice)
*   **Vulnerability:** SQL Injection
*   **Vulnerability Type:** Security
*   **Severity:** Low
*   **Source Location:** `lib/database/databaseNew.dart:1321-1322`
*   **Line Content:** `.rawQuery("SELECT * FROM recordingParts WHERE RecordingId = $id");`
*   **Description:** The query uses string interpolation instead of parameterized queries (`?`). While `id` is currently typed as `int` in the function signature (mitigating immediate exploitation), this is a bad practice that can lead to vulnerabilities if the variable type changes.
*   **Recommendation:** Use `whereArgs`: `db.rawQuery("SELECT * FROM recordingParts WHERE RecordingId = ?", [id]);`.
