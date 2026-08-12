import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/api/controllers/recording_parts_controller.dart';
import 'package:strnadi/api/dio_client.dart';

void main() {
  late Dio dio;
  late HttpClientAdapter originalAdapter;
  late _QueuedResponseAdapter adapter;

  setUp(() {
    dio = ApiDioClient.instance;
    originalAdapter = dio.httpClientAdapter;
    adapter = _QueuedResponseAdapter()..enqueue(404);
    dio.httpClientAdapter = adapter;
  });

  tearDown(() {
    dio.httpClientAdapter = originalAdapter;
    adapter.verifyExhausted();
  });

  test('legacy recovery downloads the actual sound route without redirecting',
      () async {
    const RecordingPartsController controller = RecordingPartsController();

    final Response<dynamic> response = await controller.fetchPart(
      900,
      101,
      accessToken: 'captured-token',
      host: 'api.example.test',
    );

    expect(response.statusCode, 404);
    expect(adapter.requests, hasLength(1));
    final RequestOptions request = adapter.requests.single;
    expect(
      request.uri,
      Uri.parse('https://api.example.test/recordings/part/900/101/sound'),
    );
    expect(request.headers['Authorization'], 'Bearer captured-token');
    expect(request.followRedirects, isFalse);
    expect(request.maxRedirects, 0);
    expect(request.validateStatus(404), isTrue);
    expect(request.validateStatus(500), isFalse);
  });

  test('download uses the captured token and host without redirects', () async {
    adapter
      ..replaceResponses()
      ..enqueue(200, body: 'RIFF');
    const RecordingPartsController controller = RecordingPartsController();

    final Response<List<int>> response = await controller.downloadPartSound(
      900,
      101,
      accessToken: 'captured-download-token',
      host: 'captured-api.example.test',
    );

    expect(response.statusCode, 200);
    expect(adapter.requests, hasLength(1));
    final RequestOptions request = adapter.requests.single;
    expect(
      request.uri,
      Uri.parse(
        'https://captured-api.example.test/recordings/part/900/101/sound',
      ),
    );
    expect(
      request.headers['Authorization'],
      'Bearer captured-download-token',
    );
    expect(request.followRedirects, isFalse);
    expect(request.maxRedirects, 0);
    expect(request.responseType, ResponseType.bytes);
    expect(request.validateStatus(302), isTrue);
    expect(request.validateStatus(500), isFalse);
  });

  test('cross-origin 302 download response is returned and never replayed',
      () async {
    adapter
      ..replaceResponses()
      ..enqueue(
        302,
        headers: <String, List<String>>{
          'location': <String>['https://attacker.example/sound.wav'],
        },
      );
    const RecordingPartsController controller = RecordingPartsController();

    final Response<List<int>> response = await controller.downloadPartSound(
      900,
      101,
      accessToken: 'captured-download-token',
      host: 'captured-api.example.test',
    );

    expect(response.statusCode, 302);
    expect(adapter.requests, hasLength(1));
    expect(
      adapter.requests.single.uri.host,
      'captured-api.example.test',
    );
    expect(
      adapter.requests.single.headers['Authorization'],
      'Bearer captured-download-token',
    );
  });

  test('rebuilds multipart FormData for one mocked same-origin redirect',
      () async {
    adapter
      ..replaceResponses()
      ..enqueue(
        307,
        headers: <String, List<String>>{
          'location': <String>['/canonical/recordings/part-new'],
        },
      )
      ..enqueue(201, body: '202');
    final Directory tempDirectory =
        await Directory.systemTemp.createTemp('recording-part-upload-test-');
    addTearDown(() => tempDirectory.delete(recursive: true));
    final File audioFile = File('${tempDirectory.path}/part.wav');
    final List<int> audioBytes = <int>[1, 2, 3, 4];
    await audioFile.writeAsBytes(audioBytes);
    const RecordingPartMultipartUploader uploader =
        RecordingPartMultipartUploader();

    final Response<dynamic> response = await uploader.upload(
      filePath: audioFile.path,
      expectedSha256: sha256.convert(audioBytes).toString(),
      expectedByteLength: audioBytes.length,
      backendRecordingId: 900,
      startDate: DateTime.utc(2026, 7, 18, 8),
      endDate: DateTime.utc(2026, 7, 18, 8, 0, 12),
      gpsLatitudeStart: 49.1,
      gpsLatitudeEnd: 49.2,
      gpsLongitudeStart: 16.5,
      gpsLongitudeEnd: 16.6,
      accessToken: 'captured-token',
      idempotencyKey: 'recording-part:stable-key',
      host: 'api.example.test',
      beforePost: () async {},
    );

    expect(response.statusCode, 201);
    expect(adapter.requests, hasLength(2));
    final RequestOptions first = adapter.requests.first;
    final RequestOptions replay = adapter.requests.last;
    expect(
      first.uri,
      Uri.parse('https://api.example.test/recordings/part-new'),
    );
    expect(
      replay.uri,
      Uri.parse('https://api.example.test/canonical/recordings/part-new'),
    );
    expect(first.method, 'POST');
    expect(replay.method, 'POST');
    expect(first.followRedirects, isFalse);
    expect(replay.followRedirects, isFalse);
    expect(first.maxRedirects, 0);
    expect(replay.maxRedirects, 0);
    expect(first.headers['Authorization'], 'Bearer captured-token');
    expect(replay.headers['Authorization'], 'Bearer captured-token');
    expect(first.headers['Idempotency-Key'], 'recording-part:stable-key');
    expect(replay.headers['Idempotency-Key'], 'recording-part:stable-key');

    final FormData firstBody = first.data as FormData;
    final FormData replayBody = replay.data as FormData;
    expect(identical(firstBody, replayBody), isFalse);
    expect(
      Map<String, String>.fromEntries(firstBody.fields),
      Map<String, String>.fromEntries(replayBody.fields),
    );
    expect(
      Map<String, String>.fromEntries(firstBody.fields)['RecordingId'],
      '900',
    );
    expect(firstBody.files, hasLength(1));
    expect(replayBody.files, hasLength(1));
    expect(firstBody.files.single.key, 'file');
    expect(replayBody.files.single.key, 'file');
    expect(firstBody.files.single.value.filename, 'part.wav');
    expect(replayBody.files.single.value.filename, 'part.wav');
    expect(
      identical(
        firstBody.files.single.value,
        replayBody.files.single.value,
      ),
      isFalse,
    );
  });
}

