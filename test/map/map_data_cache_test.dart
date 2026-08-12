import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/map/filtered_parts_api_loader.dart';
import 'package:strnadi/map/map_data_cache.dart';

class _MemoryMapDataCacheStore implements MapDataCacheStore {
  final Map<String, String> values = <String, String>{};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String contents) async {
    if (failWrites) throw const FileSystemExceptionForTest();
    values[key] = contents;
  }
}

class FileSystemExceptionForTest implements Exception {
  const FileSystemExceptionForTest();
}

void main() {
  group('MapDataCache', () {
    test('stores and restores a scoped map data snapshot', () async {
      final _MemoryMapDataCacheStore store = _MemoryMapDataCacheStore();
      final DateTime savedAt = DateTime.utc(2026, 8, 12, 9, 30);
      final MapDataCache cache = MapDataCache(
        scope: 'prod|api.strnadi.cz',
        store: store,
        now: () => savedAt,
      );
      final List<dynamic> payload = <dynamic>[
        <String, Object?>{'id': 8934, 'parts': <dynamic>[]},
      ];

      expect(
        await cache.save(payload, const <dynamic>[]),
        isTrue,
      );
      final MapDataCacheEntry? restored = await cache.load();

      expect(restored, isNotNull);
      expect(restored!.savedAt, savedAt);
      expect(restored.recordingsPayload, payload);
      expect(restored.filteredPartsPayload, isEmpty);
    });

    test('keeps production and development snapshots separate', () async {
      final _MemoryMapDataCacheStore store = _MemoryMapDataCacheStore();
      final MapDataCache production = MapDataCache(
        scope: 'prod|api.strnadi.cz',
        store: store,
      );
      final MapDataCache development = MapDataCache(
        scope: 'dev|dev-api.strnadi.cz',
        store: store,
      );

      await production.save(<dynamic>[
        <String, Object?>{'id': 1}
      ], const <dynamic>[]);

      expect(await development.load(), isNull);
    });

    test('ignores corrupt and oversized entries', () async {
      final _MemoryMapDataCacheStore corruptStore = _MemoryMapDataCacheStore();
      final MapDataCache corruptCache = MapDataCache(
        scope: 'prod|api.strnadi.cz',
        store: corruptStore,
      );
      await corruptCache.save(<dynamic>[
        <String, Object?>{'id': 1}
      ], const <dynamic>[]);
      corruptStore.values.updateAll((_, __) => '{not-json');

      expect(
        await corruptCache.load(),
        isNull,
      );

      final _MemoryMapDataCacheStore smallStore = _MemoryMapDataCacheStore();
      final MapDataCache smallCache = MapDataCache(
        scope: 'prod|api.strnadi.cz',
        store: smallStore,
        maximumEntryBytes: 80,
      );
      expect(
        await smallCache.save(
          <dynamic>[
            <String, Object?>{'value': 'x' * 100}
          ],
          const <dynamic>[],
        ),
        isFalse,
      );
      expect(smallStore.values, isEmpty);
    });

    test('does not report a failed write as cached', () async {
      final _MemoryMapDataCacheStore store = _MemoryMapDataCacheStore()
        ..failWrites = true;
      final MapDataCache cache = MapDataCache(
        scope: 'prod|api.strnadi.cz',
        store: store,
      );

      expect(
        await cache.save(const <dynamic>[], const <dynamic>[]),
        isFalse,
      );
    });

    test('serializes overlapping writes and keeps the newest snapshot',
        () async {
      final _MemoryMapDataCacheStore store = _MemoryMapDataCacheStore();
      final MapDataCache cache = MapDataCache(
        scope: 'prod|api.strnadi.cz',
        store: store,
      );

      final Future<bool> first = cache.save(
        <dynamic>[
          <String, Object?>{'id': 1}
        ],
        const <dynamic>[],
      );
      final Future<bool> second = cache.save(
        <dynamic>[
          <String, Object?>{'id': 2}
        ],
        const <dynamic>[],
      );

      expect(await Future.wait(<Future<bool>>[first, second]),
          everyElement(isTrue));
      final MapDataCacheEntry? restored = await cache.load();
      expect(restored!.recordingsPayload.single['id'], 2);
    });

    test('persists only fields required by the map', () async {
      final _MemoryMapDataCacheStore store = _MemoryMapDataCacheStore();
      final MapDataCache cache = MapDataCache(
        scope: 'prod|api.strnadi.cz',
        store: store,
      );

      await cache.save(
        <dynamic>[
          <String, Object?>{
            'id': 8934,
            'createdAt': '2026-08-12T09:00:00Z',
            'estimatedBirdsCount': 1,
            'byApp': true,
            'expectedPartsCount': 1,
            'totalSeconds': 5,
            'mail': 'must-not-be-cached@example.test',
            'parts': <dynamic>[
              <String, Object?>{
                'id': 1,
                'recordingId': 8934,
                'startDate': '2026-08-12T09:00:00Z',
                'endDate': '2026-08-12T09:00:05Z',
                'gpsLatitudeStart': 50.0,
                'gpsLatitudeEnd': 50.0,
                'gpsLongitudeStart': 14.0,
                'gpsLongitudeEnd': 14.0,
                'dataBase64': 'must-not-be-cached',
              },
            ],
          },
        ],
        <dynamic>[
          <String, Object?>{
            'id': 12,
            'recordingId': 8934,
            'startDate': '2026-08-12T09:00:00Z',
            'endDate': '2026-08-12T09:00:05Z',
            'state': 6,
            'representantFlag': true,
            'reviewerEmail': 'must-not-be-cached@example.test',
            'detectedDialects': <dynamic>[
              <String, Object?>{
                'id': 24,
                'predictedDialect': 'BC',
                'reviewerId': 99,
              },
            ],
          },
        ],
      );

      final MapDataCacheEntry restored = (await cache.load())!;
      final Map<String, dynamic> recording =
          restored.recordingsPayload.single as Map<String, dynamic>;
      final Map<String, dynamic> part =
          (recording['parts'] as List<dynamic>).single as Map<String, dynamic>;
      final Map<String, dynamic> filteredPart =
          restored.filteredPartsPayload.single as Map<String, dynamic>;
      final Map<String, dynamic> dialect =
          (filteredPart['detectedDialects'] as List<dynamic>).single
              as Map<String, dynamic>;

      expect(recording, isNot(contains('mail')));
      expect(part, isNot(contains('dataBase64')));
      expect(filteredPart, isNot(contains('reviewerEmail')));
      expect(dialect, isNot(contains('reviewerId')));
      expect(dialect['predictedDialect'], 'BC');
    });
  });

  group('FilteredPartsApiLoader.parsePayload', () {
    test('restores filtered parts and their dialects without API or DB', () {
      final List<dynamic> payload = jsonDecode('''
        [{
          "id": 12,
          "recordingId": 8934,
          "startDate": "2026-08-12T09:00:00Z",
          "endDate": "2026-08-12T09:00:05Z",
          "state": 6,
          "representantFlag": true,
          "detectedDialects": [{
            "id": 24,
            "predictedDialect": "BC"
          }]
        }]
      ''') as List<dynamic>;

      final FilteredPartsBundle bundle =
          FilteredPartsApiLoader.parsePayload(payload);

      expect(bundle.isAvailable, isTrue);
      expect(bundle.frps, hasLength(1));
      expect(bundle.frps.single.recordingBEID, 8934);
      expect(bundle.dds, hasLength(1));
      expect(bundle.dds.single.filteredPartBEID, 12);
      expect(bundle.dds.single.predictedDialect, 'BC');
      expect(bundle.sourcePayload, payload);
    });

    test('distinguishes an unavailable response from a valid empty one', () {
      final FilteredPartsBundle empty =
          FilteredPartsApiLoader.parsePayload(<dynamic>[]);

      expect(empty.isAvailable, isTrue);
      expect(empty.frps, isEmpty);
      expect(FilteredPartsBundle.unavailable.isAvailable, isFalse);
    });
  });
}
