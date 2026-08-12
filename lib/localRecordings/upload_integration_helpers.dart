class BestEffortBatchFailure<T> {
  const BestEffortBatchFailure({
    required this.item,
    required this.error,
    required this.stackTrace,
  });

  final T item;
  final Object error;
  final StackTrace stackTrace;
}

class BestEffortBatchResult<T> {
  const BestEffortBatchResult({
    required this.succeededItems,
    required this.failures,
  });

  final List<T> succeededItems;
  final List<BestEffortBatchFailure<T>> failures;

  bool get succeeded => failures.isEmpty;
}

class BackendIncompleteUploadEntry {
  BackendIncompleteUploadEntry({
    required this.backendRecordingId,
    this.expectedPartsCount,
    this.uploadedPartsCount,
    Set<int>? uploadedBackendPartIds,
  }) : uploadedBackendPartIds = uploadedBackendPartIds == null
            ? null
            : Set<int>.unmodifiable(uploadedBackendPartIds);

  final int backendRecordingId;
  final int? expectedPartsCount;
  final int? uploadedPartsCount;
  final Set<int>? uploadedBackendPartIds;

  bool get hasExactPartCounts =>
      expectedPartsCount != null &&
      expectedPartsCount! > 0 &&
      uploadedPartsCount != null &&
      uploadedPartsCount! >= 0;

  bool get requiresFullPartReconciliation => uploadedBackendPartIds == null;
}

class BackendIncompleteUploadSnapshot {
  const BackendIncompleteUploadSnapshot.unavailable()
      : isAuthoritative = false,
        entriesByRecordingId = const <int, BackendIncompleteUploadEntry>{};

  BackendIncompleteUploadSnapshot.authoritative(
    Iterable<BackendIncompleteUploadEntry> entries,
  )   : isAuthoritative = true,
        entriesByRecordingId =
            Map<int, BackendIncompleteUploadEntry>.unmodifiable(
          <int, BackendIncompleteUploadEntry>{
            for (final BackendIncompleteUploadEntry entry in entries)
              entry.backendRecordingId: entry,
          },
        );

  final bool isAuthoritative;
  final Map<int, BackendIncompleteUploadEntry> entriesByRecordingId;

  BackendIncompleteUploadEntry? entryFor(int? backendRecordingId) {
    if (backendRecordingId == null || backendRecordingId <= 0) return null;
    return entriesByRecordingId[backendRecordingId];
  }

  bool authoritativelyConfirmsComplete(int? backendRecordingId) {
    return isAuthoritative &&
        backendRecordingId != null &&
        backendRecordingId > 0 &&
        !entriesByRecordingId.containsKey(backendRecordingId);
  }
}

BackendIncompleteUploadSnapshot backendIncompleteUploadSnapshotFromResponse({
  required int? statusCode,
  required dynamic payload,
}) {
  if (statusCode == 204) {
    return BackendIncompleteUploadSnapshot.authoritative(
      const <BackendIncompleteUploadEntry>[],
    );
  }
  if (statusCode != 200) {
    return const BackendIncompleteUploadSnapshot.unavailable();
  }

  final Iterable<dynamic> items;
  if (payload is List) {
    items = payload;
  } else if (payload is Map) {
    const List<String> envelopeKeys = <String>[
      'items',
      'recordings',
      'data',
      'incomplete',
    ];
    String? envelopeKey;
    for (final String key in envelopeKeys) {
      if (payload.containsKey(key)) {
        envelopeKey = key;
        break;
      }
    }
    if (envelopeKey == null) {
      items = <dynamic>[payload];
    } else {
      final dynamic nested = payload[envelopeKey];
      if (nested is! List) {
        return const BackendIncompleteUploadSnapshot.unavailable();
      }
      items = nested;
    }
  } else if (payload == null) {
    return const BackendIncompleteUploadSnapshot.unavailable();
  } else {
    items = <dynamic>[payload];
  }

  final List<BackendIncompleteUploadEntry> entries =
      <BackendIncompleteUploadEntry>[];
  for (final dynamic item in items) {
    final BackendIncompleteUploadEntry? entry =
        _parseBackendIncompleteUploadEntry(item);
    if (entry == null) {
      // A successful status with an unrecognized body must not be mistaken
      // for an authoritative empty list, which would hide local warnings.
      return const BackendIncompleteUploadSnapshot.unavailable();
    }
    entries.add(entry);
  }
  return BackendIncompleteUploadSnapshot.authoritative(entries);
}

