# Live Activity view snapshot

Run `sh test/recording/native/check_snapshot.sh` on Apple Silicon with macOS 26+
and Xcode. Use `--update` only after reviewing an intentional layout change.
The checked-in reference was rendered with Xcode 27 / macOS 27; system font or
symbol changes can require reviewing and regenerating it on a newer OS.

This renders the actual SwiftUI controls, row, ring, and timer with fake App
Intents. It covers short/long durations and compact content without opening
Device Hub, recording audio, accessing a database, or calling an API. It is an
offscreen macOS layout regression, not proof of iOS Dynamic Island geometry or
intent execution. The camera cutout and system capsule are managed by iOS.

On a physical iPhone, verify running/paused compact and expanded presentations,
Lock Screen controls, stop while recording, stop while paused, a stop immediately
after pause, and save failure/retry. Stop must open the metadata form with the
complete draft; it must never discard audio or upload automatically. The × is a
session-specific app link: verify it from the Home Screen and Lock Screen, and
verify an old activity cannot finish a new recording. Dart waits for the app to
resume before finishing; Flutter default deep-link routing is disabled because
`app_links` owns this route and the existing authentication links. Resume may
open Strnadi via the existing foreground fallback.
