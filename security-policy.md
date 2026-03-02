# Security Analysis Report - Strnadi-API

This report outlines the security vulnerabilities identified during the audit conducted on January 22, 2026.

## Summary Table

| Severity | Vulnerability | Category |
| :--- | :--- | :--- |
| **Critical** | Second-Order SQL Injection | Security |
| **Critical** | Arbitrary File Write (via Path Traversal) | Security |
| **High** | Path Traversal (Arbitrary File Read/Write) | Security |
| **Medium** | Unauthenticated API Proxy (SSRF) | Security |
| **Medium** | Open Redirect | Security |

---

## Detailed Findings

### 1. Second-Order SQL Injection
- **Severity:** **Critical**
- **Source Location:** `Achievements/AchievementsController.cs` (Line 37)
- **Sink Location:** `Repository/AchievementsRepository.cs` (Line 137)
- **Line Content:** `var userIds = (await ExecuteSafelyAsync(Connection.QueryAsync<int>(sql)))?.ToArray();`
- **Description:** The application allows administrators to upload a raw SQL query string via the `sql` parameter in `AchievementsController.Post`. This query is stored directly in the database. Later, the `CheckAndAwardAchievements` method retrieves and executes this stored SQL query dynamically. This allows an attacker (with admin privileges) to execute arbitrary SQL commands, leading to potential full database compromise or Remote Code Execution (RCE).
- **Recommendation:** Do not store or execute raw SQL provided by user input. Use a structured query builder or predefined criteria map to generate safe, parameterized queries.

### 2. Arbitrary File Write (via Path Traversal)
- **Severity:** **Critical**
- **Source Location:** `Photos/PhotosController.cs` (Line 23)
- **Sink Location:** `Shared/Tools/FileSystemHelper.cs` (Line 115)
- **Line Content:** `return GetRecordingPhotosDirectoryPath(recordingId) + $"/{photoId}.{format}";`
- **Description:** The `PhotosController` and `UsersController` allow users to upload photos, accepting a `format` parameter (e.g., "png", "jpg") that is used directly to construct the file path. This parameter is not validated against an allowlist, allowing an attacker to supply malicious input like `png/../../shell.php`. This results in an Arbitrary File Write vulnerability, enabling attackers to overwrite sensitive files or upload executable scripts (Web Shells), leading to RCE.
- **Recommendation:** Strictly validate the `format` parameter against an allowlist of safe extensions (e.g., `png`, `jpg`). Never use raw user input to construct file extensions or paths.

### 3. Path Traversal (Arbitrary File Read/Write)
- **Severity:** **High**
- **Source Location:** `Articles/ArticlesController.cs` (Line 66)
- **Sink Location:** `Shared/Tools/FileSystemHelper.cs` (Line 132)
- **Line Content:** `return $"articles/{id}/{fileName}";`
- **Description:** The `ArticlesController` accepts a `fileName` parameter from the URL and passes it to `FileSystemHelper` to construct a file path without sanitization. This allows directory traversal (e.g., `../../etc/passwd`). Since the `Get` endpoint is unauthenticated, this enables Unauthenticated Arbitrary File Read. The authenticated `Post` endpoint allows Arbitrary File Write.
- **Recommendation:** Sanitize `fileName` to remove traversal characters (`../`) and use `Path.GetFileName()` to ensure only the filename is used. Validate that the resolved path is within the intended directory.

### 4. Unauthenticated API Proxy (SSRF / Quota Theft)
- **Severity:** **Medium**
- **Source Location:** `Utils/MapController.cs` (Line 30)
- **Sink Location:** `Utils/MapController.cs` (Line 33)
- **Line Content:** `var targetUrl = $"https://api.mapy.cz/{path}{query}";`
- **Description:** The `MapController` exposes an unauthenticated endpoint `ForwardToMapyCz` that proxies requests to `api.mapy.cz` using the server's API key. This allows any user to exhaust the application's API quota (DoS) or potentially abuse the upstream API.
- **Recommendation:** Add the `[Authorize]` attribute to the controller or method to require authentication. Validate the `path` parameter to ensure it matches expected patterns.

### 5. Open Redirect
- **Severity:** **Medium**
- **Source Location:** `Auth/AuthController.cs` (Line 258)
- **Sink Location:** `Auth/AuthController.cs` (Line 268)
- **Line Content:** `return Redirect(new Uri($"{returnUrl}#user={user}&id_token={idToken}").AbsoluteUri);`
- **Description:** The `AppleCallback` endpoint uses the `state` parameter to determine the redirect URL (`returnUrl`) without validation. An attacker can craft a malicious login link that redirects the user to a phishing site after a successful login.
- **Recommendation:** Validate `returnUrl` against a strictly defined allowlist of trusted domains or paths. Alternatively, store the return URL in a session state rather than the client-side `state` parameter.

