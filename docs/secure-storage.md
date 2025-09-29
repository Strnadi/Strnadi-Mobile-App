# Secure storage key reference

This page lists every key persisted via [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage) and
explains what the value represents, where it is set, and which flows consume it.

## Authentication & account state

| Key | Description | Writers | Consumers |
| --- | --- | --- | --- |
| `token` | JWT returned after authenticating a user. Refreshed when expiring and cleared on logout. | Login flow, registration confirmation, Apple sign-in, and token refresh routines store the token after successful responses.【F:lib/auth/login.dart†L122-L176】【F:lib/auth/registeration/overview.dart†L109-L149】【F:lib/auth/registeration/mail.dart†L461-L507】【F:lib/auth/authorizator.dart†L60-L110】 | Required for API requests throughout the app (e.g., fetching user info, syncing recordings, Firebase device registration).【F:lib/user/userPage.dart†L150-L195】【F:lib/database/databaseNew.dart†L718-L745】【F:lib/firebase/firebase.dart†L201-L275】 |
| `verified` | Tracks whether the backend has verified the user’s email. | Updated by the authorizator during JWT validation and the login/registration flows.【F:lib/auth/authorizator.dart†L74-L123】【F:lib/auth/login.dart†L141-L209】【F:lib/auth/registeration/overview.dart†L121-L149】 | Used to decide whether to route the user to verification screens when offline or at startup.【F:lib/auth/authorizator.dart†L112-L141】 |
| `userId` | Numeric identifier for the authenticated user. | Persisted after fetching `/users/get-id` following login, registration, and Apple sign-in.【F:lib/auth/login.dart†L143-L209】【F:lib/auth/registeration/overview.dart†L121-L149】【F:lib/auth/registeration/mail.dart†L478-L507】 | Queried when uploading recordings, fetching profile data, and linking device registrations to a user.【F:lib/database/databaseNew.dart†L1042-L1088】【F:lib/user/userPage.dart†L150-L195】【F:lib/firebase/firebase.dart†L160-L214】 |

## Profile caching

| Key | Description | Writers | Consumers |
| --- | --- | --- | --- |
| `user` | Cached user first name for quick display on the profile page. | Stored after fetching profile details during profile load and login hydration routines.【F:lib/user/userPage.dart†L150-L171】【F:lib/auth/authorizator.dart†L358-L403】 | Read to populate UI before making a network call and to render greetings in shared UI components.【F:lib/user/userPage.dart†L140-L175】【F:lib/bottomBar.dart†L57-L108】 |
| `lastname` | Cached user last name alongside the first name cache. | Written during the same profile fetches as `user`.【F:lib/user/userPage.dart†L150-L171】【F:lib/auth/authorizator.dart†L358-L403】 | Accessed with `user` for offline profile display and cleared during logout.【F:lib/user/userPage.dart†L140-L175】【F:lib/bottomBar.dart†L57-L108】 |
| `firstName`, `lastName`, `nick` | Detailed identity fields stored after successfully resolving the user’s profile from the API so multiple views can reuse them. | Persisted during the login flow when `GetUserName` resolves profile details.【F:lib/auth/login.dart†L75-L176】 | Read on the profile screen to render the greeting while offline.【F:lib/user/userPage.dart†L65-L73】 |
| `profileImage` | Local path to the user’s selected avatar for quick reload after app restarts. | Updated when the user picks a profile photo and uploads it to the backend.【F:lib/user/userPage.dart†L177-L220】 | Not currently read from secure storage; the profile screen keeps the path in memory after upload for immediate display.【F:lib/user/userPage.dart†L256-L299】 |

## Device & messaging

| Key | Description | Writers | Consumers |
| --- | --- | --- | --- |
| `fcmToken` | Firebase Cloud Messaging token linked to the authenticated device. | Stored after registering/updating the device with the backend or when a new token arrives.【F:lib/firebase/firebase.dart†L160-L275】 | Retrieved when refreshing device registrations and removed when the user signs out or deletes the device record.【F:lib/firebase/firebase.dart†L230-L305】【F:lib/bottomBar.dart†L57-L108】 |

## Maintenance

- All keys are cleared on explicit logout, and authentication tokens are also deleted when the backend instructs the app to log out.【F:lib/bottomBar.dart†L57-L108】【F:lib/auth/authorizator.dart†L403-L415】
- When adding a new entry to `FlutterSecureStorage`, extend the relevant table above with a short description and code references so the team can keep this page current.
