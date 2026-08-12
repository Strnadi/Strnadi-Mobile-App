String _firstNonEmpty(Iterable<Object?> values, {required String fallback}) {
  for (final Object? value in values) {
    final String text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;
  }
  return fallback;
}

int _notificationType(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  return int.tryParse(value?.toString().trim() ?? '') ?? 0;
}

const int notificationHistoryRetentionLimit = 500;

String? normalizeNotificationProviderMessageId(Object? value) {
  final String normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

class NotificationRetentionDeletePlan {
  const NotificationRetentionDeletePlan({
    required this.where,
    required this.whereArgs,
  });

  final String where;
  final List<Object?> whereArgs;
}

/// Builds the owner/environment-scoped pruning predicate used after inserts.
///
/// Keeping the SQL and bindings in a pure value makes the security boundary
/// testable without opening SQLite.
NotificationRetentionDeletePlan notificationRetentionDeletePlan({
  required String ownerUserId,
  required String environment,
  int limit = notificationHistoryRetentionLimit,
}) {
  final String normalizedOwnerUserId = ownerUserId.trim();
  final String normalizedEnvironment = environment.trim();
  final int? numericOwnerUserId = int.tryParse(normalizedOwnerUserId);
  if (numericOwnerUserId == null || numericOwnerUserId <= 0) {
    throw ArgumentError.value(ownerUserId, 'ownerUserId');
  }
  if (normalizedEnvironment.isEmpty) {
    throw ArgumentError.value(environment, 'environment');
  }
  if (limit <= 0) {
    throw RangeError.range(limit, 1, null, 'limit');
  }

  return NotificationRetentionDeletePlan(
    where: 'ownerUserId = ? AND env = ? AND id NOT IN ('
        'SELECT id FROM Notifications '
        'WHERE ownerUserId = ? AND env = ? '
        'ORDER BY receivedAt DESC, id DESC LIMIT ?'
        ')',
    whereArgs: <Object?>[
      normalizedOwnerUserId,
      normalizedEnvironment,
      normalizedOwnerUserId,
      normalizedEnvironment,
      limit,
    ],
  );
}

List<Object?> _localizedValues(
  Map<String, dynamic> data,
  String baseKey,
  String? preferredLanguageCode,
) {
  final String preferred = preferredLanguageCode?.trim().toLowerCase() ?? '';
  final String? preferredSuffix = switch (preferred) {
    'en' => 'En',
    'cs' => 'Cs',
    'de' => 'De',
    _ => null,
  };
  final List<Object?> values = <Object?>[];
  if (preferredSuffix != null) {
    values.add(data['$baseKey$preferredSuffix']);
  }
  values.add(data[baseKey]);
  for (final String suffix in <String>['En', 'Cs', 'De']) {
    if (suffix != preferredSuffix) {
      values.add(data['$baseKey$suffix']);
    }
  }
  return values;
}

Map<String, Object> notificationPersistenceValues({
  required String? notificationTitle,
  required String? notificationBody,
  required Object? messageType,
  required Map<String, dynamic> data,
  required DateTime? sentTime,
  required String ownerUserId,
  required String environment,
  Object? providerMessageId,
  String? preferredLanguageCode,
  DateTime Function()? now,
}) {
  final String normalizedOwnerUserId = ownerUserId.trim();
  final String normalizedEnvironment = environment.trim();
  final int? numericOwnerUserId = int.tryParse(normalizedOwnerUserId);
  if (numericOwnerUserId == null || numericOwnerUserId <= 0) {
    throw ArgumentError.value(
      ownerUserId,
      'ownerUserId',
      'A notification owner must be a positive backend user id.',
    );
  }
  if (normalizedEnvironment.isEmpty) {
    throw ArgumentError.value(
      environment,
      'environment',
      'A notification environment cannot be empty.',
    );
  }

  final String title = _firstNonEmpty(
    <Object?>[
      notificationTitle,
      ..._localizedValues(data, 'title', preferredLanguageCode),
    ],
    fallback: 'Strnadi',
  );
  final String body = _firstNonEmpty(
    <Object?>[
      notificationBody,
      ..._localizedValues(data, 'body', preferredLanguageCode),
    ],
    fallback: '',
  );
  final DateTime receivedAt = sentTime ?? (now ?? DateTime.now)();
  final String? normalizedProviderMessageId =
      normalizeNotificationProviderMessageId(providerMessageId);

  return <String, Object>{
    'title': title,
    'body': body,
    'receivedAt': receivedAt.toUtc().toIso8601String(),
    'type': _notificationType(messageType),
    'read': 0,
    'ownerUserId': normalizedOwnerUserId,
    'env': normalizedEnvironment,
    if (normalizedProviderMessageId != null)
      'providerMessageId': normalizedProviderMessageId,
  };
}