class _QueuedResponseAdapter implements HttpClientAdapter {
  final Queue<_AdapterResponse> _responses = Queue<_AdapterResponse>();
  final List<RequestOptions> requests = <RequestOptions>[];

  void enqueue(
    int statusCode, {
    String body = '',
    Map<String, List<String>> headers = const <String, List<String>>{},
  }) {
    _responses.add(
      _AdapterResponse(
        statusCode: statusCode,
        body: body,
        headers: headers,
      ),
    );
  }

  void replaceResponses() {
    if (requests.isNotEmpty) {
      throw StateError('Cannot replace responses after a request.');
    }
    _responses.clear();
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_responses.isEmpty) {
      throw StateError('Unexpected mocked request to ${options.uri}.');
    }
    requests.add(options);
    if (requestStream != null) {
      await requestStream.drain<void>();
    }
    final _AdapterResponse response = _responses.removeFirst();
    return ResponseBody.fromString(
      response.body,
      response.statusCode,
      headers: response.headers,
    );
  }

  @override
  void close({bool force = false}) {}

  void verifyExhausted() {
    if (_responses.isNotEmpty) {
      throw StateError(
        '${_responses.length} mocked HTTP response(s) were not consumed.',
      );
    }
  }
}

class _AdapterResponse {
  const _AdapterResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  final int statusCode;
  final String body;
  final Map<String, List<String>> headers;
}
