# Mobile Deployment

GitHub Actions deploys the Flutter app with Fastlane from `.github/workflows/deploy.yml`.

## Behavior

- Pushes to `main` deploy Android to the Google Play `internal` track and iOS to TestFlight.
- Pushes to `release/**` deploy Android to the closed testing track and iOS to TestFlight.
- Manual runs support `all`, `ios`, or `android`.
- Manual Android runs accept `play_track`, such as `internal`, `alpha`, `beta`, or a custom closed-testing track name from Play Console.
- `build_number` defaults to the GitHub Actions run number so Android `versionCode` and iOS `CFBundleVersion` stay numeric.
- `build_name` defaults to the version before `+` in `pubspec.yaml`.
- Both platforms build with `--dart-define-from-file=build.env.json`.

## Required GitHub Secrets

Create these repository secrets before running the workflow.

Shared:

- `BUILD_ENV_JSON_BASE64`: Base64-encoded `build.env.json`.

Android:

- `ANDROID_KEYSTORE_BASE64`: Base64-encoded Android upload keystore.
- `ANDROID_KEYSTORE_PASSWORD`: Keystore store password.
- `ANDROID_KEY_PASSWORD`: Key password.
- `ANDROID_KEY_ALIAS`: Key alias.
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64`: Base64-encoded Play Console service account JSON with release permissions.

iOS:

- `APP_STORE_CONNECT_API_KEY_ID`: App Store Connect API key ID.
- `APP_STORE_CONNECT_API_ISSUER_ID`: App Store Connect issuer ID.
- `APP_STORE_CONNECT_API_KEY_BASE64`: Base64-encoded `.p8` Team API key. This authenticates App Store Connect/Xcode automation, but it is not a signing certificate.

The App Store Connect key must be a Team key, not an Individual key, because automatic signing needs provisioning access. If cloud signing is not allowed for the key/account, configure manual signing secrets as well:

- `IOS_DISTRIBUTION_CERTIFICATE_BASE64`: Base64-encoded `.p12` Apple Distribution certificate with private key.
- `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`: Password for the `.p12` file.
- `IOS_APPSTORE_PROVISIONING_PROFILE_BASE64`: Base64-encoded App Store provisioning profile for `com.delta.strnadi`.

The `.p8` App Store Connect key cannot be converted into a `.p12`. The `.p12` must come from an Apple Distribution certificate whose private key is available in Keychain Access, or from another secure certificate store already used by the team.

## CI Caching

The workflow caches:

- Flutter pub packages.
- Android Gradle caches.
- Ruby gems through `ruby/setup-ruby`.
- CocoaPods downloads and installed pods.
- iOS Xcode DerivedData for incremental archive builds.

## Optional GitHub Variables

- `IOS_TEAM_ID`: Apple Developer Team ID. Defaults to `3GPTVJHVFN`.
- `FLUTTER_VERSION`: Flutter SDK version. Defaults to `3.41.2`.
- `GOOGLE_PLAY_CLOSED_TRACK`: Play Console closed-testing track for `release/**` pushes. Defaults to `alpha`.

## Local Encoding Commands

On macOS:

```sh
base64 -i build.env.json | pbcopy
base64 -i android/strnadi-release-key.jks | pbcopy
base64 -i play-store-service-account.json | pbcopy
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
base64 -i ios_distribution.p12 | pbcopy
base64 -i Strnadi_AppStore.mobileprovision | pbcopy
```

## Fastlane Lanes

Android:

```sh
cd android
bundle exec fastlane play
bundle exec fastlane internal
bundle exec fastlane closed_beta
```

iOS:

```sh
cd ios
bundle exec fastlane testflight
bundle exec fastlane beta
```
