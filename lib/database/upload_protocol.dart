import 'dart:convert';

import 'package:strnadi/database/recording_upload_service.dart';
import 'package:strnadi/exceptions.dart';

int readPositiveUploadResponseId(
  dynamic data, {
  required String entity,
  List<String> mapKeys = const <String>['id', 'data'],
}) {
  dynamic value = data;
  for (int depth = 0; depth < 4; depth++) {
    if (value is String) {
      final String trimmed = value.trim();
      try {
        value = jsonDecode(trimmed);
      } on FormatException {
        value = int.tryParse(trimmed);
      }
      continue;
    }
    if (value is Map) {
      dynamic nested;
      for (final String key in mapKeys) {
        if (value.containsKey(key)) {
          nested = value[key];
          break;
        }
      }
      value = nested;
      continue;
    }
    break;
  }

  final int? id = value is int
      ? value
      : value is num && value.isFinite && value == value.truncate()
          ? value.toInt()
          : int.tryParse('$value');
  if (id == null || id <= 0) {
    throw UploadException(
      'Backend returned an invalid $entity id.',
      502,
    );
  }
  return id;
}

/// Validates a `GET /recordings/{id}?parts=true` response and reports whether
/// it contains [expectedPartId].
///
/// A `false` result is safe for upload reconciliation only after the complete
/// parent payload has been proven internally consistent. Any malformed or
/// ambiguous response throws so callers retain the locally persisted backend
/// part id instead of issuing a duplicate POST.
bool recordingPayloadConfirmsPartExists(
  dynamic payload, {
  required int expectedRecordingId,
  required int expectedPartId,
}) {
  if (expectedRecordingId <= 0 || expectedPartId <= 0) {
    throw const RecordingUploadValidationException(
      'Recording-part reconciliation requires valid backend identities.',
    );
  }

  dynamic decoded = payload;
  if (decoded is String) {
    try {
      decoded = jsonDecode(decoded);
    } on FormatException {
      throw UploadException(
        'Backend returned malformed recording details.',
        502,
      );
    }
  }
  if (decoded is! Map) {
    throw UploadException(
      'Backend returned malformed recording details.',
      502,
    );
  }

  final int? parentId = _strictPositiveJsonInt(decoded['id']);
  if (parentId == null || parentId != expectedRecordingId) {
    throw UploadException(
      'Backend returned mismatched recording details.',
      502,
    );
  }
  if (!decoded.containsKey('parts') || decoded['parts'] is! List) {
    throw UploadException(
      'Backend omitted recording parts during reconciliation.',
      502,
    );
  }

  final Set<int> partIds = <int>{};
  for (final dynamic rawPart in decoded['parts'] as List) {
    if (rawPart is! Map) {
      throw UploadException(
        'Backend returned a malformed recording part.',
        502,
      );
    }
    final int? partId = _strictPositiveJsonInt(rawPart['id']);
    final int? partRecordingId = _strictPositiveJsonInt(rawPart['recordingId']);
    if (partId == null ||
        partRecordingId == null ||
        partRecordingId != expectedRecordingId ||
        !partIds.add(partId)) {
      throw UploadException(
        'Backend returned ambiguous recording parts.',
        502,
      );
    }
  }

  return partIds.contains(expectedPartId);
}

int? _strictPositiveJsonInt(dynamic value) {
  if (value is int) return value > 0 ? value : null;
  if (value is num &&
      value.isFinite &&
      value == value.truncateToDouble() &&
      value > 0) {
    return value.toInt();
  }
  return null;
}

String dialectUploadIdempotencyKey({
  required String recordingUploadKey,
  required String dialectUploadKey,
}) {
  final String recordingKey = recordingUploadKey.trim();
  final String dialectKey = dialectUploadKey.trim();
  if (recordingKey.isEmpty || dialectKey.isEmpty) {
    throw const RecordingUploadValidationException(
      'Dialect upload requires durable entity keys.',
    );
  }
  return 'recording-dialect:$recordingKey:$dialectKey';
}

/// Freezes a dialect request before its first POST and revalidates the exact
/// workflow session after the marker write.
///
/// [post] receives the same renewal callback so the transport can invoke it
/// immediately before both the initial request and a redirect replay.
Future<T> runDialectUploadAttempt<T>({
  required bool uploadAttempted,
  required Future<void> Function() persistAttemptMarker,
  required void Function() markAttemptedInMemory,
  required Future<void> Function() renew,
  required Future<T> Function(Future<void> Function() beforePost) post,
}) async {
  if (!uploadAttempted) {
    await persistAttemptMarker();
    markAttemptedInMemory();
  }

  // Marker persistence is an await boundary. The account, environment, or
  // logical login can change while the durable write is in flight.
  await renew();
  return post(renew);
}

void validatePersistedDialectBackendAssociation({
  required int backendDialectId,
  required int? backendRecordingId,
  required int expectedBackendRecordingId,
}) {
  if (backendDialectId <= 0) {
    throw const RecordingUploadValidationException(
      'A persisted dialect has an invalid backend id.',
    );
  }
  if (expectedBackendRecordingId <= 0 ||
      backendRecordingId == null ||
      backendRecordingId <= 0 ||
      backendRecordingId != expectedBackendRecordingId) {
    throw const RecordingUploadValidationException(
      'A persisted dialect belongs to a different backend recording.',
    );
  }
}

void validateDialectUploadRequest(Map<String, dynamic> body) {
  final dynamic rawRecordingId = body['recordingId'];
  final int? recordingId = rawRecordingId is int
      ? rawRecordingId
      : rawRecordingId is num &&
              rawRecordingId.isFinite &&
              rawRecordingId == rawRecordingId.truncate()
          ? rawRecordingId.toInt()
          : null;
  if (recordingId == null || recordingId <= 0) {
    throw const RecordingUploadValidationException(
      'A dialect upload requires a valid backend recording id.',
    );
  }

  final dynamic rawDialectCode = body['dialectCode'];
  if (rawDialectCode is! String || rawDialectCode.trim().isEmpty) {
    throw const RecordingUploadValidationException(
      'A dialect upload requires a dialect code.',
    );
  }

  final dynamic rawStartDate = body['startDate'];
  final dynamic rawEndDate = body['endDate'];
  final DateTime? startDate =
      rawStartDate is String ? DateTime.tryParse(rawStartDate.trim()) : null;
  final DateTime? endDate =
      rawEndDate is String ? DateTime.tryParse(rawEndDate.trim()) : null;
  if (startDate == null || endDate == null || !startDate.isBefore(endDate)) {
    throw const RecordingUploadValidationException(
      'A dialect upload requires a valid positive time range.',
    );
  }
}

bool isRetryableRecordingUploadFailure(Object error) {
  if (error is RecordingUploadSessionChangedException) return true;
  if (error is RecordingUploadValidationException) return false;
  if (error is UploadException) {
    return error.statusCode == 401 ||
        error.statusCode == 408 ||
        error.statusCode == 409 ||
        error.statusCode == 425 ||
        error.statusCode == 429 ||
        error.statusCode >= 500;
  }
  if (error is FetchException) {
    return error.statusCode == 401 ||
        error.statusCode == 408 ||
        error.statusCode == 429 ||
        error.statusCode >= 500;
  }
  // Database, plugin, and transport failures are transient unless a more
  // specific type above proves the operation is permanently invalid.
  return true;
}
