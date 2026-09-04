import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/database/src/upload_progress_bus.dart';

void main() {
  const List<int> testPartIds = <int>[7101, 7102, 7103, 7104];

  setUp(() {
    for (final int partId in testPartIds) {
      UploadProgressBus.clear(partId);
    }
  });

  tearDown(() {
    for (final int partId in testPartIds) {
      UploadProgressBus.clear(partId);
    }
    UploadProgressBus.setRetainAfterDone(Duration.zero);
  });

  test('new listeners receive an immediate detached snapshot', () async {
    UploadProgressBus.update(7101, 1, 4);
    final StreamIterator<Map<int, double>> iterator =
        StreamIterator<Map<int, double>>(UploadProgressBus.stream);

    expect(await iterator.moveNext(), isTrue);
    final Map<int, double> initial = iterator.current;
    expect(initial, <int, double>{7101: 0.25});
    expect(() => initial[7102] = 0.5, throwsUnsupportedError);

    await iterator.cancel();
  });

  test('update calculates progress and emits the current aggregate', () async {
    final StreamIterator<Map<int, double>> iterator =
        StreamIterator<Map<int, double>>(UploadProgressBus.stream);
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current, isEmpty);

    UploadProgressBus.update(7101, 3, 4);
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current, <int, double>{7101: 0.75});

    UploadProgressBus.update(7102, 1, 2);
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current, <int, double>{7101: 0.75, 7102: 0.5});

    await iterator.cancel();
  });

  test('invalid totals and out-of-range byte counts are clamped safely', () {
    UploadProgressBus.update(7101, 5, 0);
    UploadProgressBus.update(7102, -5, 10);
    UploadProgressBus.update(7103, 15, 10);

    expect(
      UploadProgressBus.snapshot,
      <int, double>{7101: 0, 7102: 0, 7103: 1},
    );
  });

  test('snapshot mutations cannot change the bus state', () {
    UploadProgressBus.update(7101, 1, 2);

    final Map<int, double> copy = UploadProgressBus.snapshot;
    copy
      ..clear()
      ..[7102] = 1;

    expect(UploadProgressBus.snapshot, <int, double>{7101: 0.5});
  });

  test('markDone and clear remove only the selected part', () async {
    UploadProgressBus.update(7101, 1, 2);
    UploadProgressBus.update(7102, 1, 4);
    final StreamIterator<Map<int, double>> iterator =
        StreamIterator<Map<int, double>>(UploadProgressBus.stream);
    expect(await iterator.moveNext(), isTrue);

    UploadProgressBus.markDone(7101);
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current, <int, double>{7102: 0.25});

    UploadProgressBus.clear(7102);
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current, isEmpty);
    expect(UploadProgressBus.snapshot, isEmpty);

    await iterator.cancel();
  });

  test('retention configuration and debug state are safe without listeners',
      () {
    UploadProgressBus.setRetainAfterDone(const Duration(milliseconds: 50));
    UploadProgressBus.setRetainAfterDone(null);

    expect(() => UploadProgressBus.debugState('test'), returnsNormally);
  });
}
