import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/Models/recordingPart.dart';
import 'package:strnadi/map/recording_detail/recording_audio_player.dart';
import 'package:strnadi/map/recording_detail/recording_detail_controller.dart';
import 'package:strnadi/map/recording_detail/recording_detail_repository.dart';

Recording recording({String? path, bool downloaded = false}) => Recording(
  id: 7,
  BEId: 700,
  userId: 42,
  createdAt: DateTime.utc(2026, 9, 15, 10),
  estimatedBirdsCount: 1,
  byApp: true,
  partCount: 1,
  totalSeconds: 20,
  env: 'prod',
  path: path,
  downloaded: downloaded,
);

const ownerScope = RecordingDetailScope(
  host: 'api.example.test',
  environment: 'prod',
  sessionId: 'owner-session',
  userId: 42,
  role: 'user',
);

const otherScope = RecordingDetailScope(
  host: 'api.example.test',
  environment: 'prod',
  sessionId: 'other-session',
  userId: 8,
  role: 'user',
);

class FakeRepository implements RecordingDetailRepository {
  RecordingDetailScope scope = ownerScope;
  Recording? resolved;
  bool failCache = false;
  List<RecordingPart> parts = [];
  final dialectStarted = Completer<void>();
  Completer<List<Map<String, dynamic>>>? dialectPending;
  List<Map<String, dynamic>> dialectPayload = [];
  final downloadStarted = Completer<void>();
  final downloadPending = Completer<Recording?>();
  CancelToken? token;
  void Function(double)? progress;
  int? downloadedBackendId;

  @override
  Future<RecordingDetailScope> captureScope() async => scope;
  @override
  Future<Recording?> resolveRecording(Recording input) async {
    if (failCache) throw StateError('cache unavailable');
    return resolved ?? input;
  }

  @override
  Future<List<RecordingPart>> loadParts(int localId) async => List.of(parts);
  @override
  Future<Recording?> downloadByBackendId(
    int backendId, {
    required CancelToken cancelToken,
    required void Function(double) onProgress,
  }) {
    downloadedBackendId = backendId;
    token = cancelToken;
    progress = onProgress;
    downloadStarted.complete();
    return downloadPending.future;
  }

  @override
  Future<List<Map<String, dynamic>>> loadDialectParts(
    int backendId,
    String host,
  ) {
    if (!dialectStarted.isCompleted) dialectStarted.complete();
    return dialectPending?.future ?? Future.value(dialectPayload);
  }

  @override
  Future<List<Color>> loadDialectColors(List<String> codes) async =>
      List.filled(codes.length, Colors.green);
  @override
  Future<String?> reverseGeocode(
    double latitude,
    double longitude,
    String host,
  ) async => 'Praha';
}

class FakeAudio implements RecordingAudioPlayer {
  final positions = StreamController<Duration>.broadcast(sync: true);
  final durations = StreamController<Duration?>.broadcast(sync: true);
  final playingEvents = StreamController<bool>.broadcast(sync: true);
  final seeks = <Duration>[];
  final paths = <String>[];
  bool disposed = false;
  @override
  bool playing = false;
  @override
  Duration? duration = const Duration(seconds: 20);
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<Duration?> get durationStream => durations.stream;
  @override
  Stream<bool> get playingStream => playingEvents.stream;
  @override
  Future<void> setFilePath(String path) async {
    paths.add(path);
  }

  @override
  Future<void> play() async {
    playing = true;
    playingEvents.add(true);
  }

  @override
  Future<void> pause() async {
    playing = false;
    playingEvents.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await Future.wait([
      positions.close(),
      durations.close(),
      playingEvents.close(),
    ]);
  }
}

