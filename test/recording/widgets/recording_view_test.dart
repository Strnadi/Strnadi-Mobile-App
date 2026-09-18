import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/recording/widgets/recording_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Localization.load('assets/lang/en.json'));
  Future<void> pumpView(
    WidgetTester tester, {
    required RecordState state,
    bool busy = false,
    Future<void> Function()? onToggle,
    Future<void> Function()? onFinish,
    Future<void> Function()? onDiscard,
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: RecordingView(
          duration: const Duration(minutes: 1, seconds: 2, milliseconds: 340),
          recordState: state,
          hasMicPermission: true,
          isGuestUser: true,
          isProcessing: busy,
          isFinishing: false,
          isDiscarding: false,
          onToggle: onToggle ?? () async {},
          onFinish: onFinish ?? () async {},
          onDiscard: onDiscard ?? () async {},
          confirmExit: () async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('idle view offers start and hides completion actions', (
    tester,
  ) async {
    var toggles = 0;
    await pumpView(
      tester,
      state: RecordState.stop,
      onToggle: () async {
        toggles++;
      },
    );
    expect(find.text('01:02,34'), findsOneWidget);
    expect(find.text(t('streamRec.buttons.finishRecording')), findsNothing);
    expect(find.text(t('streamRec.buttons.discardRecording')), findsNothing);
    await tester.tap(
      find.bySemanticsLabel(t('streamRec.buttons.startRecording')),
    );
    expect(toggles, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paused view wires resume, finish and discard independently', (
    tester,
  ) async {
    var toggles = 0;
    var finishes = 0;
    var discards = 0;
    await pumpView(
      tester,
      state: RecordState.pause,
      onToggle: () async {
        toggles++;
      },
      onFinish: () async {
        finishes++;
      },
      onDiscard: () async {
        discards++;
      },
    );
    expect(find.text(t('streamRec.status.paused')), findsOneWidget);
    await tester.tap(
      find.bySemanticsLabel(t('streamRec.buttons.resumeRecording')),
    );
    await tester.tap(find.text(t('streamRec.buttons.finishRecording')));
    await tester.tap(find.text(t('streamRec.buttons.discardRecording')));
    expect([toggles, finishes, discards], [1, 1, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('busy capture blocks duplicate actions', (tester) async {
    var calls = 0;
    Future<void> action() async {
      calls++;
    }

    await pumpView(
      tester,
      state: RecordState.record,
      busy: true,
      onToggle: action,
      onFinish: action,
      onDiscard: action,
    );
    expect(find.text(t('streamRec.status.recording')), findsOneWidget);
    await tester.tap(
      find.bySemanticsLabel(t('streamRec.buttons.pauseRecording')),
      warnIfMissed: false,
    );
    await tester.tap(find.text(t('streamRec.buttons.finishRecording')));
    await tester.tap(find.text(t('streamRec.buttons.discardRecording')));
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });
}
