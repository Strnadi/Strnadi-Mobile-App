# Návrat krále – Project Overview

Návrat krále is a field-research companion app that helps ornithologists and citizen scientists record, classify, and analyse dialect variations of the corn bunting (*Emberiza calandra*, "strnad") across Central Europe. The Flutter app consolidates audio recording, metadata management, and exploratory tooling so that the team can build a shared dialect corpus while working both on- and offline.

## Core capabilities
- **Guided audio capture** – Recordings can be captured in-app with automatic geolocation, device metadata, and segment-level annotations stored alongside the waveform for later labelling.【F:lib/recording/streamRec.dart†L1-L120】【F:assets/databaseScheme.sql†L1-L22】
- **Dialect intelligence** – Detected dialects and playback previews are available from the dialect detail screens, combining local inference with server-provided models.【F:lib/dialects/ModelHandler.dart†L1-L120】【F:lib/PostRecordingForm/addDialect.dart†L1-L120】
- **Interactive mapping** – Map tiles expose the spatial distribution of dialects and individual observations, drawing from the synchronised database of uploaded recordings.【F:lib/map/mapv2.dart†L1-L160】【F:lib/map/RecordingPage.dart†L1-L120】
- **Background synchronisation** – Offline-first data is periodically uploaded and refreshed through `Workmanager` jobs and a persistent foreground service to keep notifications, auth, and data in sync.【F:lib/main.dart†L84-L151】【F:lib/database/databaseNew.dart†L18-L120】
- **Secure accounts & telemetry** – Firebase Authentication, Sentry crash reporting, and PostHog analytics are pre-integrated for monitoring real-world deployments.【F:lib/auth/authorizator.dart†L1-L160】【F:lib/main.dart†L29-L112】【F:pubspec.yaml†L39-L108】

## Technology stack
- **Framework**: Flutter (Dart SDK ≥ 3.3) targeting Android and iOS clients.【F:pubspec.yaml†L16-L28】
- **Backend services**: Firebase (Authentication, Cloud Messaging), bespoke REST APIs configured via `assets/config.json`, and Google Play Services on Android.【F:lib/main.dart†L52-L119】【F:lib/config/config.dart†L1-L160】
- **Data layer**: SQLite (via `sqflite`) for offline caching, with audio stored in the application documents directory, and Firebase Cloud Messaging tokens persisted for push updates.【F:lib/database/databaseNew.dart†L18-L120】【F:assets/databaseScheme.sql†L1-L22】
- **Analytics & observability**: Sentry for crash analytics, PostHog for product instrumentation, and structured logging via the `logger` package.【F:lib/main.dart†L29-L94】【F:pubspec.yaml†L75-L108】

## Project structure
```
lib/
  auth/              → Authentication flows (login, registration, password reset)
  recording/         → Audio capture, waveform utilities, WAV exports
  database/          → Local persistence, synchronisation, notification hooks
  map/               → Map rendering and observation overlays
  localization/      → JSON-driven translations and string lookup helper
  widgets/           → Shared UI building blocks (buttons, cards, etc.)
  assets/
    config.json        → Sample runtime configuration used when crafting `assets/secrets.json`
    databaseScheme.sql → Canonical SQLite schema used for local caching
    lang/              → Translation JSON files flattened by `Localization`
```

## Additional resources
- [Development setup](./development.md)
- [Architecture guide](./architecture.md)
- [Data & synchronisation](./data-pipeline.md)

