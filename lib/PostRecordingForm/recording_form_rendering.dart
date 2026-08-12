import 'package:strnadi/database/Models/recordingPart.dart';

/// Returns the first converted recording part without assuming the conversion
/// produced at least one row.
RecordingPart? firstRecordingPartOrNull(List<RecordingPart> parts) {
  return parts.isEmpty ? null : parts.first;
}
