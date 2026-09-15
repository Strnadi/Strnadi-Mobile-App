import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/map/recording_detail/recording_dialect_entry.dart';
import 'package:strnadi/map/recording_detail/recording_dialects_section.dart';
import 'package:strnadi/map/recording_detail/recording_download_card.dart';
import 'package:strnadi/map/recording_detail/recording_playback_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final packageFile = File('.dart_tool/package_config.json').absolute;
    final packages =
        jsonDecode(await packageFile.readAsString())['packages'] as List;
    final flutter = packages.cast<Map>().firstWhere(
      (entry) => entry['name'] == 'flutter',
    );
    final root = packageFile.uri.resolve(flutter['rootUri'] as String);
    final fonts = Uri.directory(
      File.fromUri(root).path,
    ).resolve('../../bin/cache/artifacts/material_fonts/');
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(
          File.fromUri(
            fonts.resolve(entry.value),
          ).readAsBytes().then(ByteData.sublistView),
        );
      await loader.load();
    }
  });
  setUp(() => Localization.load('assets/lang/en.json'));

  testWidgets('download progress supports cancellation and restricted access', (
    tester,
  ) async {
    var canceled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordingDownloadCard(
            accessResolved: true,
            canPlay: true,
            downloaded: false,
            downloading: true,
            progress: 0.42,
            onDownload: () {},
            onCancel: () => canceled = true,
          ),
        ),
      ),
    );
    expect(find.text('42.0%'), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    expect(canceled, isTrue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordingDownloadCard(
            accessResolved: true,
            canPlay: false,
            downloaded: false,
            downloading: false,
            progress: 0,
            onDownload: () {},
            onCancel: () {},
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('dialect loading and failure never display an invented dialect', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecordingDialectsSection(
            loading: true,
            error: null,
            entries: [],
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(t('dialectKeywords.unknown')), findsNothing);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecordingDialectsSection(
            loading: false,
            error: 'unavailable',
            entries: [],
          ),
        ),
      ),
    );
    expect(find.text(t('map.dialogs.error.title')), findsOneWidget);
    expect(find.text(t('dialectKeywords.unknown')), findsNothing);
  });

  testWidgets('detail cards retain their mobile layout', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final seeks = <int>[];
    var toggles = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: RepaintBoundary(
            key: const Key('detail-cards'),
            child: ColoredBox(
              color: ThemeData(useMaterial3: true).scaffoldBackgroundColor,
              child: Column(
                children: [
                  RecordingDownloadCard(
                    accessResolved: true,
                    canPlay: true,
                    downloaded: false,
                    downloading: false,
                    progress: 0,
                    onDownload: () {},
                    onCancel: () {},
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        RecordingPlaybackControls(
                          position: const Duration(seconds: 12),
                          duration: const Duration(seconds: 30),
                          progress: 0.4,
                          isPlaying: false,
                          onTogglePlay: () => toggles++,
                          onSeek: seeks.add,
                        ),
                        const SizedBox(height: 16),
                        const RecordingDialectsSection(
                          loading: false,
                          error: null,
                          entries: [
                            RecordingDialectEntry(
                              canonicalCode: 'BC',
                              displayLabel: 'BC',
                              isRepresentant: true,
                              startOffset: Duration(seconds: 3),
                              endOffset: Duration(seconds: 8),
                              confidence: RecordingDialectConfidence.confirmed,
                              color: Colors.green,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const Key('detail-cards')),
      matchesGoldenFile('../goldens/recording_detail_cards.png'),
    );
    await tester.tap(find.byIcon(Icons.replay_10));
    await tester.tap(find.byIcon(Icons.forward_10));
    await tester.tap(find.byIcon(Icons.play_circle_filled));
    expect(seeks, [-10, 10]);
    expect(toggles, 1);
  });
}
