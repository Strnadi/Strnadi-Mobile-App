import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/database/recording_duration_refresh.dart';

void main() {
  group('parseRecordingDuration', () {
    test('accepts positive integer, double, and numeric string values', () {
      expect(parseRecordingDuration(<String, Object>{'totalSeconds': 12}), 12);
      expect(
        parseRecordingDuration(<String, Object>{'totalSeconds': 12.5}),
        12.5,
      );
      expect(
        parseRecordingDuration(<String, Object>{'totalSeconds': ' 8.25 '}),
        8.25,
      );
    });

    test('accepts a JSON string response', () {
      expect(parseRecordingDuration('{"totalSeconds":"7.5"}'), 7.5);
    });

    test('rejects malformed or non-object JSON', () {
      expect(parseRecordingDuration('{broken'), isNull);
      expect(parseRecordingDuration('[12]'), isNull);
      expect(parseRecordingDuration(null), isNull);
    });

    test('rejects missing, zero, negative, NaN, and infinite values', () {
      expect(parseRecordingDuration(<String, Object>{}), isNull);
      expect(
          parseRecordingDuration(<String, Object>{'totalSeconds': 0}), isNull);
      expect(
        parseRecordingDuration(<String, Object>{'totalSeconds': -0.1}),
        isNull,
      );
      expect(
        parseRecordingDuration(<String, Object>{'totalSeconds': double.nan}),
        isNull,
      );
      expect(
        parseRecordingDuration(
          <String, Object>{'totalSeconds': double.infinity},
        ),
        isNull,
      );
    });
  });

  group('refreshRecordingDurations', () {
    test('stale session before loading performs no DB or API work', () async {
      var loadCalls = 0;
      var fetchCalls = 0;
      var saveCalls = 0;

      final RecordingDurationRefreshResult result =
          await refreshRecordingDurations(
        isSessionCurrent: () async => false,
        loadTargets: () async {
          loadCalls++;
          return <RecordingDurationTarget>[];
        },
        fetchDuration: (_) async {
          fetchCalls++;
          return _success(10);
        },
        saveDuration: (_, __) async => saveCalls++,
      );

      expect(result.sessionChanged, isTrue);
      expect(result.attempted, 0);
      expect(loadCalls, 0);
      expect(fetchCalls, 0);
      expect(saveCalls, 0);
    });

    test('session read failure fails closed before loading', () async {
      var loadCalls = 0;

      final RecordingDurationRefreshResult result =
          await refreshRecordingDurations(
        isSessionCurrent: () => Future<bool>.error(StateError('keychain')),
        loadTargets: () async {
          loadCalls++;
          return <RecordingDurationTarget>[];
        },
        fetchDuration: (_) async => _success(10),
        saveDuration: (_, __) async {},
      );

      expect(result.sessionChanged, isTrue);
      expect(loadCalls, 0);
    });

    test('session change after DB load performs no API work', () async {
      final List<bool> checks = <bool>[true, false];
      var fetchCalls = 0;

      final RecordingDurationRefreshResult result =
          await refreshRecordingDurations(
        isSessionCurrent: () async => checks.removeAt(0),
        loadTargets: () async => <RecordingDurationTarget>[_target(1, 101)],
        fetchDuration: (_) async {
          fetchCalls++;
          return _success(10);
        },
        saveDuration: (_, __) async {},
      );

      expect(result.sessionChanged, isTrue);
      expect(fetchCalls, 0);
    });

    test('skips invalid identifiers and existing positive duration', () async {
      final List<int> fetched = <int>[];

      final RecordingDurationRefreshResult result =
          await refreshRecordingDurations(
        isSessionCurrent: () async => true,
        loadTargets: () async => <RecordingDurationTarget>[
          _target(0, 101),
          _target(1, 0),
          _target(2, 102, duration: 4),
          _target(3, 103),
        ],
        fetchDuration: (int backendId) async {
          fetched.add(backendId);
          return _success(9);
        },
        saveDuration: (_, __) async {},
      );

      expect(fetched, <int>[103]);
      expect(result.attempted, 1);
      expect(result.updated, 1);
      expect(result.failed, 0);
    });

    test('saves a valid response against its local target', () async {
      RecordingDurationTarget? savedTarget;
      double? savedDuration;

      final RecordingDurationRefreshResult result =
          await refreshRecordingDurations(
        isSessionCurrent: () async => true,
        loadTargets: () async => <RecordingDurationTarget>[_target(7, 107)],
        fetchDuration: (int backendId) async {
          expect(backendId, 107);
          return const RecordingDurationFetchResponse(
            statusCode: 200,
            data: <String, Object>{'totalSeconds': '11.25'},
          );
        },
        saveDuration: (target, duration) async {
          savedTarget = target;
          savedDuration = duration;
        },
      );

      expect(savedTarget?.localId, 7);
      expect(savedDuration, 11.25);
      expect(result.updated, 1);
      expect(result.sessionChanged, isFalse);
    });

    test('non-200 and invalid 200 responses fail without DB writes', () async {
      var saveCalls = 0;
      final List<RecordingDurationFetchResponse> responses =
          <RecordingDurationFetchResponse>[
        const RecordingDurationFetchResponse(
          statusCode: 404,
          data: <String, Object>{'totalSeconds': 3},
        ),
        const RecordingDurationFetchResponse(
          statusCode: 500,
          data: <String, Object>{'totalSeconds': 4},
        ),
        const RecordingDurationFetchResponse(
          statusCode: 200,
          data: <String, Object>{'totalSeconds': 0},
        ),
      ];

      final RecordingDurationRefreshResult result =
          await refreshRecordingDurations(
        isSessionCurrent: () async => true,
        loadTargets: () async => <RecordingDurationTarget>[
          _target(1, 101),
          _target(2, 102),
          _target(3, 103),
        ],
        fetchDuration: (_) async => responses.removeAt(0),
        saveDuration: (_, __) async => saveCalls++,
      );

      expect(result.attempted, 3);
      expect(result.failed, 3);
      expect(result.updated, 0);
      expect(saveCalls, 0);
    });

    test('API exception is isolated and later targets still run', () async {
      final List<int> fetched = <int>[];

      final RecordingDurationRefreshResult result =
          await refreshRecordingDurations(
        isSessionCurrent: () async => true,
        loadTargets: () async => <RecordingDurationTarget>[
          _target(1, 101),
          _target(2, 102),
        ],
        fetchDuration: (int backendId) async {
          fetched.add(backendId);
          if (backendId == 101) throw StateError('mock API failure');
          return _success(6);
        },
        saveDuration: (_, __) async {},
      );

      expect(fetched, <int>[101, 102]);
      expect(result.failed, 1);
      expect(result.updated, 1);
    });

    test('DB save exception is isolated and later targets still run', () async {
      final List<int> saved = <int>[];

      final RecordingDurationRefreshResult result =
          await refreshRecordingDurations(
        isSessionCurrent: () async => true,
        loadTargets: () async => <RecordingDurationTarget>[
          _target(1, 101),
          _target(2, 102),
        ],
        fetchDuration: (_) async => _success(6),
        saveDuration: (target, _) async {
          saved.add(target.localId);
          if (target.localId == 1) throw StateError('mock DB failure');
        },
      );

      expect(saved, <int>[1, 2]);
      expect(result.failed, 1);
      expect(result.updated, 1);
    });

    test('account switch while API is pending prevents the DB save', () async {
      final Completer<RecordingDurationFetchResponse> response =
          Completer<RecordingDurationFetchResponse>();
      var current = true;
      var saveCalls = 0;

      final Future<RecordingDurationRefreshResult> pending =
          refreshRecordingDurations(
        isSessionCurrent: () async => current,
        loadTargets: () async => <RecordingDurationTarget>[_target(1, 101)],
        fetchDuration: (_) => response.future,
        saveDuration: (_, __) async => saveCalls++,
      );
      await Future<void>.delayed(Duration.zero);
      current = false;
      response.complete(_success(10));

      final RecordingDurationRefreshResult result = await pending;
      expect(result.sessionChanged, isTrue);
      expect(result.attempted, 1);
      expect(saveCalls, 0);
    });

    test('session check failure after API prevents the DB save', () async {
      var checks = 0;
      var saveCalls = 0;

      final RecordingDurationRefreshResult result =
          await refreshRecordingDurations(
        isSessionCurrent: () async {
          checks++;
          if (checks == 4) throw StateError('mock keychain failure');
          return true;
        },
        loadTargets: () async => <RecordingDurationTarget>[_target(1, 101)],
        fetchDuration: (_) async => _success(10),
        saveDuration: (_, __) async => saveCalls++,
      );

      expect(result.sessionChanged, isTrue);
      expect(saveCalls, 0);
    });

    test('account switch after save aborts before the next API call', () async {
      var current = true;
      final List<int> fetched = <int>[];

      final RecordingDurationRefreshResult result =
          await refreshRecordingDurations(
        isSessionCurrent: () async => current,
        loadTargets: () async => <RecordingDurationTarget>[
          _target(1, 101),
          _target(2, 102),
        ],
        fetchDuration: (int backendId) async {
          fetched.add(backendId);
          return _success(10);
        },
        saveDuration: (_, __) async => current = false,
      );

      expect(result.sessionChanged, isTrue);
      expect(result.updated, 1);
      expect(fetched, <int>[101]);
    });

    test('initial mocked DB load failure is surfaced to the caller', () async {
      expect(
        () => refreshRecordingDurations(
          isSessionCurrent: () async => true,
          loadTargets: () => Future<List<RecordingDurationTarget>>.error(
            StateError('mock DB load failure'),
          ),
          fetchDuration: (_) async => _success(10),
          saveDuration: (_, __) async {},
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}

RecordingDurationTarget _target(
  int localId,
  int backendId, {
  double? duration,
}) {
  return RecordingDurationTarget(
    localId: localId,
    backendId: backendId,
    currentDuration: duration,
  );
}

RecordingDurationFetchResponse _success(num duration) {
  return RecordingDurationFetchResponse(
    statusCode: 200,
    data: <String, Object>{'totalSeconds': duration},
  );
}
