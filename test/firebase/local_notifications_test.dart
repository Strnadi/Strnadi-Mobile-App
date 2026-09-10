import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:strnadi/firebase/local_notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'initialize' ? true : null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('initializes the Android notification icon', () async {
    await initLocalNotifications();
    expect(calls.single.method, 'initialize');
    expect(calls.single.arguments['defaultIcon'], '@mipmap/ic_launcher');
  });

  test(
    'delivers the supplied id and content to the notification channel',
    () async {
      await showLocalNotification('Recording ready', 'Upload complete', id: 42);
      expect(calls.single.method, 'show');
      expect(calls.single.arguments['id'], 42);
      expect(calls.single.arguments['title'], 'Recording ready');
      expect(calls.single.arguments['body'], 'Upload complete');
      expect(
        calls.single.arguments['platformSpecifics']['channelId'],
        'com.delta.strnadi',
      );
    },
  );

  test(
    'notification platform failures do not escape to the message handler',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(code: 'notification_unavailable');
          });
      await expectLater(
        showLocalNotification('Recording ready', null, id: 42),
        completes,
      );
    },
  );
}
