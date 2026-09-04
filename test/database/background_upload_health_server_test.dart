import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/database/background_upload_health_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BackgroundRecordingHealthServer server;

  setUp(() {
    server = BackgroundRecordingHealthServer();
  });

  tearDown(() {
    for (final int recordingId in <int>[42, 43]) {
      server.stop(recordingId);
      IsolateNameServer.removePortNameMapping(server.portName(recordingId));
    }
  });

  test('registers a predictable per-recording health endpoint', () {
    expect(server.portName(42), '/upload/rec/42');
    expect(server.start(42), isTrue);
    expect(
      IsolateNameServer.lookupPortByName('/upload/rec/42'),
      isNotNull,
    );
  });

  test('replies to a direct SendPort health probe', () async {
    expect(server.start(42), isTrue);
    final SendPort endpoint =
        IsolateNameServer.lookupPortByName(server.portName(42))!;
    final ReceivePort reply = ReceivePort();
    addTearDown(reply.close);

    endpoint.send(reply.sendPort);

    expect(
      await reply.first.timeout(const Duration(seconds: 1)),
      <String, Object>{'status': 'uploading', 'recordingId': 42},
    );
  });

  test('map probes preserve their command in the reply', () async {
    expect(server.start(42), isTrue);
    final SendPort endpoint =
        IsolateNameServer.lookupPortByName(server.portName(42))!;
    final ReceivePort reply = ReceivePort();
    addTearDown(reply.close);

    endpoint.send(<String, Object>{
      'replyTo': reply.sendPort,
      'cmd': 'ping',
    });

    expect(
      await reply.first.timeout(const Duration(seconds: 1)),
      <String, Object>{
        'status': 'uploading',
        'recordingId': 42,
        'cmd': 'ping',
      },
    );
  });

  test('duplicate starts do not steal an active worker endpoint', () async {
    expect(server.start(42), isTrue);
    final SendPort original =
        IsolateNameServer.lookupPortByName(server.portName(42))!;

    expect(server.start(42), isFalse);
    expect(
      IsolateNameServer.lookupPortByName(server.portName(42)),
      original,
    );
  });

  test('different recordings have independent health endpoints', () {
    expect(server.start(42), isTrue);
    expect(server.start(43), isTrue);

    expect(
      IsolateNameServer.lookupPortByName(server.portName(42)),
      isNotNull,
    );
    expect(
      IsolateNameServer.lookupPortByName(server.portName(43)),
      isNotNull,
    );
  });

  test('stop removes the endpoint and permits a clean restart', () {
    expect(server.start(42), isTrue);

    server.stop(42);

    expect(
      IsolateNameServer.lookupPortByName(server.portName(42)),
      isNull,
    );
    expect(server.start(42), isTrue);
  });

  test('malformed health messages do not stop later valid probes', () async {
    expect(server.start(42), isTrue);
    final SendPort endpoint =
        IsolateNameServer.lookupPortByName(server.portName(42))!;
    final ReceivePort reply = ReceivePort();
    addTearDown(reply.close);

    endpoint
      ..send('not-a-health-request')
      ..send(<String, Object>{'replyTo': 'not-a-port'})
      ..send(reply.sendPort);

    expect(
      await reply.first.timeout(const Duration(seconds: 1)),
      <String, Object>{'status': 'uploading', 'recordingId': 42},
    );
  });

  test('an externally occupied endpoint is preserved', () {
    final ReceivePort external = ReceivePort();
    addTearDown(external.close);
    expect(
      IsolateNameServer.registerPortWithName(
        external.sendPort,
        server.portName(42),
      ),
      isTrue,
    );

    expect(server.start(42), isFalse);
    expect(
      IsolateNameServer.lookupPortByName(server.portName(42)),
      external.sendPort,
    );
  });
}
