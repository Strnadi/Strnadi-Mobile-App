import 'dart:convert';

import 'package:logger/logger.dart';
import 'package:strnadi/api/controllers/filtered_recordings_controller.dart';
import 'package:strnadi/database/Models/detectedDialect.dart';
import 'package:strnadi/database/Models/filteredRecordingPart.dart';

class FilteredPartsBundle {
  const FilteredPartsBundle({
    required this.frps,
    required this.dds,
    required this.isAvailable,
    required this.sourcePayload,
  });

  final List<FilteredRecordingPart> frps;
  final List<DetectedDialect> dds;
  final bool isAvailable;
  final List<dynamic> sourcePayload;

  static const FilteredPartsBundle unavailable = FilteredPartsBundle(
    frps: <FilteredRecordingPart>[],
    dds: <DetectedDialect>[],
    isAvailable: false,
    sourcePayload: <dynamic>[],
  );
}

class FilteredPartsApiLoader {
  const FilteredPartsApiLoader({
    FilteredRecordingsController controller =
        const FilteredRecordingsController(),
    Logger? logger,
  })  : _controller = controller,
        _logger = logger;

  final FilteredRecordingsController _controller;
  final Logger? _logger;

  static FilteredPartsBundle parsePayload(List<dynamic> decoded) {
    final frps = <FilteredRecordingPart>[];
    final dds = <DetectedDialect>[];

    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      final frp = FilteredRecordingPart.fromBEJson(item);
      frps.add(frp);

      final List<dynamic>? dialects =
          item['detectedDialects'] as List<dynamic>?;
      if (dialects == null) continue;
      for (final d in dialects) {
        if (d is! Map<String, dynamic>) continue;
        dds.add(DetectedDialect.fromBEJson(
          d,
          parentFilteredPartBEID: frp.BEId ?? -1,
        ));
      }
    }

    return FilteredPartsBundle(
      frps: frps,
      dds: dds,
      isAvailable: true,
      sourcePayload: List<dynamic>.from(decoded),
    );
  }

  Future<FilteredPartsBundle> fetch({
    int? recordingId,
    required bool verified,
  }) async {
    try {
      _logger?.i(
          '[MapV2] GET /recordings/filtered recordingId=$recordingId verified=$verified');
      final resp = await _controller.fetchFilteredParts(
        recordingId: recordingId,
        verified: verified,
      );

      if (resp.statusCode == 204) {
        _logger?.i('[MapV2] /recordings/filtered returned 204 No Content');
        return const FilteredPartsBundle(
          frps: <FilteredRecordingPart>[],
          dds: <DetectedDialect>[],
          isAvailable: true,
          sourcePayload: <dynamic>[],
        );
      }
      if (resp.statusCode != 200) {
        _logger?.w(
          '[MapV2] /recordings/filtered unavailable: ${resp.statusCode}',
        );
        return FilteredPartsBundle.unavailable;
      }

      final dynamic decoded =
          resp.data is String ? jsonDecode(resp.data as String) : resp.data;
      if (decoded is! List) {
        _logger?.w('[MapV2] /recordings/filtered returned non-list payload');
        return FilteredPartsBundle.unavailable;
      }

      final FilteredPartsBundle bundle = parsePayload(decoded);

      _logger?.i(
        '[MapV2] /recordings/filtered parsed: FRPs=${bundle.frps.length}, DDs=${bundle.dds.length}',
      );
      return bundle;
    } catch (e) {
      _logger?.w(
        '[MapV2] /recordings/filtered unavailable: ${e.runtimeType}',
      );
      return FilteredPartsBundle.unavailable;
    }
  }
}
