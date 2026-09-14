import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/components/liquid_glass.dart';
import 'package:strnadi/components/native_ios_controls.dart';
import 'package:strnadi/navigation/scaffold_with_bottom_bar.dart';

void testNativeWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(
    description,
    callback,
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final configurations = <Map<Object?, Object?>>[];
  final channels = <String>[];
  var viewId = -1;

  setUp(() {
    configurations.clear();
    channels.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (call) async {
        if (call.method == 'create') {
          final args = call.arguments as Map;
          viewId = args['id'] as int;
          configurations.add(
            const StandardMessageCodec().decodeMessage(
                  ByteData.sublistView(args['params'] as Uint8List),
                )
                as Map<Object?, Object?>,
          );
          final name = 'com.delta.strnadi/native-controls/$viewId';
          channels.add(name);
          binding.defaultBinaryMessenger.setMockMethodCallHandler(
            MethodChannel(name),
            (call) async {
              if (call.method == 'update') {
                configurations.add(
                  Map<Object?, Object?>.from(call.arguments as Map),
                );
              }
              return null;
            },
          );
        }
        return null;
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      null,
    );
    for (final name in channels) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        null,
      );
    }
  });

  Future<dynamic> activate(int index) async {
    final completion = Completer<dynamic>();
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      'com.delta.strnadi/native-controls/$viewId',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('activate', index),
      ),
      (data) => completion.complete(
        data == null ? null : const StandardMethodCodec().decodeEnvelope(data),
      ),
    );
    return completion.future;
  }

  Future<dynamic> tapNative(WidgetTester tester, int index) async {
    final response = activate(index);
    await tester.pumpAndSettle();
    return response;
  }

  testNativeWidgets(
    'native toolbar buttons keep edge padding, gaps and full touch targets',
    (tester) async {
      Widget button(String symbol) => GlassIconButton(
        nativeSymbol: symbol,
        icon: const Icon(Icons.close),
        onPressed: () {},
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(appBarTheme: glassAppBarTheme),
          home: Scaffold(
            appBar: AppBar(
              leading: button('chevron.left'),
              actions: [button('bell'), button('xmark')],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final views = find.byType(UiKitView);
      expect(views, findsNWidgets(3));
      final back = tester.getRect(views.at(0));
      final bell = tester.getRect(views.at(1));
      final close = tester.getRect(views.at(2));
      final toolbar = tester.getRect(find.byType(AppBar));
      for (final rect in [back, bell, close]) {
        expect(rect.size, const Size(48, 48));
        expect(rect.top - toolbar.top, 4);
      }
      expect(back.left - toolbar.left, 12);
      expect(toolbar.right - close.right, 12);
      expect(close.left - bell.right, 8);
    },
  );

  testNativeWidgets(
    'map controls keep a full target inside their existing 48-point slot',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox.square(
              dimension: 48,
              child: GlassIconButton(
                padding: EdgeInsets.zero,
                nativeSymbol: 'location',
                icon: const Icon(Icons.location_on),
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(UiKitView)), const Size(48, 48));
    },
  );

  testNativeWidgets(
    'iOS close is native, with localized label, enabled state and badge',
    (tester) async {
      var pressed = 0;
      Widget button(bool enabled) => MaterialApp(
        home: Scaffold(
          body: GlassIconButton(
            icon: const Icon(Icons.close),
            nativeSymbol: 'xmark',
            tooltip: 'Zavřít',
            hasBadge: true,
            onPressed: enabled ? () => pressed++ : null,
          ),
        ),
      );
      await tester.pumpWidget(button(true));
      await tester.pumpAndSettle();
      expect(find.byType(UiKitView), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(configurations.last, containsPair('symbol', 'xmark'));
      expect(configurations.last, containsPair('label', 'Zavřít'));
      expect(configurations.last, containsPair('badge', true));
      await tapNative(tester, 0);
      expect(pressed, 1);
      await tester.pumpWidget(button(false));
      await tester.pumpAndSettle();
      expect(configurations.last, containsPair('enabled', false));
      await tapNative(tester, 0);
      expect(pressed, 1);
    },
  );

  testNativeWidgets(
    'glass button awaits async work and suppresses repeat taps',
    (tester) async {
      final gate = Completer<void>();
      var actions = 0;
      var finished = false;
      await tester.pumpWidget(
        MaterialApp(
          home: GlassIconButton(
            icon: const Icon(Icons.close),
            nativeSymbol: 'xmark',
            onPressed: () async {
              actions++;
              await gate.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pending = activate(0).then((value) {
        finished = true;
        return value;
      });
      await tester.pumpAndSettle();
      expect(actions, 1);
      expect(finished, isFalse);
      await tapNative(tester, 0);
      expect(actions, 1);
      gate.complete();
      await tester.pumpAndSettle();
      await pending;
      expect(finished, isTrue);
      await tapNative(tester, 0);
      expect(actions, 2);
    },
  );

  testNativeWidgets(
    'pending tab guard runs once and cancellation restores committed selection',
    (tester) async {
      final gate = Completer<void>();
      var actions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: NativeIOSTabBar(
              labels: const ['Map', 'Recordings', 'Record', 'Blog', 'Profile'],
              selectedIndex: 2,
              onTap: (index) async {
                actions++;
                expect(index, 0);
                await gate.future;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pending = activate(0);
      await tester.pump();
      expect(actions, 1);
      await tapNative(tester, 3);
      expect(actions, 1);
      gate.complete();
      await tester.pumpAndSettle();
      final committed = await pending;
      expect(committed, containsPair('selectedIndex', 2));
    },
  );

  testNativeWidgets('native tab taps obey the real recorder exit policy', (
    tester,
  ) async {
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
    await tapNative(tester, 2);
    expect(exitRequests, 0);
    final refused = await tapNative(tester, 3);
    expect(exitRequests, 1);
    expect(refused, containsPair('selectedIndex', 2));
    expect(find.byType(ReusableBottomAppBar), findsOneWidget);
    await tapNative(tester, -1);
    await tapNative(tester, 8);
    expect(exitRequests, 1);
    expect(tester.takeException(), isNull);
  });

  testNativeWidgets(
    'approved native selection returns the rebuilt destination',
    (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              bottomNavigationBar: NativeIOSTabBar(
                labels: const [
                  'Map',
                  'Recordings',
                  'Record',
                  'Articles',
                  'Profile',
                ],
                selectedIndex: selected,
                onTap: (index) async {
                  setState(() => selected = index);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final response = await tapNative(tester, 3);
      expect(response, containsPair('selectedIndex', 3));
    },
  );

  testNativeWidgets(
    'platform view updates selection and labels when Flutter changes',
    (tester) async {
      Widget bar(int selected) => MaterialApp(
        home: Scaffold(
          bottomNavigationBar: NativeIOSTabBar(
            labels: const ['Mapa', 'Nahrávky', 'Nahrávání', 'Články', 'Profil'],
            selectedIndex: selected,
            onTap: (_) async {},
          ),
        ),
      );
      await tester.pumpWidget(bar(0));
      await tester.pumpAndSettle();
      await tester.pumpWidget(bar(4));
      await tester.pumpAndSettle();
      expect(configurations.last, containsPair('selectedIndex', 4));
      expect((configurations.last['labels'] as List).first, 'Mapa');
    },
  );

  testNativeWidgets(
    'disposing during a pending action does not update a removed view',
    (tester) async {
      final gate = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 48,
            height: 48,
            child: NativeIOSControl(
              configuration: const {
                'kind': 'button',
                'enabled': true,
                'symbol': 'xmark',
              },
              onAction: (_) => gate.future,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pending = activate(0);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      gate.complete();
      expect(await pending, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
