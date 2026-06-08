# Mobile Deployment

GitHub Actions deploys the Flutter app with Fastlane from `.github/workflows/deploy.yml`.

## Behavior

- Pushes to `main` run the `internal` stage: Android is uploaded to the Google Play `internal` track and iOS is uploaded to the TestFlight `closed_beta` group.
- Pushes to `release/**` also run the `internal` stage: Android is uploaded to the Google Play `internal` track and iOS is uploaded to the TestFlight `closed_beta` group for tester validation.
- Manual or Jira `external_beta` runs promote Android from the Google Play `internal` track to the open testing track and distribute the already uploaded TestFlight build to the `open_beta` group.
- Manual `production` runs promote Android from open testing to production and submit the latest TestFlight build for App Store review with automatic release after approval.
- Manual runs support `all`, `ios`, or `android`.
- Manual Android runs can override `play_track`, but normal release automation derives it from the selected deployment stage.
- `build_number` defaults to the GitHub Actions run number so Android `versionCode` and iOS `CFBundleVersion` stay numeric.
- On `release/**` internal or release-candidate builds, `build_name` is derived from the release branch name and `pubspec.yaml` is automatically synced and committed before deployment.
- Outside release-candidate builds, `build_name` defaults to the version before `+` in `pubspec.yaml`.
- Both platforms build with `--dart-define-from-file=build.env.json`.

## Automatic Build Triggers

The repository currently starts mobile deployment builds automatically in these cases:

| Trigger | Workflow | What runs | Builds a new app binary? |
| --- | --- | --- | --- |
| Push to `main` | `Deploy Mobile Apps` | `internal` stage for Android and iOS | Yes |
| Push to `release/**` | `Deploy Mobile Apps` | `internal` stage for Android and iOS | Yes |
| Manual GitHub workflow dispatch with `deployment_stage = internal` | `Deploy Mobile Apps` | Internal Android/iOS deployment for selected platform(s) | Yes |
| Manual or Jira workflow dispatch with `deployment_stage = release_candidate` | `Deploy Mobile Apps` | Release-candidate Android/iOS deployment for selected platform(s) | Yes |
| Manual or Jira workflow dispatch with `deployment_stage = external_beta` | `Deploy Mobile Apps` | Android track promotion and TestFlight `open_beta` distribution | No, promotes/distributes an existing build |
| Manual or Jira workflow dispatch with `deployment_stage = production` | `Deploy Mobile Apps` | Android production promotion and App Store submission | No, promotes/submits an existing build |

Other automatic workflows:

| Trigger | Workflow | Purpose |
| --- | --- | --- |
| Pull request opened/edited/synchronized/reopened/ready for review | `Branch and Jira Policy` | Validates branch/Jira naming and comments Jira on PR open/reopen/ready. It does not build the app. |
| Push to `feature/**` or `release/**` | `Branch and Jira Policy` | Validates branch naming. It does not build the app. |
| GitHub Release published | `Update JSON on Release` | Updates the external APK download JSON over SSH. It does not build the app. |

## Release Version Sync

Before an `internal` or `release_candidate` deployment from a `release/**` branch, the workflow runs `.github/scripts/sync-pubspec-version.sh`.

The script derives the app version from the branch name:

- `release/1.7.0` -> `1.7.0`
- `release/APP-123-1.7.0` -> `1.7.0`

It then rewrites `pubspec.yaml` to:

```yaml
version: 1.7.0+1.7.0
```

If `pubspec.yaml` changed, the workflow commits the update back to the release branch with a commit like:

```text
Sync pubspec version to 1.7.0 [skip ci]
```

The Android and iOS deploy jobs then check out that synced commit and set `BUILD_NAME` to the derived release version, so Android `versionName` and iOS `CFBundleShortVersionString` match the release branch. `BUILD_NUMBER` still comes from GitHub Actions run number unless manually overridden.

## Release Stages

| Stage | Trigger | Android | iOS | Jira effect |
| --- | --- | --- | --- | --- |
| `internal` | Push to `main`, push to `release/**`, or manual run | Upload new AAB to `internal` | Upload new build to TestFlight group `closed_beta` | Comment linked Jira issue keys when present |
| `release_candidate` | Manual or Jira dispatch only | Upload new AAB to `GOOGLE_PLAY_RELEASE_CANDIDATE_TRACK` | Upload new build to TestFlight group `closed_beta` | Comment all issues in the release `fixVersion` and transition them to `JIRA_TEST_STATUS` |
| `external_beta` | Jira version release automation or manual run after testers approve the version | Promote from `internal` to `GOOGLE_PLAY_OPEN_BETA_TRACK` | Distribute existing build to TestFlight group `open_beta` | Comment linked Jira issue keys when present |
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
- `TESTFLIGHT_CLOSED_BETA_GROUPS`: Comma-separated TestFlight groups for new internal and release-candidate iOS builds. Defaults to `closed_beta`.
- `TESTFLIGHT_OPEN_BETA_GROUPS`: Comma-separated TestFlight groups for Open Beta distribution. Defaults to `open_beta`; manual workflow input `testflight_groups` can override it for one run.
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
