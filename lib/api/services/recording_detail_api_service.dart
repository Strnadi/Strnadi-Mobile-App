import 'dart:convert';

import 'package:strnadi/api/controllers/filtered_recordings_controller.dart';

/// Decodes the recording-detail API response before it reaches presentation.
class RecordingDetailApiService {
  const RecordingDetailApiService({
    FilteredRecordingsController controller =
        const FilteredRecordingsController(),
  }) : _controller = controller;

  final FilteredRecordingsController _controller;

  Future<List<Map<String, dynamic>>> fetchDialectParts(
    int recordingId, {
    required String host,
  }) async {
    final response = await _controller.fetchFilteredParts(
      recordingId: recordingId,
      verified: false,
      host: host,
    );
    if (response.statusCode == 204) return const [];
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final dynamic decoded = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    if (decoded is! List) return const [];
    return decoded.whereType<Map<String, dynamic>>().toList(growable: false);
  }
}
