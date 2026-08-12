/*
 * Copyright (C) 2025 Marian Pecqueur && Jan Drobílek
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class MapDataCacheEntry {
  const MapDataCacheEntry({
    required this.savedAt,
    required this.recordingsPayload,
    required this.filteredPartsPayload,
  });

  final DateTime savedAt;
  final List<dynamic> recordingsPayload;
  final List<dynamic> filteredPartsPayload;
}

abstract class MapDataCacheStore {
  Future<String?> read(String key);

  Future<void> write(String key, String contents);
}

class FileMapDataCacheStore implements MapDataCacheStore {
  const FileMapDataCacheStore();

  Future<File> _file(String key) async {
    final Directory supportDirectory = await getApplicationSupportDirectory();
    final Directory cacheDirectory =
        Directory('${supportDirectory.path}/map-data-cache');
    await cacheDirectory.create(recursive: true);
    return File('${cacheDirectory.path}/$key.json');
  }

  @override
  Future<String?> read(String key) async {
    final File file = await _file(key);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(String key, String contents) async {
    final File target = await _file(key);
    final File temporary = File('${target.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(target.path);
  }
}

class MapDataCache {
  MapDataCache({
    required this.scope,
    MapDataCacheStore store = const FileMapDataCacheStore(),
    DateTime Function()? now,
    this.maximumEntryBytes = 48 * 1024 * 1024,
  })  : _store = store,
        _now = now ?? DateTime.now;

  static const int schemaVersion = 1;

  final String scope;
  final MapDataCacheStore _store;
  final DateTime Function() _now;
  final int maximumEntryBytes;
  Future<void> _pendingWrite = Future<void>.value();

  String _key() {
    final String scopeHash = sha256.convert(utf8.encode(scope)).toString();
    return 'map-data-$scopeHash';
  }

  Future<MapDataCacheEntry?> load() async {
    try {
      final String? raw = await _store.read(_key());
      if (raw == null || utf8.encode(raw).length > maximumEntryBytes) {
        return null;
      }
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != schemaVersion ||
          decoded['scope'] != scope ||
          decoded['recordings'] is! List ||
          decoded['filteredParts'] is! List ||
          decoded['savedAt'] is! String) {
        return null;
      }
      final DateTime? savedAt = DateTime.tryParse(decoded['savedAt'] as String);
      if (savedAt == null) return null;
      return MapDataCacheEntry(
        savedAt: savedAt,
        recordingsPayload:
            List<dynamic>.from(decoded['recordings'] as List<dynamic>),
        filteredPartsPayload:
            List<dynamic>.from(decoded['filteredParts'] as List<dynamic>),
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> save(
    List<dynamic> recordingsPayload,
    List<dynamic> filteredPartsPayload,
  ) async {
    try {
      final List<dynamic> safeRecordings =
          sanitizeMapRecordingsPayload(recordingsPayload);
      final List<dynamic> safeFilteredParts =
          sanitizeMapFilteredPartsPayload(filteredPartsPayload);
      final String encoded = jsonEncode(<String, Object?>{
        'version': schemaVersion,
        'scope': scope,
        'savedAt': _now().toUtc().toIso8601String(),
        'recordings': safeRecordings,
        'filteredParts': safeFilteredParts,
      });
      if (utf8.encode(encoded).length > maximumEntryBytes) {
        return false;
      }
      final Future<void> write = _pendingWrite.then(
        (_) => _store.write(_key(), encoded),
      );
      _pendingWrite = write.catchError((_) {});
      await write;
      return true;
    } catch (_) {
      return false;
    }
  }
}

List<dynamic> sanitizeMapRecordingsPayload(List<dynamic> payload) {
  return payload.whereType<Map<String, dynamic>>().map((recording) {
    final List<dynamic> parts =
        (recording['parts'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(
              (part) => _pickFields(part, const <String>[
                'id',
                'length',
                'recordingId',
                'startDate',
                'endDate',
                'gpsLatitudeStart',
                'gpsLatitudeEnd',
                'gpsLongitudeStart',
                'gpsLongitudeEnd',
                'square',
              ]),
            )
            .toList(growable: false);
    return <String, Object?>{
      ..._pickFields(recording, const <String>[
        'id',
        'userId',
        'createdAt',
        'estimatedBirdsCount',
        'device',
        'byApp',
        'note',
        'name',
        'expectedPartsCount',
        'totalSeconds',
      ]),
      'parts': parts,
    };
  }).toList(growable: false);
}

List<dynamic> sanitizeMapFilteredPartsPayload(List<dynamic> payload) {
  return payload.whereType<Map<String, dynamic>>().map((filteredPart) {
    final List<dynamic> dialects =
        (filteredPart['detectedDialects'] as List<dynamic>? ??
                const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(
              (dialect) => _pickFields(dialect, const <String>[
                'id',
                'userGuessDialectId',
                'userGuessDialect',
                'confirmedDialectId',
                'confirmedDialect',
                'predictedDialectId',
                'predictedDialect',
              ]),
            )
            .toList(growable: false);
    return <String, Object?>{
      ..._pickFields(filteredPart, const <String>[
        'id',
        'recordingId',
        'startDate',
        'endDate',
        'state',
        'representantFlag',
        'parentId',
      ]),
      'detectedDialects': dialects,
    };
  }).toList(growable: false);
}

Map<String, Object?> _pickFields(
  Map<String, dynamic> source,
  List<String> fields,
) {
  return <String, Object?>{
    for (final String field in fields)
      if (source.containsKey(field)) field: source[field],
  };
}
