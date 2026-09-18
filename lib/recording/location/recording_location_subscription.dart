import 'dart:async';

/// Owns error delivery as well as positions; a denied/disabled GPS source must
/// not turn an otherwise valid audio capture into an uncaught zone error.
StreamSubscription<T> subscribeToRecordingLocation<T>({
  required Stream<T> positions,
  required void Function(T) onPosition,
  required void Function(Object, StackTrace) onFailure,
}) => positions.listen(onPosition, onError: onFailure);
