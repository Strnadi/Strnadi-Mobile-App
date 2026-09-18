import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/recording/platform/recording_live_activity.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const codec = StandardMethodCodec();
  late RecordingLiveActivity activity;

  Future<void> send(String action) {
    final reply = Completer<void>();
    binding.defaultBinaryMessenger.handlePlatformMessage(
      'com.delta.strnadi/recording-activity',
      codec.encodeMethodCall(
        MethodCall('performRecordingAction', {
          'sessionID': 'test-session',
          'action': action,
        }),
      ),
      (data) {
        try {
          codec.decodeEnvelope(data!);
          reply.complete();
        } catch (error, stackTrace) {
          reply.completeError(error, stackTrace);
        }
      },
    );
    return reply.future;
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    activity = RecordingLiveActivity();
  });

  tearDown(() {
    activity.setActionHandler(null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('finish link waits for foreground before dispatching stop', () async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final actions = <RecordingActivityAction>[];
    activity.setActionHandler((sessionID, action) async {
      expect(sessionID, 'test-session');
      actions.add(action);
    });
    final finish = RecordingLiveActivity.handleFinishLink(
      Uri.parse('com.delta.strnadi://recording/finish?sessionID=test-session'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(actions, isEmpty);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(await finish, isTrue);
    expect(actions, [RecordingActivityAction.stop]);
  });

  test('finish link cannot transfer to a replacement recorder', () async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    activity.setActionHandler((sessionID, action) async {
      fail('Disposed recorder must not receive stop');
    });
    final finish = RecordingLiveActivity.handleFinishLink(
      Uri.parse('com.delta.strnadi://recording/finish?sessionID=old-session'),
    );
    final rejected = expectLater(finish, throwsA(isA<PlatformException>()));
    activity.setActionHandler(null);
    activity = RecordingLiveActivity();
    activity.setActionHandler((sessionID, action) async {
      fail('New recorder must not receive the old finish link');
    });
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await rejected;
  });

  test('unrelated and missing-session links do not finish recording', () async {
    activity.setActionHandler((sessionID, action) async {
      fail('Invalid link must not dispatch');
    });
    expect(
      await RecordingLiveActivity.handleFinishLink(
        Uri.parse('https://example.com/finish?sessionID=test-session'),
      ),
      isFalse,
    );
    expect(
      await RecordingLiveActivity.handleFinishLink(
        Uri.parse('com.delta.strnadi://recording/finish'),
      ),
      isTrue,
    );
  });

  test(
    'resume waits for pause finalization instead of being dropped',
    () async {
      final pauseStarted = Completer<void>();
      final finishPause = Completer<void>();
      final actions = <RecordingActivityAction>[];
      activity.setActionHandler((sessionID, action) async {
        actions.add(action);
        if (action == RecordingActivityAction.pause) {
          pauseStarted.complete();
          await finishPause.future;
        }
      });
      final pause = send('pause');
      await pauseStarted.future;
      final resume = send('resume');
      await Future<void>.delayed(Duration.zero);
      expect(actions, [RecordingActivityAction.pause]);
      finishPause.complete();
      await Future.wait([pause, resume]);
      expect(actions, [
        RecordingActivityAction.pause,
        RecordingActivityAction.resume,
      ]);
    },
  );

  test('failed command does not block subsequent resume', () async {
    final actions = <RecordingActivityAction>[];
    activity.setActionHandler((sessionID, action) async {
      actions.add(action);
      if (action == RecordingActivityAction.pause) {
        throw PlatformException(code: 'TEST_FAILURE');
      }
    });
    await expectLater(send('pause'), throwsA(isA<PlatformException>()));
    await send('resume');
    expect(actions.last, RecordingActivityAction.resume);
  });

  test(
    'stop waits for pause finalization and dispatches finish, not resume',
    () async {
      final pauseStarted = Completer<void>();
      final finishPause = Completer<void>();
      final actions = <RecordingActivityAction>[];
      activity.setActionHandler((sessionID, action) async {
        expect(sessionID, 'test-session');
        actions.add(action);
        if (action == RecordingActivityAction.pause) {
          pauseStarted.complete();
          await finishPause.future;
        }
      });
      final pause = send('pause');
      await pauseStarted.future;
      final stop = send('stop');
      await Future<void>.delayed(Duration.zero);
      expect(actions, [RecordingActivityAction.pause]);
      finishPause.complete();
      await Future.wait([pause, stop]);
      expect(actions, [
        RecordingActivityAction.pause,
        RecordingActivityAction.stop,
      ]);
    },
  );

  test('failed finish is returned and a later retry can complete', () async {
    var attempts = 0;
    activity.setActionHandler((sessionID, action) async {
      expect(action, RecordingActivityAction.stop);
      if (++attempts == 1) {
        throw PlatformException(code: 'RECORDING_FINISH_FAILED');
      }
    });
    await expectLater(send('stop'), throwsA(isA<PlatformException>()));
    await send('stop');
    expect(attempts, 2);
  });

  test('unknown commands never reach the recorder', () async {
    var calls = 0;
    activity.setActionHandler((_, _) async {
      calls++;
    });
    await expectLater(send('discard'), throwsA(isA<PlatformException>()));
    expect(calls, 0);
  });

  test('disposing an old screen does not remove the new handler', () async {
    final previous = activity;
    previous.setActionHandler((_, _) async {});
    activity = RecordingLiveActivity();
    var resumed = false;
    activity.setActionHandler((_, action) async {
      resumed = action == RecordingActivityAction.resume;
    });
    previous.setActionHandler(null);
    await send('resume');
    expect(resumed, isTrue);
  });
}
