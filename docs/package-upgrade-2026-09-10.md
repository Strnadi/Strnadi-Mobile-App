# Flutter package upgrade — 2026-09-10

Major dependency constraints and the resolved lockfile are updated together.
The app now requires Flutter 3.44 or newer and Dart 3.12 or newer. Android
uses AGP 9.2.1, Gradle 9.4.1, compile SDK 37, Kotlin 2.3.20 and Java 17
bytecode. Native validation uses JDK 21. Flutter compatibility flags keep
legacy Kotlin and Android DSL support enabled for existing plugins.
Both deployment jobs now default to Flutter 3.44.0. If the repository has a
`FLUTTER_VERSION` variable override, set it to 3.44.0 or newer as well.
No repository-level override was found during this update.

## Migration choices

- `flutter_secure_storage` stays on the 10.3.x release line. Version 10 migrates
  Android data written by version 9; version 11 removes the legacy algorithms
  and cannot safely replace version 9 directly. Keep this migration available
  for users who skip app releases. Device upgrade testing is still required.
- Sentry stays on stable 9.29.0; the 10.0.0 alpha is excluded deliberately.
- Local notifications use the new named initialization and display arguments.
- Android restores app-first Gradle evaluation so Flutter registers the
  extensions required by the new file-picker plugin before it is configured.
- Removed unused native plugin imports from `AppDelegate.swift`. In particular,
  `path_provider_foundation` 2.6 uses Dart/FFI and no longer exposes a native
  module to import. Flutter's generated registrant still registers native
  plugins; explicit imports remain for the APIs AppDelegate calls.
- Record 7 removes its own Android background recording service. This app
  already uses its separate microphone foreground service through
  `flutter_foreground_task`; verify its lifecycle on a device.
- `flutter_markdown` remains discontinued. Replacing it with a different
  package is not included in this version upgrade.

## Required device QA before release

1. Upgrade an installed version using secure storage 9, with an existing
   login and offline recordings. Verify that the login, preferences, account
   scope, drafts and queued recordings remain available. Repeat with another
   account/environment and ensure records cannot cross scopes.
2. Record, pause, resume and stop audio with the screen locked and the app
   backgrounded. Verify microphone notification start/stop and playback of the
   resulting file. Force termination and verify draft recovery.
3. Retry interrupted uploads, including background jobs and app restarts;
   retain local files and backend upload identifiers on ambiguous responses.
4. Check notification delivery in foreground/background, deep-link cold and
   warm starts, Apple sign-in, camera/gallery/file selection and permission
   denial paths on Android and iOS.

Automated tests use mocked API, database and platform boundaries; they do not
prove native storage migration, backend integration or device behavior.

## Automated validation

- Static analysis: no errors; 376 warning/informational diagnostics remain.
  Raising the declared Dart minimum enables additional existing-code lints.
- Full suite: 1,429 passed initially. Two new notification harness failures
  were corrected by registering the Android plugin for its mocked channel.
  Those tests and the update-dialog shader-asset failure pass on focused rerun
  (8 tests). The known localization-key and recording-note golden failures
  remain; both reproduced with the original lockfile before this upgrade.
- Deployment workflow YAML parses; both Flutter version defaults match the
  new SDK minimum. GitHub Actions deployment was not run.
- No live API or SQLite integration tests were introduced.

## Native validation

- Android `assembleDebug`: passed with JDK 21, Gradle 9.4.1 and AGP 9.2.1
  (1,136 tasks; 764 executed, 372 up to date). Native Kotlin/Gradle
  compatibility warnings remain for upstream plugins.

- After `flutter clean`, `flutter build ios --debug --no-codesign
  --dart-define-from-file=build.env.json` passed (Xcode: 105.1 seconds) and
  produced `build/ios/iphoneos/Runner.app`. This verifies the obsolete-import
  fix from a clean Flutter build; signing and device launch remain unverified.
- iOS still uses CocoaPods fallback for `audio_waveforms` and
  `google_maps_flutter_ios`; neither currently supports Swift Package Manager
  according to Flutter's build diagnostics.

## Upstream references

- [Secure storage migration notes](https://pub.dev/packages/flutter_secure_storage/changelog)
- [AGP 9.2 compatibility, including SDK 37 and Gradle 9.4.1](https://developer.android.com/build/releases/agp-9-2-0-release-notes)
- [Flutter's Kotlin compatibility migration](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers)
