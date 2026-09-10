import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/config/host_environment.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/user/environment_dropdown.dart';
import 'package:strnadi/widgets/environment_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => Localization.load('assets/lang/en.json'));

  test('production selector remains role gated, non-production can exit', () {
    for (final role in [null, '', 'user', 'admin', 'tester']) {
      expect(canEditEnvironment(role, HostEnvironment.prod),
          role == 'admin' || role == 'tester');
      expect(canEditEnvironment(role, HostEnvironment.dev), isTrue);
      expect(canEditEnvironment(role, HostEnvironment.preprod), isTrue);
    }
  });

  Future<void> pumpControls(
    WidgetTester tester, {
    HostEnvironment initial = HostEnvironment.preprod,
    bool enabled = true,
  }) async {
    var environment = initial;
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: StatefulBuilder(
          builder: (context, setState) => EnvironmentBanner(
                environment: environment,
                child: Scaffold(
                    body: Padding(
                  padding: const EdgeInsets.all(24),
                  child: EnvironmentDropdown(
                    environment: environment,
                    onChanged: !enabled
                        ? null
                        : (next) async {
                            if (next == null || next == environment) return;
                            if (await confirmEnvironmentChange(context)) {
                              setState(() => environment = next);
                            }
                          },
                  ),
                )),
              )),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('offers all three environments and cancel preserves selection',
      (tester) async {
    await pumpControls(tester, initial: HostEnvironment.prod);
    await tester.tap(find.byType(DropdownButton<HostEnvironment>));
    await tester.pumpAndSettle();
    expect(find.text('Production'), findsWidgets);
    expect(find.text('Development'), findsWidgets);
    expect(find.text('Preprod'), findsWidgets);
    await tester.tap(find.text('Preprod').last);
    await tester.pumpAndSettle();
    expect(find.text('Change environment?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<DropdownButton<HostEnvironment>>(
                find.byType(DropdownButton<HostEnvironment>))
            .value,
        HostEnvironment.prod);
    expect(find.byType(Banner), findsNothing);
  });

  for (final source in HostEnvironment.values) {
    for (final target
        in HostEnvironment.values.where((value) => value != source)) {
      testWidgets('confirm $source -> $target updates label and banner',
          (tester) async {
        await pumpControls(tester, initial: source);
        await tester.tap(find.byType(DropdownButton<HostEnvironment>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(t(target.labelKey)).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(
            tester
                .widget<DropdownButton<HostEnvironment>>(
                    find.byType(DropdownButton<HostEnvironment>))
                .value,
            target);
        if (target.isNonProduction) {
          expect(tester.widget<Banner>(find.byType(Banner)).message,
              t(target.badgeKey));
        } else {
          expect(find.byType(Banner), findsNothing);
        }
      });
    }
  }

  testWidgets('disabled selector cannot change while switching',
      (tester) async {
    await pumpControls(tester, enabled: false);
    expect(
        tester
            .widget<DropdownButton<HostEnvironment>>(
                find.byType(DropdownButton<HostEnvironment>))
            .onChanged,
        isNull);
  });

  for (final language in ['cs', 'en', 'de']) {
    testWidgets('$language preprod controls match narrow golden',
        (tester) async {
      await tester
          .runAsync(() => Localization.load('assets/lang/$language.json'));
      for (final environment in HostEnvironment.values) {
        expect(t(environment.labelKey), isNot(startsWith('user.settings.')));
      }
      await tester.binding.setSurfaceSize(const Size(320, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpControls(tester);
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(EnvironmentBanner),
          matchesGoldenFile('goldens/preprod_controls_$language.png'));
    });
  }
}
