import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/api/controllers/recording_parts_controller.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/api/immutable_upload_file.dart';
import 'package:strnadi/database/recording_upload_service.dart';
import 'package:strnadi/exceptions.dart';

void main() {
  late Dio dio;
  late HttpClientAdapter originalAdapter;
  late _CapturingAdapter adapter;

  setUp(() {
    dio = ApiDioClient.instance;
    originalAdapter = dio.httpClientAdapter;
    adapter = _CapturingAdapter();
    dio.httpClientAdapter = adapter;
  });

  tearDown(() {
    dio.httpClientAdapter = originalAdapter;
    adapter.verifyExhausted();
  });

  test(
      'mutation after fingerprint validation is rejected before mocked remote '
      'bytes', () async {
    final _FakeStagingOperations files = _FakeStagingOperations();
    const String path = '/recordings/part.wav';
    final List<int> validatedBytes = Uint8List.fromList(
      'validated-recording-content'.codeUnits,
    );
    files.put(path, validatedBytes);
    final String validatedHash = sha256.convert(validatedBytes).toString();

    // Simulates a writer replacing the content after the service validated
    // and froze its fingerprint, but before the API adapter stages it.
    files.mutate(
      path,
      Uint8List.fromList('changed---recording-content'.codeUnits),
    );
    final RecordingPartMultipartUploader uploader =
        _uploaderWithFakeFiles(files);

    await expectLater(
      _upload(
        uploader,
        path: path,
        hash: validatedHash,
        length: validatedBytes.length,
      ),
      throwsA(isA<ImmutableUploadSourceException>()),
    );

    expect(adapter.requests, isEmpty);
    expect(adapter.requestBodies, isEmpty);
    expect(files.stageCreateCount, 1);
    expect(files.stageDeleteCount, 1);
    expect(files.handles, isEmpty);
  });

  test(
      'initial POST and redirect replay stream the fingerprinted snapshot when '
      'the original changes between legs', () async {
    final _FakeStagingOperations files = _FakeStagingOperations();
    const String path = '/recordings/part.wav';
    final List<int> fingerprintedBytes = Uint8List.fromList(
      'ORIGINAL-IMMUTABLE-RECORDING-BYTES'.codeUnits,
    );
    final List<int> changedOriginal = Uint8List.fromList(
      'MUTATED--ORIGINAL--RECORDING-BYTES'.codeUnits,
    );
    files.put(path, fingerprintedBytes);
    adapter
      ..enqueue(
        307,
        headers: <String, List<String>>{
          'location': <String>['/canonical/recordings/part-new'],
        },
      )
      ..enqueue(201, body: '702')
      ..afterBody = (int requestIndex) {
        if (requestIndex == 0) {
          files.mutate(path, changedOriginal);
        }
      };
    final RecordingPartMultipartUploader uploader =
        _uploaderWithFakeFiles(files);

    final Response<dynamic> response = await _upload(
      uploader,
      path: path,
      hash: sha256.convert(fingerprintedBytes).toString(),
      length: fingerprintedBytes.length,
    );

    expect(response.statusCode, 201);
    expect(adapter.requests, hasLength(2));
    expect(adapter.requestBodies, hasLength(2));
    expect(
      adapter.requests.map(
        (RequestOptions request) => request.headers['Idempotency-Key'],
      ),
      everyElement('recording-part:stable-key'),
    );
    expect(
      adapter.requests.map((RequestOptions request) => request.uri),
      <Uri>[
        Uri.parse('https://api.example.test/recordings/part-new'),
        Uri.parse('https://api.example.test/canonical/recordings/part-new'),
      ],
    );

    final List<Uint8List> uploadedFiles = adapter.requestBodies
        .map(_extractMultipartFile)
        .toList(growable: false);
    expect(uploadedFiles, hasLength(2));
    for (final Uint8List uploaded in uploadedFiles) {
      expect(uploaded, orderedEquals(fingerprintedBytes));
      expect(
        sha256.convert(uploaded).toString(),
        sha256.convert(fingerprintedBytes).toString(),
      );
      expect(uploaded, isNot(orderedEquals(changedOriginal)));
    }
    expect(uploadedFiles.first, orderedEquals(uploadedFiles.last));
    expect(files.bytesAt(path), orderedEquals(changedOriginal));
    expect(files.stageDeleteCount, 1);
    expect(files.handles.single.closeCount, 1);
  });

  test('session change during staged copy sends zero mocked remote bytes',
      () async {
    final _FakeStagingOperations files = _FakeStagingOperations();
    const String path = '/recordings/part.wav';
    final List<int> bytes =
        Uint8List.fromList('session-change-during-copy'.codeUnits);
    var sessionCurrent = true;
    files
      ..put(path, bytes)
      ..afterWrite = () {
        sessionCurrent = false;
      };
    final RecordingPartMultipartUploader uploader =
        _uploaderWithFakeFiles(files);

    await expectLater(
      _upload(
        uploader,
        path: path,
        hash: sha256.convert(bytes).toString(),
        length: bytes.length,
        beforePost: () async {
          if (!sessionCurrent) {
            throw const RecordingUploadSessionChangedException();
          }
        },
      ),
      throwsA(isA<RecordingUploadSessionChangedException>()),
    );

    expect(adapter.requests, isEmpty);
    expect(adapter.requestBodies, isEmpty);
    expect(files.stageDeleteCount, 1);
    expect(files.handles.single.closeCount, 1);
  });

  test('session change after 307 prevents redirect replay and cleans the stage',
      () async {
    final _FakeStagingOperations files = _FakeStagingOperations();
    const String path = '/recordings/part.wav';
    final List<int> bytes =
        Uint8List.fromList('session-change-before-replay'.codeUnits);
    files.put(path, bytes);
    adapter.enqueue(
      307,
      headers: <String, List<String>>{
        'location': <String>['/canonical/recordings/part-new'],
      },
    );
    var sessionChecks = 0;
    final RecordingPartMultipartUploader uploader =
        _uploaderWithFakeFiles(files);

    await expectLater(
      _upload(
        uploader,
        path: path,
        hash: sha256.convert(bytes).toString(),
        length: bytes.length,
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
    expect(adapter.requestBodies, hasLength(1));
    expect(_extractMultipartFile(adapter.requestBodies.single),
        orderedEquals(bytes));
    expect(files.stageDeleteCount, 1);
    expect(files.handles.single.closeCount, 1);
  });

  test('unsafe redirect failure still closes and deletes the staged snapshot',
      () async {
    final _FakeStagingOperations files = _FakeStagingOperations();
    const String path = '/recordings/part.wav';
    final List<int> bytes =
        Uint8List.fromList('redirect-failure-recording'.codeUnits);
    files.put(path, bytes);
    adapter.enqueue(
      307,
      headers: <String, List<String>>{
        'location': <String>['https://attacker.example/upload'],
      },
    );
    final RecordingPartMultipartUploader uploader =
        _uploaderWithFakeFiles(files);

    await expectLater(
      _upload(
        uploader,
        path: path,
        hash: sha256.convert(bytes).toString(),
        length: bytes.length,
      ),
      throwsA(isA<UploadException>()),
    );

    expect(adapter.requests, hasLength(1));
    expect(_extractMultipartFile(adapter.requestBodies.single),
        orderedEquals(bytes));
    expect(files.stageDeleteCount, 1);
    expect(files.handles.single.closeCount, 1);
  });

  test('mocked non-success response still closes and deletes the stage',
      () async {
    final _FakeStagingOperations files = _FakeStagingOperations();
    const String path = '/recordings/part.wav';
    final List<int> bytes =
        Uint8List.fromList('validation-response-recording'.codeUnits);
    files.put(path, bytes);
    adapter.enqueue(422, body: 'invalid recording part');
    final RecordingPartMultipartUploader uploader =
        _uploaderWithFakeFiles(files);

    final Response<dynamic> response = await _upload(
      uploader,
      path: path,
      hash: sha256.convert(bytes).toString(),
      length: bytes.length,
    );

    expect(response.statusCode, 422);
    expect(adapter.requests, hasLength(1));
    expect(_extractMultipartFile(adapter.requestBodies.single),
        orderedEquals(bytes));
    expect(files.stageDeleteCount, 1);
    expect(files.handles.single.closeCount, 1);
  });

  test('mocked transport failure still closes and deletes the stage', () async {
    final _FakeStagingOperations files = _FakeStagingOperations();
    const String path = '/recordings/part.wav';
    final List<int> bytes =
        Uint8List.fromList('transport-failure-recording'.codeUnits);
    files.put(path, bytes);
    adapter.enqueueError(const SocketException('Injected transport failure.'));
    final RecordingPartMultipartUploader uploader =
        _uploaderWithFakeFiles(files);

    await expectLater(
      _upload(
        uploader,
        path: path,
        hash: sha256.convert(bytes).toString(),
        length: bytes.length,
      ),
      throwsA(anything),
    );

    expect(adapter.requests, hasLength(1));
    expect(_extractMultipartFile(adapter.requestBodies.single),
        orderedEquals(bytes));
    expect(files.stageDeleteCount, 1);
    expect(files.handles.single.closeCount, 1);
  });

  test('successful response survives staged-file delete failure', () async {
    final List<Object> reportedCleanupErrors = <Object>[];
    final _FakeStagingOperations files = _FakeStagingOperations()
      ..throwDuringDelete = true;
    const String path = '/recordings/part.wav';
    final List<int> bytes =
        Uint8List.fromList('successful-remote-commit'.codeUnits);
    files.put(path, bytes);
    adapter.enqueue(201, body: '901');
    final RecordingPartMultipartUploader uploader = _uploaderWithFakeFiles(
      files,
      onCleanupError: (Object error, StackTrace _) {
        reportedCleanupErrors.add(error);
      },
    );

    final Response<dynamic> response = await _upload(
      uploader,
      path: path,
      hash: sha256.convert(bytes).toString(),
      length: bytes.length,
    );

    expect(response.statusCode, 201);
    expect(response.data, '901');
    expect(files.stageDeleteCount, 1);
    expect(files.handles.single.closeCount, 1);
    expect(reportedCleanupErrors.single, isA<FileSystemException>());
  });

  test('successful response survives handle close failure and still deletes',
      () async {
    final List<Object> reportedCleanupErrors = <Object>[];
    final _FakeStagingOperations files = _FakeStagingOperations()
      ..throwDuringHandleClose = true;
    const String path = '/recordings/part.wav';
    final List<int> bytes =
        Uint8List.fromList('successful-close-failure'.codeUnits);
    files.put(path, bytes);
    adapter.enqueue(201, body: '902');
    final RecordingPartMultipartUploader uploader = _uploaderWithFakeFiles(
      files,
      onCleanupError: (Object error, StackTrace _) {
        reportedCleanupErrors.add(error);
      },
    );

    final Response<dynamic> response = await _upload(
      uploader,
      path: path,
      hash: sha256.convert(bytes).toString(),
      length: bytes.length,
    );

    expect(response.statusCode, 201);
    expect(response.data, '902');
    expect(files.handles.single.closeCount, 1);
    expect(files.stageDeleteCount, 1);
    expect(reportedCleanupErrors.single, isA<FileSystemException>());
  });

  test('primary transport error survives a simultaneous cleanup failure',
      () async {
    final List<Object> reportedCleanupErrors = <Object>[];
    final _FakeStagingOperations files = _FakeStagingOperations()
      ..throwDuringDelete = true;
    const String path = '/recordings/part.wav';
    final List<int> bytes =
        Uint8List.fromList('transport-and-cleanup-failure'.codeUnits);
    files.put(path, bytes);
    adapter.enqueueError(const SocketException('Primary transport failure.'));
    final RecordingPartMultipartUploader uploader = _uploaderWithFakeFiles(
      files,
      onCleanupError: (Object error, StackTrace _) {
        reportedCleanupErrors.add(error);
      },
    );

    await expectLater(
      _upload(
        uploader,
        path: path,
        hash: sha256.convert(bytes).toString(),
        length: bytes.length,
      ),
      throwsA(isA<DioException>()),
    );

    expect(files.stageDeleteCount, 1);
    expect(files.handles.single.closeCount, 1);
    expect(reportedCleanupErrors.single, isA<FileSystemException>());
  });

  test('partial staging failure deletes its private temporary directory',
      () async {
    final _FakeStagingOperations files = _FakeStagingOperations()
      ..throwDuringWrite = true;
    const String path = '/recordings/part.wav';
    final List<int> bytes =
        Uint8List.fromList('copy-failure-recording'.codeUnits);
    files.put(path, bytes);
    final RecordingPartMultipartUploader uploader =
        _uploaderWithFakeFiles(files);

    await expectLater(
      _upload(
        uploader,
        path: path,
        hash: sha256.convert(bytes).toString(),
        length: bytes.length,
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(adapter.requests, isEmpty);
    expect(files.stageCreateCount, 1);
    expect(files.stageDeleteCount, 1);
    expect(files.handles, isEmpty);
  });

  test('partial-stage delete failure is reported without hiding copy failure',
      () async {
    final List<Object> reportedCleanupErrors = <Object>[];
    final _FakeStagingOperations files = _FakeStagingOperations()
      ..throwDuringWrite = true
      ..throwDuringDelete = true;
    const String path = '/recordings/part.wav';
    final List<int> bytes =
        Uint8List.fromList('copy-and-delete-failure'.codeUnits);
    files.put(path, bytes);
    final RecordingPartMultipartUploader uploader = _uploaderWithFakeFiles(
      files,
      onCleanupError: (Object error, StackTrace _) {
        reportedCleanupErrors.add(error);
      },
    );

    await expectLater(
      _upload(
        uploader,
        path: path,
        hash: sha256.convert(bytes).toString(),
        length: bytes.length,
      ),
      throwsA(
        isA<FileSystemException>().having(
          (FileSystemException error) => error.message,
          'primary message',
          contains('staged write'),
        ),
      ),
    );

    expect(adapter.requests, isEmpty);
    expect(files.stageDeleteCount, 1);
    expect(
      reportedCleanupErrors.single,
      isA<FileSystemException>().having(
        (FileSystemException error) => error.message,
        'cleanup message',
        contains('stage deletion'),
      ),
    );
  });

  test('stale crash-stage cleanup is bounded in age and never blocks upload',
      () async {
    final _FakeStagingOperations files = _FakeStagingOperations()
      ..throwDuringStaleCleanup = true;
    const String path = '/recordings/part.wav';
    final List<int> bytes =
        Uint8List.fromList('stale-cleanup-is-ancillary'.codeUnits);
    files.put(path, bytes);
    adapter.enqueue(201, body: '903');
    final DateTime now = DateTime.utc(2026, 7, 18, 12);
    final RecordingPartMultipartUploader uploader =
        RecordingPartMultipartUploader(
      snapshots: ImmutableUploadSnapshotFactory(
        operations: files,
        staleStageLifetime: const Duration(hours: 6),
        now: () => now,
      ),
    );

    final Response<dynamic> response = await _upload(
      uploader,
      path: path,
      hash: sha256.convert(bytes).toString(),
      length: bytes.length,
    );

    expect(response.statusCode, 201);
    expect(files.staleCleanupCount, 1);
    expect(files.lastStaleCutoff, DateTime.utc(2026, 7, 18, 6));
    expect(files.stageDeleteCount, 1);
  });

  for (final _InfrastructureFailure failure in _InfrastructureFailure.values) {
    test(
        '${failure.name} staging I/O failure stays retryable and sends no '
        'mocked API bytes', () async {
      final _FakeStagingOperations files = _FakeStagingOperations();
      switch (failure) {
        case _InfrastructureFailure.create:
          files.throwDuringCreate = true;
        case _InfrastructureFailure.write:
          files.throwDuringWrite = true;
        case _InfrastructureFailure.open:
          files.throwDuringOpen = true;
      }
      const String path = '/recordings/part.wav';
      final List<int> bytes =
          Uint8List.fromList('retryable-staging-infrastructure'.codeUnits);
      files.put(path, bytes);
      final RecordingPartMultipartUploader uploader =
          _uploaderWithFakeFiles(files);

      await expectLater(
        _upload(
          uploader,
          path: path,
          hash: sha256.convert(bytes).toString(),
          length: bytes.length,
        ),
        throwsA(
          allOf(
            isA<FileSystemException>(),
            isNot(isA<ImmutableUploadSourceException>()),
          ),
        ),
      );

      expect(adapter.requests, isEmpty);
      expect(adapter.requestBodies, isEmpty);
      expect(files.stageCreateCount, 1);
      expect(
        files.stageDeleteCount,
        failure == _InfrastructureFailure.create ? 0 : 1,
      );
    });
  }

  test('source read failure is classified as frozen-source validation',
      () async {
    final _FakeStagingOperations files = _FakeStagingOperations()
      ..throwDuringSourceRead = true;
    const String path = '/recordings/part.wav';
    final List<int> bytes =
        Uint8List.fromList('unreadable-frozen-source'.codeUnits);
    files.put(path, bytes);
    final RecordingPartMultipartUploader uploader =
        _uploaderWithFakeFiles(files);

    await expectLater(
      _upload(
        uploader,
        path: path,
        hash: sha256.convert(bytes).toString(),
        length: bytes.length,
      ),
      throwsA(isA<ImmutableUploadSourceException>()),
    );

    expect(adapter.requests, isEmpty);
    expect(files.stageDeleteCount, 1);
  });

  test('snapshot replay keeps memory bounded to fixed read chunks', () async {
    final _FakeStagingOperations files = _FakeStagingOperations();
    const String path = '/recordings/large.wav';
    final Uint8List bytes = Uint8List(300000);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = index % 251;
    }
    files.put(path, bytes);
    final ImmutableUploadFileSnapshot snapshot =
        await ImmutableUploadSnapshotFactory(operations: files).stage(
      sourcePath: path,
      expectedSha256: sha256.convert(bytes).toString(),
      expectedByteLength: bytes.length,
    );

    final BytesBuilder firstReplay = BytesBuilder(copy: false);
    await for (final List<int> chunk in snapshot.openRead()) {
      expect(chunk.length, lessThanOrEqualTo(64 * 1024));
      firstReplay.add(chunk);
    }
    final BytesBuilder secondReplay = BytesBuilder(copy: false);
    await for (final List<int> chunk in snapshot.openRead()) {
      expect(chunk.length, lessThanOrEqualTo(64 * 1024));
      secondReplay.add(chunk);
    }
    await snapshot.dispose();

    expect(firstReplay.takeBytes(), orderedEquals(bytes));
    expect(secondReplay.takeBytes(), orderedEquals(bytes));
    expect(files.handles.single.maxReadSize, lessThanOrEqualTo(64 * 1024));
    expect(files.stageDeleteCount, 1);
  });
}

RecordingPartMultipartUploader _uploaderWithFakeFiles(
  _FakeStagingOperations files, {
  void Function(Object error, StackTrace stackTrace)? onCleanupError,
}) {
  return RecordingPartMultipartUploader(
    snapshots: ImmutableUploadSnapshotFactory(operations: files),
    onCleanupError: onCleanupError,
  );
}

Future<Response<dynamic>> _upload(
  RecordingPartMultipartUploader uploader, {
  required String path,
  required String hash,
  required int length,
  Future<void> Function()? beforePost,
}) {
  return uploader.upload(
    filePath: path,
    expectedSha256: hash,
    expectedByteLength: length,
    backendRecordingId: 601,
    startDate: DateTime.utc(2026, 7, 18, 8),
    endDate: DateTime.utc(2026, 7, 18, 8, 0, 12),
    gpsLatitudeStart: 49.1,
    gpsLatitudeEnd: 49.2,
    gpsLongitudeStart: 16.5,
    gpsLongitudeEnd: 16.6,
    accessToken: 'captured-token',
    idempotencyKey: 'recording-part:stable-key',
    host: 'api.example.test',
    beforePost: beforePost ?? () async {},
  );
}

class _CapturingAdapter implements HttpClientAdapter {
  final Queue<_AdapterResponse> _responses = Queue<_AdapterResponse>();
  final List<RequestOptions> requests = <RequestOptions>[];
  final List<Uint8List> requestBodies = <Uint8List>[];
  void Function(int requestIndex)? afterBody;

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

  void enqueueError(Object error) {
    _responses.add(_AdapterResponse.error(error));
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
    final BytesBuilder requestBody = BytesBuilder(copy: false);
    if (requestStream != null) {
      await for (final Uint8List chunk in requestStream) {
        requestBody.add(chunk);
      }
    }
    requestBodies.add(requestBody.takeBytes());
    afterBody?.call(requestBodies.length - 1);

    final _AdapterResponse response = _responses.removeFirst();
    if (response.error != null) throw response.error!;
    return ResponseBody.fromString(
      response.body!,
      response.statusCode!,
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
  }) : error = null;

  const _AdapterResponse.error(this.error)
      : statusCode = null,
        body = null,
        headers = const <String, List<String>>{};

  final int? statusCode;
  final String? body;
  final Map<String, List<String>> headers;
  final Object? error;
}

class _FakeStagingOperations implements UploadFileStagingOperations {
  final Map<String, _FakeFileEntry> _entries = <String, _FakeFileEntry>{};
  final List<_FakeReadHandle> handles = <_FakeReadHandle>[];
  var stageCreateCount = 0;
  var stageDeleteCount = 0;
  var staleCleanupCount = 0;
  DateTime? lastStaleCutoff;
  var throwDuringStaleCleanup = false;
  var throwDuringCreate = false;
  var throwDuringWrite = false;
  var throwDuringSourceRead = false;
  var throwDuringOpen = false;
  var throwDuringDelete = false;
  var throwDuringHandleClose = false;
  void Function()? afterWrite;

  @override
  Future<void> deleteStaleStages({required DateTime olderThan}) async {
    staleCleanupCount++;
    lastStaleCutoff = olderThan;
    if (throwDuringStaleCleanup) {
      throw const FileSystemException('Injected stale-stage cleanup failure.');
    }
  }

  void put(String path, List<int> bytes) {
    _entries[path] = _FakeFileEntry(Uint8List.fromList(bytes));
  }

  void mutate(String path, List<int> bytes) {
    final _FakeFileEntry entry =
        _entries[path] ?? (throw StateError('Unknown fake file $path.'));
    entry.bytes = Uint8List.fromList(bytes);
    entry.revision++;
  }

  Uint8List bytesAt(String path) {
    return Uint8List.fromList(
      _entries[path]?.bytes ?? (throw StateError('Unknown fake file $path.')),
    );
  }

  @override
  Future<UploadSourceVersion?> stat(String path) async {
    final _FakeFileEntry? entry = _entries[path];
    if (entry == null) return null;
    final DateTime version = DateTime.fromMillisecondsSinceEpoch(
      entry.revision + 1,
      isUtc: true,
    );
    return UploadSourceVersion(
      isFile: true,
      size: entry.bytes.length,
      modified: version,
      changed: version,
    );
  }

  @override
  Stream<List<int>> openRead(String path) async* {
    if (throwDuringSourceRead) {
      throw FileSystemException('Injected source read failure.', path);
    }
    final Uint8List bytes = bytesAt(path);
    const int sourceChunkSize = 4096;
    for (var offset = 0; offset < bytes.length; offset += sourceChunkSize) {
      final int end = offset + sourceChunkSize < bytes.length
          ? offset + sourceChunkSize
          : bytes.length;
      yield Uint8List.sublistView(bytes, offset, end);
    }
  }

  @override
  Future<UploadStageLocation> createPrivateStage() async {
    stageCreateCount++;
    if (throwDuringCreate) {
      throw const FileSystemException('Injected stage creation failure.');
    }
    final String root = '/private-stage/$stageCreateCount';
    final String path = '$root/snapshot';
    put(path, const <int>[]);
    return UploadStageLocation(rootPath: root, filePath: path);
  }

  @override
  Future<void> writeStream(String path, Stream<List<int>> bytes) async {
    final BytesBuilder output = BytesBuilder(copy: false);
    await for (final List<int> chunk in bytes) {
      output.add(chunk);
      if (throwDuringWrite) {
        throw FileSystemException('Injected staged write failure.', path);
      }
    }
    mutate(path, output.takeBytes());
    afterWrite?.call();
  }

  @override
  Future<UploadSnapshotReadHandle> openReadHandle(String path) async {
    if (throwDuringOpen) {
      throw FileSystemException('Injected stage open failure.', path);
    }
    final _FakeReadHandle handle = _FakeReadHandle(
      bytesAt(path),
      throwDuringClose: throwDuringHandleClose,
    );
    handles.add(handle);
    return handle;
  }

  @override
  Future<void> deleteStage(UploadStageLocation location) async {
    stageDeleteCount++;
    if (throwDuringDelete) {
      throw FileSystemException(
        'Injected stage deletion failure.',
        location.rootPath,
      );
    }
    _entries.removeWhere(
      (String path, _FakeFileEntry _) =>
          path == location.rootPath || path.startsWith('${location.rootPath}/'),
    );
  }
}

class _FakeFileEntry {
  _FakeFileEntry(this.bytes);

  Uint8List bytes;
  int revision = 0;
}

class _FakeReadHandle implements UploadSnapshotReadHandle {
  _FakeReadHandle(
    List<int> bytes, {
    required this.throwDuringClose,
  }) : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;
  final bool throwDuringClose;
  var _position = 0;
  var closeCount = 0;
  var maxReadSize = 0;

  @override
  Future<void> setPosition(int position) async {
    if (closeCount > 0) throw StateError('Fake read handle is closed.');
    _position = position;
  }

  @override
  Future<List<int>> read(int byteCount) async {
    if (closeCount > 0) throw StateError('Fake read handle is closed.');
    if (byteCount > maxReadSize) maxReadSize = byteCount;
    if (_position >= _bytes.length) return Uint8List(0);
    final int end = _position + byteCount < _bytes.length
        ? _position + byteCount
        : _bytes.length;
    final Uint8List result = Uint8List.sublistView(_bytes, _position, end);
    _position = end;
    return result;
  }

  @override
  Future<void> close() async {
    closeCount++;
    if (throwDuringClose) {
      throw const FileSystemException(
          'Injected snapshot handle close failure.');
    }
  }
}

enum _InfrastructureFailure { create, write, open }

Uint8List _extractMultipartFile(Uint8List body) {
  final List<int> filenameMarker = 'filename="part.wav"'.codeUnits;
  final int filenameIndex = _indexOf(body, filenameMarker);
  if (filenameIndex < 0) {
    throw StateError('Multipart test body has no part.wav file header.');
  }
  final int contentStartMarker = _indexOf(
    body,
    const <int>[13, 10, 13, 10],
    start: filenameIndex + filenameMarker.length,
  );
  if (contentStartMarker < 0) {
    throw StateError('Multipart test body has no header terminator.');
  }
  final int contentStart = contentStartMarker + 4;
  final int contentEnd = _indexOf(
    body,
    const <int>[13, 10, 45, 45],
    start: contentStart,
  );
  if (contentEnd < 0) {
    throw StateError('Multipart test body has no closing boundary.');
  }
  return Uint8List.sublistView(body, contentStart, contentEnd);
}

int _indexOf(List<int> haystack, List<int> needle, {int start = 0}) {
  if (needle.isEmpty) return start;
  for (var index = start; index <= haystack.length - needle.length; index++) {
    var matches = true;
    for (var offset = 0; offset < needle.length; offset++) {
      if (haystack[index + offset] != needle[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return index;
  }
  return -1;
}
