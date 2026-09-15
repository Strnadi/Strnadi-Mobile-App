import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/api/controllers/maps_controller.dart';
import 'package:strnadi/api/services/recording_detail_api_service.dart';
import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:strnadi/auth/user_identity.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/Models/recordingPart.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/dialects/dynamicIcon.dart';

class RecordingDetailScope {
  const RecordingDetailScope({
    required this.host,
    required this.environment,
    required this.sessionId,
    required this.userId,
    required this.role,
  });

  final String host;
  final String environment;
  final String? sessionId;
  final Object? userId;
  final String role;

  bool canPlay(Recording recording) =>
      role == 'admin' || (userId != null && userId == recording.userId);

  @override
  bool operator ==(Object other) =>
      other is RecordingDetailScope &&
      other.host == host &&
      other.environment == environment &&
      other.sessionId == sessionId &&
      other.userId == userId &&
      other.role == role;

  @override
  int get hashCode => Object.hash(host, environment, sessionId, userId, role);
}

abstract interface class RecordingDetailRepository {
  Future<RecordingDetailScope> captureScope();
  Future<Recording?> resolveRecording(Recording recording);
  Future<List<RecordingPart>> loadParts(int localId);
  Future<Recording?> downloadByBackendId(
    int backendId, {
    required CancelToken cancelToken,
    required void Function(double) onProgress,
  });
  Future<List<Map<String, dynamic>>> loadDialectParts(
    int backendId,
    String host,
  );
  Future<List<Color>> loadDialectColors(List<String> codes);
  Future<String?> reverseGeocode(
    double latitude,
    double longitude,
    String host,
  );
}

class DatabaseRecordingDetailRepository implements RecordingDetailRepository {
  const DatabaseRecordingDetailRepository({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
    RecordingDetailApiService api = const RecordingDetailApiService(),
    MapsController maps = const MapsController(),
  }) : _storage = storage,
       _api = api,
       _maps = maps;

  final FlutterSecureStorage _storage;
  final RecordingDetailApiService _api;
  final MapsController _maps;

  @override
  Future<RecordingDetailScope> captureScope() async {
    final host = Config.host;
    final environment = Config.dataEnvironment;
    final session = await activatedAuthSessions.capture();
    final userId = parseUserId(
      (await _storage.read(key: 'userId') ?? '').trim(),
    );
    final role = (await _storage.read(key: 'role') ?? '').toLowerCase();
    return RecordingDetailScope(
      host: host,
      environment: environment,
      sessionId: session?.sessionId,
      userId: userId,
      role: role,
    );
  }

  @override
  Future<Recording?> resolveRecording(Recording recording) async {
    if (recording.id != null) {
      final local = await DatabaseNew.getRecordingFromDbByIdNoMail(
        recording.id!,
      );
      if (local != null) return local;
    }
    final backendId = recording.BEId;
    if (backendId == null) return null;
    final cached = await DatabaseNew.getRecordingFromDbByBEId(backendId);
    if (cached != null) return cached;
    final localId = await DatabaseNew.fetchRecordingFromBE(backendId);
    return localId == null
        ? null
        : DatabaseNew.getRecordingFromDbByIdNoMail(localId);
  }

  @override
  Future<List<RecordingPart>> loadParts(int localId) =>
      DatabaseNew.getPartsByRecordingId(localId);

  @override
  Future<Recording?> downloadByBackendId(
    int backendId, {
    required CancelToken cancelToken,
    required void Function(double) onProgress,
  }) async {
    final localId = await DatabaseNew.downloadRecordingByBackendId(
      backendId,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );
    return DatabaseNew.getRecordingFromDbByIdNoMail(localId);
  }

  @override
  Future<List<Map<String, dynamic>>> loadDialectParts(
    int backendId,
    String host,
  ) => _api.fetchDialectParts(backendId, host: host);

  @override
  Future<List<Color>> loadDialectColors(List<String> codes) =>
      DialectColorCache.getColors(codes);

  @override
  Future<String?> reverseGeocode(
    double latitude,
    double longitude,
    String host,
  ) => _maps.reverseGeocode(latitude, longitude, host: host);
}
