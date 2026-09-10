# Repository Guidelines

## Project Structure & Module Organization
- `lib/`: Dart source; key areas include `auth/` (sign-in), `map/` (map UI), `database/` (SQLite layer), `localRecordings/` (offline storage), and `firebase/` (messaging).
- `assets/` and `images/`: static media, localization JSON, and public runtime configuration.
- `test/`: widget and unit tests (`*_test.dart`).
- Platform folders `android/` and `ios/` hold native build configuration; keep signing secrets and server credentials out of tracked files.

## Build, Test, and Development Commands
- `flutter pub get`: install or update Dart dependencies after edits to `pubspec.yaml`.
- `flutter run --dart-define-from-file=build.env.json`: launch the app on a connected device or emulator with hot reload and local build configuration.
- `flutter analyze`: run static analysis using the rules in `analysis_options.yaml`.
- `flutter test`: execute the Dart and widget tests under `test/`.
- `flutter build appbundle --release --dart-define-from-file=build.env.json` / `flutter build ios --release --dart-define-from-file=build.env.json`: produce release binaries with local build configuration.

## Working Tree Safety
- Check `git status` before making changes and preserve unrelated or pre-existing edits.
- Keep changes scoped to the task; do not revert user work or include unrelated generated files.

## Coding Style & Naming Conventions
- Follow Flutter's default 2-space indentation and the lint set in `analysis_options.yaml` (extends `flutter_lints`).
- Run `dart format` on only the Dart files touched by the task before committing; avoid repository-wide formatting churn.
- Prefer `PascalCase` for widgets/classes, `camelCase` for members, and `snake_case.dart` for files. Asset files stay lowercase with hyphens (e.g., `assets/images/map-layer.png`).
- Keep widgets small and composable; extract shared UI into `lib/components/` when multiple features depend on it.

## Localization
- Use `t()` only with stable dotted translation keys such as `map.filters.mapView.title`; never pass user-facing Czech, English, or German copy as the key.
- Add every new translation key to all files under `assets/lang/` in the same nested structure, even when the temporary text matches another language.
- Keep feature strings under the feature namespace (for example `map.buttons.*`, `map.filters.*`, and `user.settings.*`) so missing keys are easy to find and do not fall back to raw display text.

## Testing Guidelines
- Place tests in `test/` mirroring the `lib/` directory structure, with filenames ending in `_test.dart`.
- Always mock API and database boundaries. Use injected fakes, mock HTTP transports, and mocked platform channels; never call live APIs or open real SQLite databases, including in-memory SQLite, in automated tests.
- Test observable behavior and failure paths. Source-string assertions may supplement behavioral tests but do not establish correctness on their own.
- Use `flutter test --coverage` when assessing new features; maintain or improve overall coverage before merging.
- Add widget golden tests for UI changes affecting layout or theming, and document manual QA steps for camera, location, and recording flows in the PR description.
- Report automated checks and device QA separately. Passing mocked tests or a build does not prove live backend integration or on-device recording, background upload, location, and notification behavior; state what remains unverified.

## Recording Data & Session Isolation
- Preserve offline recordings and recovery state. Cover interrupted uploads, retries, and draft recovery when changing recording or upload behavior.
- On ambiguous API responses, retain local recordings and persisted backend upload identifiers; do not clear them or create duplicate uploads to guess at recovery.
- Preserve account and prod/dev/preprod isolation for recordings, caches, notifications, and background jobs. Switching accounts or environments must not move queued recordings into another scope or expose another session's cached data.

## Commit & Pull Request Guidelines
- Write concise, imperative commit messages without prefixes (e.g., `Fix duplicate map markers`). Group related changes to keep history meaningful.
- Each PR should explain the change, list testing performed, reference related issues, and include platform-specific screenshots or screen recordings for UI updates.
- Ensure CI passes (`flutter analyze`, `flutter test`) before requesting review, and flag any required backend or Firebase configuration updates.

## Security & Configuration Tips
- Use an untracked `build.env.json` with `--dart-define-from-file` for local build configuration, following `README.md`; never commit secrets to Git.
- Flutter assets and compiled build-time values ship with the app and cannot protect server secrets. Never bundle secret JSON assets, Firebase service-account credentials, or private server keys; keep server credentials on the backend.
- When sharing recordings or database files, scrub personal data before attaching them to issues or PRs.
