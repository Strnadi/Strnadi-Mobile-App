# Mobile Deployment

GitHub Actions deploys the Flutter app with Fastlane from `.github/workflows/deploy.yml`.

## Behavior

- Pushes to `main` run the `internal` stage: Android is uploaded to the Google Play `internal` track and iOS is uploaded to TestFlight.
- Pushes to `release/**` run the `release_candidate` stage: Android is uploaded to the release-candidate Play track and iOS is uploaded to TestFlight.
- Manual `external_beta` runs promote Android from the release-candidate track to the Google Play open testing track and distribute the already uploaded TestFlight build to the `External` group.
- Manual `production` runs promote Android from open testing to production and submit the latest TestFlight build for App Store review with automatic release after approval.
- Manual runs support `all`, `ios`, or `android`.
- Manual Android runs can override `play_track`, but normal release automation derives it from the selected deployment stage.
- `build_number` defaults to the GitHub Actions run number so Android `versionCode` and iOS `CFBundleVersion` stay numeric.
- `build_name` defaults to the version before `+` in `pubspec.yaml`.
- Both platforms build with `--dart-define-from-file=build.env.json`.

## Release Stages

| Stage | Trigger | Android | iOS | Jira effect |
| --- | --- | --- | --- | --- |
| `internal` | Push to `main`, or manual run | Upload new AAB to `internal` | Upload new build to TestFlight | Comment linked Jira issue keys when present |
| `release_candidate` | Push to `release/**`, or manual run | Upload new AAB to `GOOGLE_PLAY_RELEASE_CANDIDATE_TRACK` | Upload new build to TestFlight | Comment all issues in the release `fixVersion` and transition them to `JIRA_TEST_STATUS` |
| `external_beta` | Jira automation or manual run after all release issues pass QA | Promote from release-candidate track to `GOOGLE_PLAY_OPEN_BETA_TRACK` | Distribute existing build to TestFlight group `External` | Comment linked Jira issue keys when present |
| `production` | Jira automation after seven days in external beta, or manual run | Promote from `GOOGLE_PLAY_OPEN_BETA_TRACK` to `production` | Submit existing TestFlight build for App Store review and automatic release | Comment linked Jira issue keys when present |

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
- `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`: Password for the `.p12` file. Leave this secret unset if the `.p12` was exported with an empty password.
- `IOS_APPSTORE_PROVISIONING_PROFILE_BASE64`: Base64-encoded App Store provisioning profile for `com.delta.strnadi`.

The `.p8` App Store Connect key cannot be converted into a `.p12`. The `.p12` must come from an Apple Distribution certificate whose private key is available in Keychain Access, or from another secure certificate store already used by the team.

## CI Caching

The workflow caches:

- Flutter pub packages.
- Android Gradle caches.
- Ruby gems through `ruby/setup-ruby`.
- CocoaPods downloads and installed pods.
- iOS Xcode DerivedData for incremental archive builds.

The iOS deploy job uses GitHub's `macos-26` runner so App Store Connect receives an IPA built with the required iOS 26 SDK/Xcode 26 toolchain.

## Optional GitHub Variables

- `IOS_TEAM_ID`: Apple Developer Team ID. Defaults to `3GPTVJHVFN`.
- `FLUTTER_VERSION`: Flutter SDK version. Defaults to `3.41.2`.
- `GOOGLE_PLAY_RELEASE_CANDIDATE_TRACK`: Play Console track for release-candidate builds. Defaults to `GOOGLE_PLAY_CLOSED_TRACK`, then `alpha`.
- `GOOGLE_PLAY_CLOSED_TRACK`: Legacy fallback for the release-candidate track. Defaults to `alpha`.
- `GOOGLE_PLAY_OPEN_BETA_TRACK`: Play Console open testing track. Defaults to `beta`.
- `JIRA_TEST_STATUS`: Jira status used after a release-candidate deploy. Defaults to `To Test`.
- `IOS_USES_NON_EXEMPT_ENCRYPTION`: Set to `true` only if App Store export compliance requires it. Defaults to `false`.

## Jira-Triggered Dispatch

Jira automation can call the deployment workflow with GitHub's workflow dispatch API:

```json
{
  "ref": "release/1.6.0",
  "inputs": {
    "platform": "all",
    "deployment_stage": "external_beta",
    "jira_release_version": "1.6.0"
  }
}
```

For production after a week in external beta, use the same request with `"deployment_stage": "production"`. If App Store Connect should submit a specific processed build, also pass `app_store_build_number`; otherwise Fastlane selects the latest build for the editable app version.

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
bundle exec fastlane promote
```

iOS:

```sh
cd ios
bundle exec fastlane testflight
bundle exec fastlane external_beta
bundle exec fastlane app_store
bundle exec fastlane beta
```
