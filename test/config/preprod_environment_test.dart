import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strnadi/api/controllers/articles_controller.dart';
import 'package:strnadi/api/controllers/auth_controller.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/database/background_recording_upload_task.dart';
import 'package:strnadi/database/recording_upload_scheduling.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const defineHost = String.fromEnvironment('STRNADI_PREPROD_API_HOST');
  const hasDefine = bool.hasEnvironment('STRNADI_PREPROD_API_HOST');
  const defaultHost = 'preprod-api.strnadi.cz';
  const validDefine =
      !hasDefine || defineHost == 'override-preprod.example.test';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> loadAssetConfig(Map<String, dynamic> config) async {
    rootBundle.evict('assets/config.json');
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      expect(utf8.decode(message!.buffer.asUint8List()), 'assets/config.json');
      return ByteData.sublistView(
        Uint8List.fromList(utf8.encode(jsonEncode(config))),
      );
    });
    await Config.loadConfig();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Config.onHostEnvironmentChanged = null;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
    await loadAssetConfig({});
  });

  tearDown(() {
    Config.onHostEnvironmentChanged = null;
    rootBundle.evict('assets/config.json');
    messenger.setMockMessageHandler('flutter/assets', null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  test(
    'Administration uses the existing asset configuration and scope resolver',
    () async {
      if (!validDefine) return;
      await loadAssetConfig({
        'preprodadministrationurl': 'https://admin-preview.example.test/',
        'preprodprojectid': '01a08608-44b7-7aba-8d0c-542148b30bf2',
      });
      await Config.setHostEnvironment(HostEnvironment.preprod);
      expect(
        Config.administrationOrigin.toString(),
        'https://admin-preview.example.test/',
      );
      expect(Config.administration!.tenantOrigin.host, Config.host);
      expect(
        Config.dataEnvironment,
        contains('https://admin-preview.example.test'),
      );
    },
  );

  test(
    'invalid Administration asset configuration cannot change the environment',
    () async {
      if (!validDefine) return;
      await loadAssetConfig({
        'preprodadministrationurl': 'http://invalid.example/',
      });
      await expectLater(
        Config.setHostEnvironment(HostEnvironment.preprod),
        throwsArgumentError,
      );
      expect(Config.hostEnvironment, HostEnvironment.prod);
    },
  );

  test(
    'full preprod URL preserves prefix while OAuth uses its origin',
    () async {
      if (hasDefine) return;
      await loadAssetConfig({
        'preprodhost': 'https://preprod-api.example.test:8443/custom/v1/',
      });
      await Config.setHostEnvironment(HostEnvironment.preprod);
      expect(
        ApiDioClient.uri('/recordings').toString(),
        'https://preprod-api.example.test:8443/custom/v1/recordings',
      );
      expect(
        Config.administration!.tenantOrigin.toString(),
        'https://preprod-api.example.test:8443',
      );
      expect(
        ApiDioClient.uri(
          '/account/profile',
          host: Config.administrationHost,
        ).path,
        '/account/profile',
      );
    },
  );

  test('new installation remains production', () async {
    expect(Config.hostEnvironment, HostEnvironment.prod);
    expect(Config.host, 'api.strnadi.cz');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('host_environment'), 'HostEnvironment.prod');
  });

  test('empty Administration values fail before persisting preprod', () async {
    if (!validDefine) return;
    await loadAssetConfig({
      'preprodadministrationurl': '',
      'preprodprojectid': '',
    });
    await expectLater(
      Config.setHostEnvironment(HostEnvironment.preprod),
      throwsStateError,
    );
    expect(Config.hostEnvironment, HostEnvironment.prod);
  });

  test('password recovery uses administration only for preprod', () async {
    final dio = ApiDioClient.instance;
    final previous = dio.httpClientAdapter;
    final adapter = _RecordingAdapter();
    dio.httpClientAdapter = adapter;
    addTearDown(() => dio.httpClientAdapter = previous);
    for (final environment in HostEnvironment.values) {
      if (environment == HostEnvironment.preprod && !validDefine) continue;
      await Config.setHostEnvironment(environment);
      await const AuthController().requestPasswordReset('person@example.test');
      final request = adapter.requests.last;
      if (environment == HostEnvironment.preprod) {
        expect(request.uri.host, 'preprod-administration.strnadi.cz');
        expect(request.uri.path, '/account/forgot-password');
        expect(request.method, 'POST');
        expect(request.data, {'email': 'person@example.test'});
        expect(request.followRedirects, isFalse);
      } else {
        expect(request.uri.host, Config.host);
        expect(request.uri.path, '/auth/person@example.test/reset-password');
        expect(request.method, 'GET');
      }
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(request.extra['authRequired'], isFalse);
    }
  });

  for (final environment in HostEnvironment.values) {
    for (final raw in [environment.toString(), environment.name]) {
      test('restores $raw without changing recording scope names', () async {
        SharedPreferences.setMockInitialValues({'host_environment': raw});
        await Config.loadHostEnvironment();
        expect(Config.hostEnvironment, environment);
        expect(Config.hostEnvironment.name, environment.name);
      });
    }
  }

  test('unknown legacy selection retains production default', () async {
    SharedPreferences.setMockInitialValues({'host_environment': 'unknown'});
    await Config.loadHostEnvironment();
    expect(Config.hostEnvironment, HostEnvironment.prod);
  });

  test('prod and dev overrides keep their existing behavior', () async {
    await loadAssetConfig({
      'host': 'prod.example.test',
      'devhost': 'dev.example.test',
    });
    expect(Config.host, 'prod.example.test');
    await Config.setHostEnvironment(HostEnvironment.dev);
    expect(Config.host, 'dev.example.test');
    await loadAssetConfig({'host': 'prod.example.test', 'devhost': ''});
    expect(Config.host, 'prod.example.test');
  });

  test('preprod defaults and asset/define precedence', () async {
    if (!validDefine) {
      await expectLater(
        Config.setHostEnvironment(HostEnvironment.preprod),
        throwsStateError,
      );
      expect(Config.hostEnvironment, HostEnvironment.prod);
      return;
    }
    await Config.setHostEnvironment(HostEnvironment.preprod);
    expect(Config.host, hasDefine ? defineHost : defaultHost);
    await loadAssetConfig({'preprodhost': 'asset-preprod.example.test'});
    expect(Config.host, hasDefine ? defineHost : 'asset-preprod.example.test');
  });

  test('empty or production compile-time override fails closed', () async {
    if (validDefine) return;
    await loadAssetConfig({'preprodhost': defaultHost});
    var notified = false;
    Config.onHostEnvironmentChanged = () => notified = true;
    await expectLater(
      Config.setHostEnvironment(HostEnvironment.preprod),
      throwsStateError,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('host_environment'), 'HostEnvironment.prod');
    expect(notified, isFalse);
  });

  test(
    'switch persists before notification and survives background initialization',
    () async {
      if (!validDefine) return;
      final prefs = await SharedPreferences.getInstance();
      var notifications = 0;
      Config.onHostEnvironmentChanged = () {
        notifications++;
        expect(prefs.getString('host_environment'), 'HostEnvironment.preprod');
        expect(Config.hostEnvironment, HostEnvironment.preprod);
      };
      await Config.setHostEnvironment(HostEnvironment.preprod);
      expect(notifications, 1);
      // Force stale in-memory state, then initialize the real dispatch path from
      // mocked persisted preferences, as a newly launched worker would do.
      await prefs.setString('host_environment', 'HostEnvironment.prod');
      await Config.loadHostEnvironment();
      await prefs.setString('host_environment', 'HostEnvironment.preprod');
      expect(
        await dispatchBackgroundRecordingTask(
          taskName: recordingBackgroundTaskName,
          inputData: {'recordingId': 42},
          initialize: Config.loadConfig,
          handleRecordingTask: (input) async {
            expect(Config.hostEnvironment.name, 'preprod');
            expect(Config.host, hasDefine ? defineHost : defaultHost);
            return true;
          },
        ),
        isTrue,
      );
    },
  );

  test(
    'real controller and health check use HTTPS preprod via fake transport',
    () async {
      if (!validDefine) return;
      await Config.setHostEnvironment(HostEnvironment.preprod);
      final dio = ApiDioClient.instance;
      final previous = dio.httpClientAdapter;
      final adapter = _RecordingAdapter();
      dio.httpClientAdapter = adapter;
      addTearDown(() => dio.httpClientAdapter = previous);
      await const ArticlesController().fetchArticles();
      expect(await Config.checkServerHealth(), ServerHealth.healthy);
      expect(
        adapter.requests.map((r) => r.uri.host),
        everyElement(hasDefine ? defineHost : defaultHost),
      );
      expect(adapter.requests.map((r) => r.uri.scheme), everyElement('https'));
      expect(adapter.requests.map((r) => r.uri.path), [
        '/articles',
        '/utils/health',
      ]);
    },
  );

  for (final invalid in [
    null,
    '',
    ' ',
    'host/path',
    'host:443',
    'host?query',
    'user@host',
    '-host',
    'host..test',
    42,
    'api.strnadi.cz',
    'API.STRNADI.CZ',
    'prod.example.test',
  ]) {
    test('preprod rejects $invalid without production fallback', () {
      expect(
        () => resolveApiHost(HostEnvironment.preprod, {
          'host': 'prod.example.test',
          'preprodhost': invalid,
        }),
        throwsStateError,
      );
    });
  }
}

class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '[]',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
