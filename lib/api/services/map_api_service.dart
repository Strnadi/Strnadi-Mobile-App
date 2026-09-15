import 'dart:convert';

import 'package:strnadi/api/controllers/dialects_controller.dart';
import 'package:strnadi/api/controllers/recordings_controller.dart';
import 'package:strnadi/api/controllers/user_controller.dart';
import 'package:strnadi/api/models/map_clusters.dart';
import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/Models/userData.dart';
import 'package:strnadi/dialects/dialect_definition.dart';
import 'package:strnadi/dialects/dialect_keyword_translator.dart';

class ClusterSnapshotExpired implements Exception {}

class MapApiException implements Exception {
  const MapApiException(this.error);
  final MapClustersApiError error;

  @override
  String toString() => error.toLogMessage();
}

class MapRecordingDetail {
  const MapRecordingDetail(this.recording, this.user);
  final Recording recording;
  final UserData? user;
}

/// Typed boundary used by map state; callers never handle HTTP or JSON.
abstract interface class MapDataSource {
  Future<MapClustersResponse> fetchFeatures(
    MapClustersRequest request, {
    required String host,
  });
  Future<MapClusterItemsPage> fetchClusterItems(
    String clusterId,
    String cursor, {
    required String host,
  });
  Future<MapRecordingDetail> fetchRecording(
    int recordingId, {
    required String host,
  });
  Future<List<String>> fetchLegend({required String host});
}

class MapApiService implements MapDataSource {
  const MapApiService({
    RecordingsController recordings = const RecordingsController(),
    UserController users = const UserController(),
    DialectsController dialects = const DialectsController(),
  }) : _recordings = recordings,
       _users = users,
       _dialects = dialects;

  final RecordingsController _recordings;
  final UserController _users;
  final DialectsController _dialects;

  @override
  Future<MapClustersResponse> fetchFeatures(
    MapClustersRequest request, {
    required String host,
  }) async {
    final response = await _recordings.fetchMapClusters(request, host: host);
    if (response.statusCode != 200) {
      throw MapApiException(
        MapClustersApiError.fromResponse(
          statusCode: response.statusCode,
          payload: response.data,
        ),
      );
    }
    return MapClustersResponse.fromResponseData(response.data);
  }

  @override
  Future<MapClusterItemsPage> fetchClusterItems(
    String clusterId,
    String cursor, {
    required String host,
  }) async {
    final response = await _recordings.fetchMapClusterItems(
      clusterId,
      cursor,
      host: host,
    );
    if (response.statusCode == 409 || response.statusCode == 410) {
      throw ClusterSnapshotExpired();
    }
    if (response.statusCode != 200) {
      throw const FormatException('Cluster items request failed.');
    }
    return MapClusterItemsPage.fromResponseData(response.data);
  }

  @override
  Future<MapRecordingDetail> fetchRecording(
    int recordingId, {
    required String host,
  }) async {
    final response = await _recordings.fetchRecordingById(
      recordingId,
      host: host,
      includeParts: true,
    );
    if (response.statusCode != 200) {
      throw const FormatException('Recording request failed.');
    }
    final recording = Recording.fromBEJson(_object(response.data), null);
    UserData? user;
    if (recording.userId != null) {
      try {
        final profile = await _users.getUserById(recording.userId!, host: host);
        if (profile.statusCode == 200) {
          user = UserData.fromJson(_object(profile.data));
        }
      } catch (_) {
        // An unavailable author profile must not prevent opening a recording.
      }
    }
    return MapRecordingDetail(recording, user);
  }

  @override
  Future<List<String>> fetchLegend({required String host}) async {
    final response = await _dialects.fetchDialectPalette(host: host);
    if (response.statusCode != 200) {
      throw const FormatException('Dialect legend request failed.');
    }
    final payload = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    return visibleDialectHintCodes(payload)
        .map((code) => DialectKeywordTranslator.toEnglish(code) ?? code.trim())
        .map(
          (code) => switch (code) {
            'Unassessed' || 'Undetermined' || 'Unknown dialect' => 'Unknown',
            _ => code,
          },
        )
        .where((code) => code.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  static Map<String, dynamic> _object(dynamic data) {
    final decoded = data is String ? jsonDecode(data) : data;
    if (decoded is! Map) throw const FormatException('Expected an object.');
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
}
