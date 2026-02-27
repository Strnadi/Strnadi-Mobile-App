# Repository Guidelines

## Project Structure & Module Organization
- `lib/`: Dart source; key areas include `auth/` (sign-in), `map/` (map UI), `database/` (SQLite layer), `localRecordings/` (offline storage), and `firebase/` (messaging).
- `assets/` and `images/`: static media, localization JSON, and runtime secrets templates.
- `test/`: widget and unit tests (`*_test.dart`).
- Platform folders `android/` and `ios/` hold native configuration for builds and store platform-specific secrets.

## Build, Test, and Development Commands
- `flutter pub get`: install or update Dart dependencies after edits to `pubspec.yaml`.
- `flutter run --flavor development`: launch the app on a connected device or emulator with hot reload.
- `flutter analyze`: run static analysis using the rules in `analysis_options.yaml`.
- `flutter test`: execute the Dart and widget tests under `test/`.
- `flutter build appbundle --release` / `flutter build ios --release`: produce release binaries for publishing.

## Coding Style & Naming Conventions
- Follow Flutter's default 2-space indentation and the lint set in `analysis_options.yaml` (extends `flutter_lints`).
- Use `dart format lib test` before committing to keep code style consistent.
- Prefer `PascalCase` for widgets/classes, `camelCase` for members, and `snake_case.dart` for files. Asset files stay lowercase with hyphens (e.g., `assets/images/map-layer.png`).
- Keep widgets small and composable; extract shared UI into `lib/components/` when multiple features depend on it.

## Testing Guidelines
- Place tests in `test/` mirroring the `lib/` directory structure, with filenames ending in `_test.dart`.
- Use `flutter test --coverage` when assessing new features; maintain or improve overall coverage before merging.
- Add widget golden tests for UI changes affecting layout or theming, and document manual QA steps for camera, location, and recording flows in the PR description.

## Commit & Pull Request Guidelines
- Write concise, imperative commit messages without prefixes (e.g., `Fix duplicate map markers`). Group related changes to keep history meaningful.
- Each PR should explain the change, list testing performed, reference related issues, and include platform-specific screenshots or screen recordings for UI updates.
- Ensure CI passes (`flutter analyze`, `flutter test`) before requesting review, and flag any required backend or Firebase configuration updates.

## Security & Configuration Tips
- Store API and Firebase credentials in untracked files such as `assets/secrets.json`; never commit secrets to git.
- When sharing recordings or database files, scrub personal data before attaching them to issues or PRs.
