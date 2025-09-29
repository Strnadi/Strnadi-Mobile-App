# Návrat krále

Návrat krále is a Flutter app for field ornithologists who document dialect variations of the corn bunting (“strnad”). It combines high-fidelity audio capture, location-aware metadata, and collaborative tooling so that researchers can build a shared dialect atlas while working offline or online.【F:docs/overview.md†L1-L23】

## Quick start
1. Install Flutter 3.3+ and clone the repository:
   ```bash
   git clone https://github.com/Strnadi/Strnadi-Mobile-App.git
   cd Strnadi-Mobile-App
   flutter pub get
   ```
2. Provide Firebase configuration (via `flutterfire configure`) and add the generated platform files under `android/` and `ios/`.
3. Run the app on a simulator or device:
   ```bash
   flutter run
   ```
4. On first launch, grant microphone and notification permissions when prompted by the in-app permission gate.【F:docs/development.md†L15-L44】

## Key capabilities
- Guided audio capture with spectrogram previews and metadata forms for segment annotations.【F:docs/overview.md†L7-L12】【F:docs/architecture.md†L17-L36】
- Interactive maps that reveal dialect distribution, filters, and drill-down recording detail pages.【F:docs/overview.md†L12-L16】【F:docs/architecture.md†L37-L47】
- Offline-first storage with background upload, notifications, and Firebase-powered messaging to keep teams in sync.【F:docs/overview.md†L13-L21】【F:docs/data-pipeline.md†L5-L40】

## Documentation
- [Project overview](docs/overview.md)
- [Development setup](docs/development.md)
- [Architecture guide](docs/architecture.md)
- [Data & synchronisation pipeline](docs/data-pipeline.md)

## Contributing
We welcome bug reports, feature ideas, and pull requests. Please ensure linting and tests pass before submitting changes.【F:docs/development.md†L47-L71】

## License
This project is distributed under the terms of the GNU General Public License v3.0 or later. See [`LICENSE`](LICENSE) for details.【F:LICENSE†L1-L190】
