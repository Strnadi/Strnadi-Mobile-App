import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:strnadi/map/data/recording_parser.dart';

Map<String, Object?> partJson(int id) => {
  'id': id,
  'recordingId': 42,
  'length': 12,
  'gpsLatitudeStart': 49.2,
  'gpsLongitudeStart': 16.6,
  'gpsLatitudeEnd': 49.3,
  'gpsLongitudeEnd': 16.7,
};

void main() {
  for (final value in [null, '', '   ', 'not-a-date', 123]) {
    test(
      'unavailable date ($value) keeps the part without inventing a date',
      () {
        final part = Part.fromJson({
          ...partJson(1),
          'startDate': value,
          'endDate': value,
        });
        expect(part.start, isNull);
        expect(part.end, isNull);
        expect(part.id, 1);
        expect(part.recordingId, 42);
        expect(part.length, 12);
        expect(part.gpsLatitudeStart, 49.2);
        expect(part.gpsLongitudeStart, 16.6);
      },
    );
  }

  test('missing fields remain null and valid dates parse independently', () {
    final missing = Part.fromJson(partJson(1));
    expect(missing.start, isNull);
    expect(missing.end, isNull);
    final startOnly = Part.fromJson({
      ...partJson(2),
      'startDate': '2026-09-04T10:00:00+02:00',
      'endDate': '',
    });
    expect(startOnly.start, DateTime.utc(2026, 9, 4, 8));
    expect(startOnly.end, isNull);
    final endOnly = Part.fromJson({
      ...partJson(3),
      'startDate': null,
      'endDate': '2026-09-04T08:01:00Z',
    });
    expect(endOnly.start, isNull);
    expect(endOnly.end, DateTime.utc(2026, 9, 4, 8, 1));
  });

  test('map helpers retain all parts and coordinates in a mixed payload', () {
    final payload = jsonEncode([
      {
        'id': 42,
        'createdAt': '2026-09-04T08:00:00Z',
        'parts': [
          {...partJson(1), 'startDate': null, 'endDate': null},
          {...partJson(2), 'startDate': '', 'endDate': ''},
          partJson(3),
          {
            ...partJson(4),
            'startDate': '2026-09-04T08:00:00Z',
            'endDate': '2026-09-04T08:01:00Z',
          },
        ],
      },
    ]);
    final parts = getParts(payload);
    expect(parts.map((part) => part.id), [1, 2, 3, 4]);
    expect(parts.last.start, DateTime.utc(2026, 9, 4, 8));
    expect(parts.last.end, DateTime.utc(2026, 9, 4, 8, 1));
    expect(getFirstPartLatLng(payload), const LatLng(49.2, 16.6));
    expect(getAllLatLngs(payload), List.filled(4, const LatLng(49.2, 16.6)));
  });
}
