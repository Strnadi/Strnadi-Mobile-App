# Recording

Start at `screens/recording_screen.dart`. `LiveRec` creates one
`RecordingController`, listens to its changes, passes values and callbacks to
`RecordingView`, and disposes the controller when the route leaves.

## Where to make changes

| Responsibility | Location |
| --- | --- |
| Layout, labels, timer display, enabled controls | `widgets/recording_view.dart` |
| Informational dialogs | `widgets/recording_dialogs.dart` |
| Session state, initialization, disposal, public actions | `session/recording_controller.dart` |
| Start, pause, resume, native recorder state changes | `session/recording_capture.dart` |
| PCM drain barrier and segment finalization | `session/recording_segments.dart` |
| Finish, durable draft handoff, exit/discard confirmation | `session/recording_completion.dart` |
| Foreground service entry, notification updates, runtime shutdown | `session/recording_runtime.dart` |
| Temporary file ownership, unique paths, failed-start cleanup | `session/recording_files.dart` |
| Segment location metadata and route points | `session/recording_location.dart` |
| Serialized Live Activity updates and incoming actions | `session/recording_activity.dart` |
| Stopwatch and periodic ticks | `session/elapsed_timer.dart` |
| PCM defaults and native audio configuration | `audio/recording_audio_settings.dart` |
| Streaming capture and exclusive raw-file reservation | `audio/raw_pcm_capture.dart` |
| WAV headers, parsing, streaming writes and file boundary | `audio/wav/` |
| Location permission and subscription boundaries | `location/` |
| Android service and iOS Live Activity adapters | `platform/` |

The controller's parts share private session state intentionally: start, stop,
interruptions, finalization and cleanup must agree on the same operation guards
and file ownership. They are not independent controllers. Audio/file operations,
platform adapters, and presentation are separate libraries. Use the controller's
public actions and read-only view getters from the screen.

## Recovery invariants

- Pause/finalize stops native capture, drains PCM, writes a separate WAV, commits
  segment metadata, and only then removes the raw input. A failed finalization
  keeps the original input available for retry.
- Resume finalizes any interrupted segment before creating another segment.
- Finish persists a draft before opening the metadata form. An ambiguously
  acknowledged save keeps its files and cannot be blindly retried or discarded.
- Foreground shutdown must succeed before destructive discard cleanup.
- Live Activity operations remain serialized and ancillary to audio capture.
- The controller rejects UI updates after disposal; asynchronous runtime cleanup
  still completes and releases the recorder.

The existing `streamRec.*` translation keys and `LiveRec` widget name are retained
so this file reorganization does not change translations or route callers.

## Verification

Run `flutter test test/recording test/navigation test/location test/localization`
for focused behavior and wiring checks. PCM/WAV and service tests use fakes;
settings tests mock the native channel; presentation tests render in guest mode
without API or database access. Source contracts are supplemental wiring checks.

Device QA is separate: start/pause/resume/finish, interrupted capture, discard and
navigation, location loss, Android foreground notifications, and iOS Live
Activity controls should be exercised on physical devices.