void main() {
  late FakeRepository repository;
  late FakeAudio audio;
  late RecordingDetailController detail;
  setUp(() {
    repository = FakeRepository();
    audio = FakeAudio();
    detail = RecordingDetailController(
      recording: recording(),
      audio: audio,
      repository: repository,
    );
  });
  tearDown(() {
    if (!audio.disposed) detail.dispose();
  });

  test(
    'pending initialization shows dialect loading until API completes',
    () async {
      expect(detail.dialectsLoading, isTrue);
      repository.dialectPending = Completer();
      final pending = detail.initialize();
      await repository.dialectStarted.future;
      expect(detail.dialectsLoading, isTrue);
      repository.dialectPending!.complete([]);
      await pending;
      expect(detail.dialectsLoading, isFalse);
      expect(detail.dialectsError, isNull);
    },
  );

  test('cache failure does not suppress available remote dialects', () async {
    repository.failCache = true;
    repository.dialectPayload = [
      {
        'startDate': '1970-01-01T00:00:01Z',
        'endDate': '1970-01-01T00:00:04Z',
        'detectedDialects': [
          {'confirmedDialect': 'BC'},
        ],
      },
    ];
    await detail.initialize();
    expect(detail.loaded, isTrue);
    expect(detail.dialectsLoading, isFalse);
    expect(detail.dialectsError, isNull);
    expect(detail.dialectEntries.single.canonicalCode, 'BC');
  });

  test(
    'owner playback access resolves without opening a database or API',
    () async {
      await detail.initialize();
      expect(detail.loaded, isTrue);
      expect(detail.canAccessPlayback, isTrue);
      expect(detail.playAccessResolved, isTrue);
      expect(detail.playbackDuration, const Duration(seconds: 20));
      expect(
        await detail.togglePlay(),
        RecordingDetailActionResult.unavailable,
      );
    },
  );

  test(
    'nonowner cannot load cached audio, download, or start playback',
    () async {
      repository.scope = otherScope;
      repository.resolved = recording(
        path: '/fake/existing.wav',
        downloaded: true,
      );
      await detail.initialize();
      expect(detail.canAccessPlayback, isFalse);
      expect(audio.paths, isEmpty);
      expect(await detail.togglePlay(), RecordingDetailActionResult.restricted);
      expect(await detail.download(), RecordingDetailActionResult.restricted);
      expect(repository.downloadedBackendId, isNull);
    },
  );

  test('seeks clamp and replay starts at zero at the end of audio', () async {
    repository.resolved = recording(
      path: '/fake/existing.wav',
      downloaded: true,
    );
    await detail.initialize();
    audio.positions.add(const Duration(seconds: 2));
    await detail.seekRelative(-10);
    audio.positions.add(const Duration(seconds: 18));
    await detail.seekRelative(10);
    audio.positions.add(const Duration(seconds: 20));
    expect(await detail.togglePlay(), RecordingDetailActionResult.success);
    expect(audio.seeks, [
      Duration.zero,
      const Duration(seconds: 20),
      Duration.zero,
    ]);
    expect(audio.playing, isTrue);
  });

  test(
    'download uses backend id and publishes progress then local cache',
    () async {
      await detail.initialize();
      final pending = detail.download();
      await repository.downloadStarted.future;
      expect(repository.downloadedBackendId, 700);
      expect(detail.loaded, isFalse);
      repository.progress!(0.42);
      expect(detail.downloadProgress, 0.42);
      final downloaded = recording(
        path: '/fake/downloaded.wav',
        downloaded: true,
      );
      repository.resolved = downloaded;
      repository.downloadPending.complete(downloaded);
      expect(await pending, RecordingDetailActionResult.success);
      expect(detail.recording.downloaded, isTrue);
      expect(audio.paths, ['/fake/downloaded.wav']);
      expect(detail.loaded, isTrue);
      expect(detail.isDownloading, isFalse);
    },
  );

  test(
    'cancel keeps recording and clears loading so download can be retried',
    () async {
      await detail.initialize();
      final pending = detail.download();
      await repository.downloadStarted.future;
      detail.cancelDownload();
      expect(repository.token!.isCancelled, isTrue);
      repository.downloadPending.completeError(
        DioException(
          requestOptions: RequestOptions(path: '/recordings/700'),
          type: DioExceptionType.cancel,
        ),
      );
      expect(await pending, RecordingDetailActionResult.canceled);
      expect(detail.recording.BEId, 700);
      expect(detail.recording.id, 7);
      expect(detail.loaded, isTrue);
      expect(detail.isDownloading, isFalse);
    },
  );

  test(
    'late dialect response cannot populate a different auth session',
    () async {
      repository.dialectPending = Completer();
      final pending = detail.initialize();
      await repository.dialectStarted.future;
      repository.scope = otherScope;
      repository.dialectPending!.complete([
        {
          'startDate': '1970-01-01T00:00:01Z',
          'endDate': '1970-01-01T00:00:04Z',
          'detectedDialects': [
            {'confirmedDialect': 'BC'},
          ],
        },
      ]);
      await pending;
      expect(detail.dialectEntries, isEmpty);
      expect(detail.canAccessPlayback, isFalse);
      expect(detail.dialectsLoading, isFalse);
    },
  );

  test('host changes discard a pending download result', () async {
    await detail.initialize();
    final pending = detail.download();
    await repository.downloadStarted.future;
    repository.scope = const RecordingDetailScope(
      host: 'preprod.example.test',
      environment: 'preprod',
      sessionId: 'owner-session',
      userId: 42,
      role: 'user',
    );
    repository.downloadPending.complete(
      recording(path: '/fake/stale.wav', downloaded: true),
    );
    expect(await pending, RecordingDetailActionResult.stale);
    expect(detail.recording.path, isNull);
    expect(audio.paths, isEmpty);
    expect(detail.canAccessPlayback, isFalse);
    expect(repository.token!.isCancelled, isTrue);
  });

  test(
    'dispose cancels download, subscriptions, and rejects completion',
    () async {
      await detail.initialize();
      final pending = detail.download();
      await repository.downloadStarted.future;
      var notifications = 0;
      detail.addListener(() => notifications++);
      detail.dispose();
      expect(repository.token!.isCancelled, isTrue);
      expect(audio.disposed, isTrue);
      repository.progress!(0.8);
      repository.downloadPending.complete(
        recording(path: '/fake/stale.wav', downloaded: true),
      );
      expect(await pending, RecordingDetailActionResult.stale);
      expect(notifications, 0);
      expect(detail.recording.path, isNull);
    },
  );
}
