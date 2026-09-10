import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/recording/recording_location_subscription.dart';

void main() {
  test('location errors are handled and updates can resume until cancellation',
      () async {
    final source = StreamController<int>();
    final positions = <int>[];
    final failures = <Object>[];
    final subscription = subscribeToRecordingLocation(
      positions: source.stream,
      onPosition: positions.add,
      onFailure: (error, stack) => failures.add(error),
    );
    final disabled = StateError('Mock GPS disabled');
    final denied = StateError('Mock permission revoked');
    source
      ..add(1)
      ..addError(disabled)
      ..addError(denied)
      ..add(2);
    await Future<void>.delayed(Duration.zero);
    expect(positions, [1, 2]);
    expect(failures, [disabled, denied]);
    await subscription.cancel();
    source.add(3);
    await source.close();
    expect(positions, [1, 2]);
  });
}
