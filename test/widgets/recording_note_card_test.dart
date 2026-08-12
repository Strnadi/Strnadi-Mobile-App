import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/widgets/recording_note_card.dart';

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required String note,
    Size surfaceSize = const Size(180, 320),
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            key: const Key('note-scroll-view'),
            padding: const EdgeInsets.all(8),
            child: RecordingNoteCard(
              key: const Key('note-card'),
              note: note,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('short note is not forced to the former 100-pixel height',
      (tester) async {
    await pumpCard(tester, note: 'Short note');

    expect(tester.getSize(find.byKey(const Key('note-card'))).height,
        lessThan(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long prose wraps, grows, and scrolls on a narrow screen',
      (tester) async {
    final note = List<String>.filled(
      40,
      'A detailed recording note must remain completely readable.',
    ).join(' ');
    await pumpCard(
      tester,
      note: note,
      surfaceSize: const Size(180, 240),
    );

    final cardSize = tester.getSize(find.byKey(const Key('note-card')));
    final textSize = tester.getSize(
      find.byKey(RecordingNoteCard.textKey),
    );
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );

    expect(cardSize.height, greaterThan(240));
    expect(textSize.width, lessThanOrEqualTo(cardSize.width - 20));
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byKey(const Key('note-scroll-view')),
      const Offset(0, -180),
    );
    await tester.pump();

    expect(scrollable.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long unbroken token stays within a very narrow card',
      (tester) async {
    final token = List<String>.filled(512, 'W').join();
    await pumpCard(
      tester,
      note: token,
      surfaceSize: const Size(140, 240),
    );

    final cardRect = tester.getRect(find.byKey(const Key('note-card')));
    final textRect = tester.getRect(
      find.byKey(RecordingNoteCard.textKey),
    );

    expect(textRect.left, greaterThanOrEqualTo(cardRect.left + 10));
    expect(textRect.right, lessThanOrEqualTo(cardRect.right - 10));
    expect(textRect.height, greaterThan(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('matches the narrow wrapped-note golden', (tester) async {
    await pumpCard(
      tester,
      note:
          'Long field notes wrap naturally without clipping or leaving the bordered card.',
      surfaceSize: const Size(220, 400),
    );

    await expectLater(
      find.byKey(const Key('note-card')),
      matchesGoldenFile('goldens/recording_note_card_narrow.png'),
    );
  });

  test('map detail uses the wrapping note card instead of a fixed-height row',
      () {
    final source = File('lib/map/RecordingPage.dart').readAsStringSync();

    expect(source, contains('RecordingNoteCard('));
    expect(
      source,
      isNot(contains("'K tomuto zaznamu neni poznamka'")),
    );
  });
}
