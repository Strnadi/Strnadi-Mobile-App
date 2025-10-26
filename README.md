# Nářečí českých strnadů (Czech Yellowhammer Dialects)

<div align="center">
  <img src="assets/images/logo.png" alt="Project Logo" width="200"/>
</div>

## Overview

**Nářečí českých strnadů** (Czech Yellowhammer Dialects) is a citizen science mobile application built with Flutter for iOS and Android. The app enables users to participate in ornithological research by recording and documenting the songs of the Yellowhammer (*Emberiza citrinella*), a bird species known for its fascinating regional dialect variations.

This project builds upon the successful 2011-2016 citizen science initiative that mapped Yellowhammer dialects across the Czech Republic, making it one of the most comprehensively studied regions for bird dialects worldwide. The app helps researchers understand how bird dialects evolve, spread, and respond to environmental changes.

### Project Website
For more information, visit [strnadi.cz](https://www.strnadi.cz)

## Features

### 🎙️ Recording & Data Collection
- **High-Quality Audio Recording**: Record bird songs with foreground service support for long recording sessions
- **Automatic Geolocation**: GPS coordinates are automatically captured with each recording
- **Offline Support**: Recordings are saved locally and synced when internet connection is available
- **Background Recording**: Continue recording even when the app is in the background
- **WAV Format**: High-quality PCM 16-bit audio at 48kHz sample rate

### 🗺️ Interactive Map
- **Visualization**: View all recorded Yellowhammer songs on an interactive map
- **Multiple Map Views**: Switch between standard and satellite views (powered by OpenStreetMap and Mapy.cz)
- **Dialect Filtering**: Filter recordings by dialect type and verification status
- **Location Tracking**: Real-time user location display
- **Recording Details**: Tap markers to view recording details, listen to audio, and see dialect classifications

### 👤 User Management
- **Authentication**: Secure user registration and login with email/password
- **Social Login**: Sign in with Google or Apple accounts
- **Profile Management**: Update personal information and preferences
- **Recording History**: View and manage your personal recordings

### 📊 Data Management
- **Local Database**: SQLite-based storage for offline access
- **Cloud Sync**: Automatic synchronization with backend server
- **Smart Upload**: Configure Wi-Fi-only or mobile data usage for uploads
- **Background Tasks**: Automatic sync using WorkManager

### 🔔 Notifications
- **Firebase Cloud Messaging**: Receive updates about the project
- **Local Notifications**: Recording reminders and status updates

### 🌍 Localization
- **Czech Language**: Full Czech language support with JSON-based localization system
- **In-App Documentation**: Guide for recording best practices and project information

### 🔒 Privacy & Security
- **Secure Storage**: Sensitive data encrypted using Flutter Secure Storage
- **GDPR Compliant**: Full privacy policy and data protection measures
- **Terms of Service**: Clear terms of use and data handling policies

## Tech Stack

### Framework & Language
- **Flutter** 3.3.0+
- **Dart** SDK >=3.3.0 <4.0.0

### Key Dependencies
- **Recording**: `record`, `audioplayers`, `just_audio`, `audio_waveforms`
- **Maps**: `flutter_map`, `latlong2`, `geolocator`, `flutter_map_location_marker`
- **Database**: `sqflite`, `flutter_secure_storage`
- **Authentication**: `firebase_auth`, `google_sign_in`, `sign_in_with_apple`
- **Backend Communication**: `http`, `jwt_decoder`
- **Background Processing**: `workmanager`, `flutter_foreground_task`
- **Error Tracking**: `sentry_flutter`
- **Analytics**: `posthog_flutter`
- **UI Components**: `flutter_markdown`, `webview_flutter`, `image_picker`

### Backend Integration
- Custom REST API backend
- Firebase Cloud Messaging for push notifications
- Server health monitoring with maintenance mode support

## Installation

### Prerequisites
- Flutter SDK 3.3.0 or higher
- Dart SDK 3.3.0 or higher
- iOS 13.0+ or Android SDK 21+ (Android 5.0+)
- Xcode (for iOS development)
- Android Studio (for Android development)

### Setup

1. **Clone the repository**:
   ```sh
   git clone https://github.com/Strnadi/Strnadi-Mobile-App.git
   cd Strnadi-Mobile-App
   ```

2. **Install dependencies**:
   ```sh
   flutter pub get
   ```

3. **Configure credentials** (for development):
   - Create `assets/secrets.json` with your API credentials
   - Create `assets/firebase-secrets.json` with Firebase configuration
   - See documentation for required configuration keys

4. **Run the app**:
   ```sh
   flutter run
   ```

### Build for Production

#### Android
```sh
flutter build appbundle --release
```

#### iOS
```sh
flutter build ios --release
```

The project includes GitHub Actions workflows for automated builds and TestFlight deployment.

## Usage

### For Contributors (Citizen Scientists)

1. **Register**: Create an account with your email or use Google/Apple sign-in
2. **Grant Permissions**: Allow microphone and location access when prompted
3. **Find a Yellowhammer**: Look for singing male Yellowhammers (typically from early spring to mid-summer)
4. **Record**: 
   - Tap the record button to start capturing
   - Record for at least 5 minutes to capture the complete repertoire
   - Get as close as safely possible to the bird (even a few meters)
   - The app will automatically save GPS coordinates
5. **Submit**: Recordings are automatically uploaded when you have internet connection
6. **Explore**: View all recordings on the interactive map
7. **Track Progress**: See your contributions in your profile

### Recording Tips
- Record in continuous sessions of several minutes
- Try to capture the complete dialect phrase at the end of the song
- Note if multiple birds are singing (you can comment vocally during recording)
- Longer recordings are more valuable for research
- Record anywhere in the Czech Republic

## Project Structure

```
lib/
├── auth/              # Authentication & user registration
├── config/            # Configuration management
├── database/          # SQLite database layer
├── dialects/          # Dialect classification logic
├── firebase/          # Firebase integration
├── localization/      # Multi-language support
├── localRecordings/   # Local recording management
├── map/               # Interactive map features
├── notificationPage/  # Notification handling
├── PostRecordingForm/ # Recording metadata forms
├── recording/         # Audio recording functionality
├── user/              # User profile & settings
└── widgets/           # Reusable UI components
```

## Contributing

We welcome contributions from developers, ornithologists, and citizen scientists! Please read our [Contributing Guidelines](CONTRIBUTING.md) for details on:
- Code style and standards
- How to submit pull requests
- Bug reporting guidelines
- Feature request process

### Areas for Contribution
- Bug fixes and performance improvements
- UI/UX enhancements
- Documentation improvements
- New language translations
- Testing and quality assurance

## Development

### Code Style
- Follow Flutter/Dart best practices
- Use `dart format` before committing
- Write meaningful commit messages
- Add comments for complex logic

### Testing
```sh
flutter test
```

## Scientific Background

The Yellowhammer (*Emberiza citrinella*) is a bird species with relatively simple but fascinating songs. Each individual sings a unique song, but the terminal phrase of the song is shared among birds in a particular region—these birds have dialects.

The 2011-2016 project revealed that the Czech Republic is exceptionally rich in Yellowhammer dialects and helped map nearly the entire country. Several unusual local dialects were discovered that differ from common European dialects.

Understanding dialect distribution helps researchers answer fundamental questions about animal culture:
- How do dialects originate and what maintains them?
- How do birds respond to environmental changes?
- Are dialect boundaries stable over time?
- Do unique local dialects expand or disappear?

## Research Publications

- Diblíková et al. (2019) - *Ibis*
- Diblíková et al. (2023) - *Avian Research*
- Articles in *Živa* and *Ptačí svět*
- Featured in Czech Television's *Snist hada*

## Privacy & Data

- All recordings are stored on secure servers
- Your name and nickname are part of the scientific record
- Open data may be downloaded and redistributed by third parties
- Full privacy policy available at [strnadi.cz/ochrana-osobnich-udaju](https://www.strnadi.cz/ochrana-osobnich-udaju)
- See [Terms of Service](assets/docs/terms-of-services.md) and [GDPR Policy](assets/docs/gdpr.md)

## License

This project is licensed under the **GNU General Public License v3.0 or later** (GPL-3.0-or-later).

Copyright © 2025 Marian Pecqueur & Jan Drobílek

See the [LICENSE](LICENSE) file for full license text.

## Project Partners

- **Univerzita Karlova** (Charles University)
- **Česká společnost ornitologická** (Czech Society for Ornithology)
- **DELTA – Střední škola informatiky a ekonomie**

## Support & Contact

- **Website**: [strnadi.cz](https://www.strnadi.cz)
- **Issues**: [GitHub Issues](https://github.com/Strnadi/Strnadi-Mobile-App/issues)
- **Documentation**: See `assets/docs/` for in-app guides

## Acknowledgments

Thank you to all citizen scientists who contribute recordings and help advance our understanding of bird dialects and animal culture!

---

*Strnad obecný zpívá jednoduše, ale zajímavě. Pojďte nám pomoci zmapovat nářečí českých strnadů!*



