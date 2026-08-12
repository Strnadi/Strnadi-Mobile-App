import 'dart:collection';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/api/controllers/filtered_recordings_controller.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/database/recording_upload_service.dart';

void main() {
  late Dio dio;
  late HttpClientAdapter originalAdapter;
  late _QueuedHttpAdapter adapter;

  setUp(() {
    dio = ApiDioClient.instance;
    originalAdapter = dio.httpClientAdapter;
    adapter = _QueuedHttpAdapter();
    dio.httpClientAdapter = adapter;
  });

  tearDown(() {
    dio.httpClientAdapter = originalAdapter;
    adapter.verifyExhausted();
  });

  test('session change after mocked 307 prevents dialect POST replay',
      () async {
    adapter.enqueue(
      307,
      headers: <String, List<String>>{
        'location': <String>['/canonical/recordings/filtered'],
      },
    );
    const FilteredRecordingsController controller =
        FilteredRecordingsController();
    var sessionChecks = 0;

    await expectLater(
      controller.createFilteredPart(
        <String, dynamic>{
          'recordingId': 900,
          'startDate': '2026-07-18T08:00:00.000Z',
          'endDate': '2026-07-18T08:00:03.000Z',
          'dialectCode': 'BC',
        },
        accessToken: 'captured-dialect-token',
        idempotencyKey: 'recording-dialect:recording-key:dialect-key',
        host: 'api.example.test',
        beforePost: () async {
          sessionChecks++;
          if (sessionChecks == 2) {
            throw const RecordingUploadSessionChangedException();
          }
        },
      ),
      throwsA(isA<RecordingUploadSessionChangedException>()),
    );

    expect(sessionChecks, 2);
    expect(adapter.requests, hasLength(1));
    final RequestOptions request = adapter.requests.single;
    expect(
      request.uri,
      Uri.parse('https://api.example.test/recordings/filtered'),
    );
    expect(request.method, 'POST');
    expect(request.followRedirects, isFalse);
    expect(request.maxRedirects, 0);
    expect(
      request.headers['Authorization'],
      'Bearer captured-dialect-token',
    );
    expect(
      request.headers['Idempotency-Key'],
      'recording-dialect:recording-key:dialect-key',
    );
  });
}

class _QueuedHttpAdapter implements HttpClientAdapter {
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
        '${_responses.length} mocked response(s) were not consumed.',
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