BackendIncompleteUploadEntry? _parseBackendIncompleteUploadEntry(
  dynamic item,
) {
  if (item is! Map) {
    final int? backendRecordingId = _coerceInt(item);
    if (backendRecordingId == null || backendRecordingId <= 0) return null;
    return BackendIncompleteUploadEntry(
      backendRecordingId: backendRecordingId,
    );
  }

  final Map<String, dynamic> values = <String, dynamic>{
    for (final MapEntry<dynamic, dynamic> entry in item.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
  final int? backendRecordingId = _readInt(values, const <String>[
    'id',
    'BEId',
    'beId',
    'recordingId',
    'recordingBEID',
    'backendRecordingId',
  ]);
  if (backendRecordingId == null || backendRecordingId <= 0) return null;

  final List<dynamic>? parts = _readList(values, const <String>[
    'parts',
    'recordingParts',
    'uploadedParts',
  ]);
  final Set<int>? uploadedBackendPartIds = _parseBackendPartIds(parts);
  final int? uploadedPartsCount = _readInt(values, const <String>[
        'actualPartsCount',
        'uploadedPartsCount',
        'receivedPartsCount',
        'partsCount',
        'uploadedCount',
      ]) ??
      parts?.length;

  return BackendIncompleteUploadEntry(
    backendRecordingId: backendRecordingId,
    expectedPartsCount: _readInt(values, const <String>[
      'expectedPartsCount',
      'expectedPartCount',
      'partCount',
      'expectedCount',
    ]),
    uploadedPartsCount: uploadedPartsCount,
    uploadedBackendPartIds: uploadedBackendPartIds,
  );
}

Set<int>? _parseBackendPartIds(List<dynamic>? parts) {
  if (parts == null) return null;
  final Set<int> ids = <int>{};
  for (final dynamic part in parts) {
    if (part is! Map) return null;
    final Map<String, dynamic> partValues = <String, dynamic>{
      for (final MapEntry<dynamic, dynamic> entry in part.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    final int? id = _readInt(
      partValues,
      const <String>['id', 'BEId', 'beId'],
    );
    if (id == null || id <= 0) return null;
    ids.add(id);
  }
  return ids;
}

int? _readInt(Map<String, dynamic> values, Iterable<String> keys) {
  for (final String key in keys) {
    if (!values.containsKey(key)) continue;
    final int? parsed = _coerceInt(values[key]);
    if (parsed != null) return parsed;
  }
  return null;
}

List<dynamic>? _readList(
  Map<String, dynamic> values,
  Iterable<String> keys,
) {
  for (final String key in keys) {
    final dynamic value = values[key];
    if (value is List) return value;
  }
  return null;
}

int? _coerceInt(dynamic value) {
  if (value is int) return value;
  if (value is num) {
    if (value.isFinite && value == value.truncateToDouble()) {
      return value.toInt();
    }
    return null;
  }
  if (value is String) return int.tryParse(value.trim());
  return null;
}

Future<BestEffortBatchResult<T>> runBestEffortBatch<T>(
  Iterable<T> items,
  Future<void> Function(T item) operation,
) async {
  final List<T> succeededItems = <T>[];
  final List<BestEffortBatchFailure<T>> failures =
      <BestEffortBatchFailure<T>>[];

  for (final T item in items) {
    try {
      await operation(item);
      succeededItems.add(item);
    } catch (error, stackTrace) {
      failures.add(
        BestEffortBatchFailure<T>(
          item: item,
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  return BestEffortBatchResult<T>(
    succeededItems: List<T>.unmodifiable(succeededItems),
    failures: List<BestEffortBatchFailure<T>>.unmodifiable(failures),
  );
}

bool recordingUploadIsActive({
  required bool recordingSending,
  required String? recordingLease,
  required Iterable<bool> partSendingStates,
}) {
  return recordingSending ||
      (recordingLease?.trim().isNotEmpty ?? false) ||
      partSendingStates.any((bool sending) => sending);
}

bool canStartRecordingUpload({
  required bool captureReviewed,
  required bool recordingSent,
  required bool uploadIsActive,
}) {
  return captureReviewed && !recordingSent && !uploadIsActive;
}

bool canResendRecordingParts({
  required bool captureReviewed,
  required bool uploadIsActive,
  required bool hasIdleUnsentParts,
}) {
  return captureReviewed && !uploadIsActive && hasIdleUnsentParts;
}

bool aggregateUploadNeedsAttention({
  required int? backendExpectedPartsCount,
  required int? backendUploadedPartsCount,
  required bool backendSaysIncomplete,
  required bool localSaysIncomplete,
}) {
  final bool backendExplicitlyConfirmsCompletion =
      backendExpectedPartsCount != null &&
          backendExpectedPartsCount > 0 &&
          backendUploadedPartsCount != null &&
          backendUploadedPartsCount >= backendExpectedPartsCount;

  // Backend completion is authoritative for the missing-audio prompt. Local
  // rows can legitimately remain stale after the remote upload committed, and
  // must not produce contradictory messages such as "received 1 of 1".
  if (backendExplicitlyConfirmsCompletion) return false;

  return backendSaysIncomplete || localSaysIncomplete;
}

bool backendMissingPartCountsAreDisplayable({
  required bool hasExactBackendPartCounts,
  required int expectedPartsCount,
  required int uploadedPartsCount,
}) {
  return hasExactBackendPartCounts &&
      expectedPartsCount > 0 &&
      uploadedPartsCount >= 0 &&
      uploadedPartsCount < expectedPartsCount;
}

bool incompleteAggregateCanBeRetried({
  required int localPartsCount,
  required int expectedPartsCount,
}) {
  return expectedPartsCount > 0 && localPartsCount == expectedPartsCount;
}

bool localPartCountsAsUploaded({
  required bool sent,
  required int? backendPartId,
  required int? backendRecordingId,
  required int? expectedBackendRecordingId,
}) {
  return sent &&
      backendPartId != null &&
      backendPartId > 0 &&
      expectedBackendRecordingId != null &&
      expectedBackendRecordingId > 0 &&
      backendRecordingId == expectedBackendRecordingId;
}

bool incompletePartCanBeRetried({
  required bool sent,
  required bool sending,
  required int? backendPartId,
  required String? localPath,
  required Set<int>? uploadedBackendPartIds,
  required bool reconcileAllBackendParts,
}) {
  if (sending) return false;

  final bool hasLocalFile = localPath?.trim().isNotEmpty ?? false;
  final bool hasBackendPartId = backendPartId != null && backendPartId > 0;
  if (reconcileAllBackendParts) {
    // An ID-only incomplete-recording response proves that the aggregate needs
    // repair but does not identify which part is missing. Reconcile every idle
    // remembered backend part; local audio is required only when no backend id
    // exists for the aggregate service to query.
    return hasBackendPartId || hasLocalFile;
  }
  if (!sent) {
    // A retained backend id is intentionally ambiguous: the aggregate service
    // can reconcile it without a local file and asks for the file only if the
    // backend proves that id absent.
    return hasBackendPartId || hasLocalFile;
  }

  final bool backendProvesMissing = backendPartId != null &&
      uploadedBackendPartIds != null &&
      !uploadedBackendPartIds.contains(backendPartId);
  // When discovery already proved the remote part missing, a local file is
  // required to repair it; another existence lookup cannot recover the audio.
  return backendProvesMissing && hasLocalFile;
}
