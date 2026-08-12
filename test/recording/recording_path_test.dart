import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/recording/recording_path.dart';

void main() {
  test('skips reserved and existing paths before returning a unique path',
      () async {
    final List<String> candidates = <String>[
      'active-segment.wav',
      'already-on-disk.wav',
      'new-output.wav',
    ];
    int index = 0;

    final String selected = await selectUnusedRecordingPath(
      nextCandidate: () => candidates[index++],
      exists: (path) async => path == 'already-on-disk.wav',
      excludedPaths: <String>{'active-segment.wav'},
    );

    expect(selected, 'new-output.wav');
    expect(index, 3);
  });

  test('fails closed when no distinct path can be allocated', () async {
    await expectLater(
      selectUnusedRecordingPath(
        nextCandidate: () => 'reserved.wav',
        exists: (_) async => false,
        excludedPaths: <String>{'reserved.wav'},
        maxAttempts: 2,
      ),
      throwsA(isA<StateError>()),
    );
  });
}
