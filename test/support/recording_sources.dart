import 'dart:io';

/// Supplemental wiring checks; behavioral tests exercise the audio/platform boundaries.
String readRecordingSources() => <String>[
  File('lib/recording/session/recording_controller.dart').readAsStringSync(),
  File('lib/recording/session/recording_capture.dart').readAsStringSync(),
  File('lib/recording/session/recording_runtime.dart').readAsStringSync(),
  File('lib/recording/session/recording_segments.dart').readAsStringSync(),
  File('lib/recording/session/recording_completion.dart').readAsStringSync(),
  File('lib/recording/session/recording_files.dart').readAsStringSync(),
  File('lib/recording/session/recording_location.dart').readAsStringSync(),
  File('lib/recording/session/recording_activity.dart').readAsStringSync(),
  File('lib/recording/widgets/recording_view.dart').readAsStringSync(),
  File('lib/recording/platform/recording_task_handler.dart').readAsStringSync(),
  File(
    'lib/recording/location/recording_location_permission.dart',
  ).readAsStringSync(),
].join('\n');
