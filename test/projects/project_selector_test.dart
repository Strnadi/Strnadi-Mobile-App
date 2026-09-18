import 'dart:io';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/projects/available_project.dart';
import 'package:strnadi/projects/project_selector.dart';
import 'package:strnadi/projects/project_switch_guard.dart';

const first = AvailableProject(
  id: '019a1234-1234-7123-8123-123456789abc',
  name: 'Strnadi',
  apiDomain: 'https://first.example',
);
const second = AvailableProject(
  id: '019a1234-1234-7123-8123-123456789abd',
  name: 'Bird research',
  apiDomain: 'https://second.example',
);

void main() {
  setUpAll(() async {
    final root = Platform.environment['FLUTTER_ROOT']!;
    for (final font in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final bytes = File(
        '$root/bin/cache/artifacts/material_fonts/${font.value}',
      ).readAsBytesSync();
      await (FontLoader(
        font.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    await Localization.load('assets/lang/en.json');
  });
  test('discovery validates identity and rejects unsafe API destinations', () {
    for (final url in [
      'http://api.example',
      'https://user:secret@api.example',
      'https://api.example?token=x',
      'https://api.example/path',
      '',
    ]) {
      expect(
        AvailableProject.fromJson({
          'id': first.id,
          'name': first.name,
          'apiDomain': url,
        }).apiOrigin,
        isNull,
      );
    }
    expect(
      () => AvailableProject.fromJson({'id': 'invalid', 'name': 'name'}),
      throwsFormatException,
    );
    expect(
      AvailableProject.fromJson(first.toJson()).apiOrigin!.origin,
      'https://first.example',
    );
  });

  testWidgets(
    'loading, empty and discovery failure offer honest states and retry',
    (tester) async {
      final pending = Completer<List<AvailableProject>>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ProjectSelector(
            activeId: first.id,
            load: () {
              calls++;
              return calls == 1 ? pending.future : Future.value([]);
            },
          ),
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Strnadi'), findsNothing);
      pending.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text(t('projects.loadFailed')), findsOneWidget);
      await tester.tap(find.text(t('projects.retry')));
      await tester.pumpAndSettle();
      expect(find.text(t('projects.empty')), findsOneWidget);
    },
  );

  testWidgets('failed switch preserves active label and retry succeeds', (
    tester,
  ) async {
    var switches = 0;
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectSelector(
          activeId: first.id,
          load: () async => [first, second],
          select: (_) async {
            switches++;
            if (switches == 1) throw StateError('offline');
          },
          onSelected: () => completed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(second.name));
    await tester.pumpAndSettle();
    expect(find.text(t('projects.switchFailed')), findsOneWidget);
    expect(find.text(t('projects.active')), findsOneWidget);
    expect(completed, false);
    await tester.tap(find.text(t('projects.retry')));
    await tester.pumpAndSettle();
    expect(completed, true);
  });

  testWidgets('recording blocks UI switching with explanation', (tester) async {
    final owner = Object();
    ProjectSwitchGuard.register(owner, () => true);
    addTearDown(() => ProjectSwitchGuard.unregister(owner));
    var selected = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectSelector(
          activeId: first.id,
          load: () async => [first, second],
          select: (_) async => selected = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(second.name));
    await tester.pumpAndSettle();
    expect(selected, false);
    expect(find.text(t('projects.recordingBlocked')), findsOneWidget);
  });

  testWidgets('browse, retry joining, then explicitly switch', (tester) async {
    var joins = 0;
    var switches = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectSelector(
          activeId: first.id,
          load: () async => [first],
          loadCatalog: () async => [first, second],
          join: (_) async {
            joins++;
            if (joins == 1) throw StateError('offline');
          },
          select: (_) async => switches++,
          onSelected: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(t('projects.browse')));
    await tester.pumpAndSettle();
    expect(find.text(second.name), findsOneWidget);
    await tester.tap(find.text(t('projects.join')));
    await tester.pumpAndSettle();
    expect(find.text(t('projects.joinFailed')), findsOneWidget);
    expect(switches, 0);
    await tester.tap(find.text(t('projects.retry')));
    await tester.pumpAndSettle();
    expect(joins, 2);
    expect(find.text(t('projects.joined')), findsOneWidget);
    expect(find.text(t('projects.join')), findsNothing);
    expect(switches, 0);
    await tester.tap(find.text(second.name));
    await tester.pumpAndSettle();
    expect(switches, 1);
  });

  testWidgets('catalog failure retries without dropping current projects', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectSelector(
          activeId: first.id,
          load: () async => [first],
          loadCatalog: () async {
            calls++;
            if (calls == 1) throw StateError('offline');
            return [];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(t('projects.browse')));
    await tester.pumpAndSettle();
    expect(find.text(t('projects.catalogFailed')), findsOneWidget);
    expect(find.text(first.name), findsOneWidget);
    await tester.tap(find.text(t('projects.retry')));
    await tester.pumpAndSettle();
    expect(find.text(t('projects.noOtherProjects')), findsOneWidget);
  });

  testWidgets(
    'first-project chooser returns through navigation without switching',
    (tester) async {
      AvailableProject? joined;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Open chooser'),
                onPressed: () async {
                  joined = await Navigator.of(context).push<AvailableProject>(
                    MaterialPageRoute(
                      builder: (selectorContext) => ProjectSelector(
                        activeId: '',
                        browseInitially: true,
                        load: () async => [],
                        loadCatalog: () async => [second],
                        join: (_) async {},
                        onJoined: (project) =>
                            Navigator.of(selectorContext).pop(project),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open chooser'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t('projects.join')));
      await tester.pumpAndSettle();
      expect(joined, second);
      expect(find.byType(ProjectSelector), findsNothing);
    },
  );

  testWidgets(
    'login picker offers memberships without browsing or an active project',
    (tester) async {
      AvailableProject? selected;
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: ProjectSelector(
            activeId: '',
            allowBrowsing: false,
            load: () async => [first, second],
            select: (project) async {
              selected = project;
            },
            onSelected: () {
              completed = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(t('projects.browse')), findsNothing);
      expect(find.text(t('projects.active')), findsNothing);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/project_login_picker.png'),
      );
      await tester.tap(find.text(second.name));
      await tester.pumpAndSettle();
      expect(selected, second);
      expect(completed, isTrue);
    },
  );

  for (final dark in [false, true]) {
    testWidgets('project selector golden ${dark ? "dark" : "light"}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          home: ProjectSelector(
            activeId: first.id,
            load: () async => [first],
            loadCatalog: () async => [first, second],
            browseInitially: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          'goldens/project_selector_${dark ? "dark" : "light"}.png',
        ),
      );
    });
  }
}
