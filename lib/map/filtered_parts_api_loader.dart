import 'dart:convert';

import 'package:logger/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/api/controllers/filtered_recordings_controller.dart';
import 'package:strnadi/database/Models/detectedDialect.dart';
import 'package:strnadi/database/Models/filteredRecordingPart.dart';

class FilteredPartsBundle {
  const FilteredPartsBundle({
    required this.frps,
    required this.dds,
  });

  final List<FilteredRecordingPart> frps;
  final List<DetectedDialect> dds;
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
        );
      }
      if (resp.statusCode != 200) {
        _logger?.e(
          '[MapV2] /recordings/filtered failed: ${resp.statusCode} body=${resp.data}',
        );
        return const FilteredPartsBundle(
          frps: <FilteredRecordingPart>[],
          dds: <DetectedDialect>[],
        );
      }

      final dynamic decoded =
          resp.data is String ? jsonDecode(resp.data as String) : resp.data;
      if (decoded is! List) {
        _logger?.w('[MapV2] /recordings/filtered returned non-list payload');
        return const FilteredPartsBundle(
          frps: <FilteredRecordingPart>[],
          dds: <DetectedDialect>[],
        );
      }

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
          final row = DetectedDialect.fromBEJson(
            d,
            parentFilteredPartBEID: frp.BEId ?? -1,
          );
          dds.add(row);
        }
      }

      _logger?.i(
        '[MapV2] /recordings/filtered parsed: FRPs=${frps.length}, DDs=${dds.length}',
      );
      return FilteredPartsBundle(frps: frps, dds: dds);
    } catch (e, st) {
      _logger?.e('[MapV2] /recordings/filtered exception: $e',
          error: e, stackTrace: st);
      Sentry.captureException(e, stackTrace: st);
      return const FilteredPartsBundle(
        frps: <FilteredRecordingPart>[],
        dds: <DetectedDialect>[],
      );
    }
  }
}
