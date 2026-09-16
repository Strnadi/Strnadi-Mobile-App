import 'dart:convert';

import 'package:strnadi/api/controllers/filtered_recordings_controller.dart';
import 'package:strnadi/api/api_logging.dart';
import 'package:strnadi/exceptions.dart';

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
      throw FetchException(
        'Recording dialect parts request failed.',
        response.statusCode ?? 500,
        logFailure: apiFailureForResponse(response),
      );
    }
    final dynamic decoded = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    if (decoded is! List) return const [];
    return decoded.whereType<Map<String, dynamic>>().toList(growable: false);
  }
}
