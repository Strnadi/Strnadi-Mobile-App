import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/logging/telemetry_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'login and logout advance the telemetry boundary; renewal does not',
    () async {
      final sessions = ActivatedAuthSessionManager(
        store: _Store(),
        subjectDecoder: (_) => 'owner',
      );
      final before = TelemetrySession.foreground.generation;
      final transition = await sessions.beginTokenTransition('first');
      expect(TelemetrySession.foreground.generation, before + 1);
      final active = await sessions.activate(transition, 7, verified: true);
      await sessions.replaceCredential(active, 'renewed');
      expect(TelemetrySession.foreground.generation, before + 1);
      await sessions.invalidate();
      expect(TelemetrySession.foreground.generation, before + 2);
      await sessions.clearAllPreservingGeneration(() async {});
      expect(TelemetrySession.foreground.generation, before + 3);
    },
  );

  test(
    'environment change advances boundary; selecting same one does not',
    () async {
      SharedPreferences.setMockInitialValues({});
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMessageHandler(
        'flutter/assets',
        (_) async =>
            ByteData.sublistView(Uint8List.fromList(utf8.encode('{}'))),
      );
      addTearDown(() {
        messenger.setMockMessageHandler('flutter/assets', null);
        rootBundle.evict('assets/config.json');
      });
      await Config.loadConfig();
      await Config.setHostEnvironment(HostEnvironment.prod);
      final before = TelemetrySession.foreground.generation;
      await Config.setHostEnvironment(HostEnvironment.dev);
      expect(TelemetrySession.foreground.generation, before + 1);
      await Config.setHostEnvironment(HostEnvironment.dev);
      expect(TelemetrySession.foreground.generation, before + 1);
      await Config.setHostEnvironment(HostEnvironment.prod);
    },
  );
}

class _Store implements AuthSessionKeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
