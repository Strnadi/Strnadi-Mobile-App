import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/Models/recordingPart.dart';

/// Whether a recording may appear in the captured account's private list.
///
/// Local drafts are claimable by the active account. A recording already
/// returned by the backend is private only when the response explicitly names
/// that account; a missing owner remains public/unowned.
bool recordingBelongsToCapturedAccount({
  required bool sent,
  required int? ownerUserId,
  required int capturedUserId,
}) {
  return !sent || ownerUserId == capturedUserId;
}

/// Fields owned by recording metadata editors and backend metadata refreshes.
///
/// Upload state, ownership, local cache state, and durable keys are
/// intentionally absent. Applying this map to a newer persisted row cannot
/// roll back a completed upload from a stale UI snapshot.
Map<String, Object?> recordingMetadataUpdateFields(Recording recording) {
  return <String, Object?>{
    'estimatedBirdsCount': recording.estimatedBirdsCount,
    'device': recording.device,
    'byApp': recording.byApp ? 1 : 0,
    'name': recording.name,
    'note': recording.note,
  };
}

/// Fields owned by recording-part metadata/cache refreshes.
///
/// Backend ids, parent associations, sent/sending state, and the durable
/// upload key are only changed by lease-aware upload or reconciliation code.
Map<String, Object?> recordingPartContentUpdateFields(RecordingPart part) {
  return <String, Object?>{
    'startTime': part.startTime.toString(),
    'endTime': part.endTime.toString(),
    'gpsLatitudeStart': part.gpsLatitudeStart,
    'gpsLatitudeEnd': part.gpsLatitudeEnd,
    'gpsLongitudeStart': part.gpsLongitudeStart,
    'gpsLongitudeEnd': part.gpsLongitudeEnd,
    'square': part.square,
    if (part.path != null && part.path!.isNotEmpty) 'path': part.path,
    'length': part.length,
  };
}

/// Local cache fields for a part whose remote identity is already durable.
///
/// These fields are not part of the multipart metadata. Repository callers
/// still guard this update with a persisted positive backend id and sent flag,
/// so a draft cannot swap its upload source after its first POST.
Map<String, Object?> recordingPartCacheUpdateFields(RecordingPart part) {
  return <String, Object?>{
    'path': part.path,
    'length': part.length,
  };
}
