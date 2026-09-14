import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/components/liquid_glass.dart';
import 'package:strnadi/navigation/scaffold_with_bottom_bar.dart';

Widget showcase({
  bool highContrast = false,
  bool accessible = false,
  Brightness brightness = Brightness.light,
  VoidCallback? onClose,
}) => MaterialApp(
  theme: ThemeData(brightness: brightness),
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(320, 300),
      highContrast: highContrast,
      accessibleNavigation: accessible,
      padding: const EdgeInsets.only(bottom: 24),
    ),
    child: RepaintBoundary(
      key: const ValueKey('glass-showcase'),
      child: Scaffold(
        backgroundColor: const Color(0xFF9CB8A1),
        body: Stack(
          children: [
            const Positioned(
              left: 24,
              top: 24,
              child: SizedBox(
                width: 150,
                height: 100,
                child: ColoredBox(color: Color(0xFFE6D09B)),
              ),
            ),
            Positioned(
              top: 24,
              right: 24,
              child: GlassIconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded),
                onPressed: onClose,
              ),
            ),
          ],
        ),
        bottomNavigationBar: GlassNavigationBar(
          children: [
            for (final icon in [
              Icons.map_outlined,
              Icons.list_rounded,
              Icons.mic_none,
              Icons.menu_book_outlined,
              Icons.person_outline,
            ])
              IconButton(onPressed: () {}, icon: Icon(icon)),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(() async {
    final loader = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await loader.load();
  });
  testWidgets(
    'close control has an accessible target and invokes its callback',
    (tester) async {
      var presses = 0;
      await tester.pumpWidget(showcase(onClose: () => presses++));
      final close = find.widgetWithIcon(IconButton, Icons.close_rounded);
      expect(tester.getSize(close), const Size(48, 48));
      await tester.tap(close);
      expect(presses, 1);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disabled close cannot invoke a callback', (tester) async {
    await tester.pumpWidget(showcase());
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.close_rounded),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'five tabs fit a narrow phone and selected recorder keeps its session',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var exitRequests = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: ReusableBottomAppBar(
              currentPage: BottomBarItem.recorder,
              changeConfirmation: () async {
                exitRequests++;
                return false;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final buttons = find.byType(IconButton);
      expect(buttons, findsNWidgets(5));
      expect(tester.widget<IconButton>(buttons.at(2)).isSelected, isTrue);
      await tester.tap(buttons.at(2));
      expect(exitRequests, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('toolbar spacing golden at narrow phone width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 140));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget button(IconData icon) =>
        GlassIconButton(icon: Icon(icon), onPressed: () {});
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(appBarTheme: glassAppBarTheme),
        home: RepaintBoundary(
          key: const ValueKey('toolbar-spacing'),
          child: Scaffold(
            appBar: AppBar(
              leading: button(Icons.arrow_back_ios_new),
              actions: [
                button(Icons.notifications_outlined),
                button(Icons.close),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('toolbar-spacing')),
      matchesGoldenFile('goldens/toolbar_spacing.png'),
    );
  });

  for (final accessible in [false, true]) {
    testWidgets('opaque accessibility surface ($accessible) skips blur', (
      tester,
    ) async {
      await tester.pumpWidget(
        showcase(highContrast: !accessible, accessible: accessible),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'glass controls ${brightness.name} golden at narrow phone width',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 300));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          showcase(brightness: brightness, onClose: () {}),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('glass-showcase')),
          matchesGoldenFile('goldens/glass_${brightness.name}.png'),
        );
      },
    );
  }
}
