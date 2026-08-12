import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/recording/recording_resource_cleanup.dart';

void main() {
  test('does not dispose the recorder until runtime shutdown completes',
      () async {
    final Completer<void> shutdownGate = Completer<void>();
    final List<String> events = <String>[];

    final Future<void> cleanup = shutdownRuntimeThenDisposeRecorder(
      shutdownRuntime: () async {
        events.add('shutdown-started');
        await shutdownGate.future;
        events.add('shutdown-completed');
      },
      disposeRecorder: () async {
        events.add('recorder-disposed');
      },
    );

    await Future<void>.delayed(Duration.zero);
    expect(events, <String>['shutdown-started']);

    shutdownGate.complete();
    await cleanup;

    expect(
      events,
      <String>[
        'shutdown-started',
        'shutdown-completed',
        'recorder-disposed',
      ],
    );
  });

  test('still disposes the recorder if runtime shutdown throws', () async {
    final List<String> events = <String>[];

    await expectLater(
      shutdownRuntimeThenDisposeRecorder(
        shutdownRuntime: () async {
          events.add('shutdown');
          throw StateError('simulated shutdown failure');
        },
        disposeRecorder: () async {
          events.add('dispose');
        },
      ),
      throwsA(isA<StateError>()),
    );

    expect(events, <String>['shutdown', 'dispose']);
  });
}
