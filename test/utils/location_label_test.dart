import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/utils/location_label.dart';

void main() {
  group('buildLocationLabel', () {
    test('prefers municipality before detailed place name', () {
      final payload = <String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'Louka u lesa',
            'regionalStructure': <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'municipality',
                'name': 'Brno',
              },
            ],
          },
        ],
      };

      expect(buildLocationLabel(payload), 'Brno, Louka u lesa');
    });

    test('prefers municipality before street address for reverse geocoding',
        () {
      final payload = <String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'regional.address',
            'name': 'Dlouha 21',
            'regionalStructure': <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'regional.street',
                'name': 'Dlouha',
              },
              <String, dynamic>{
                'type': 'regional.municipality',
                'name': 'Praha',
              },
            ],
          },
        ],
      };

      expect(buildLocationLabel(payload), 'Praha, Dlouha 21');
    });

    test('prefers street from structure over poi name', () {
      final payload = <String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'poi',
            'name': 'Oblibene misto',
            'regionalStructure': <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'regional.street',
                'name': 'Masarykova',
              },
              <String, dynamic>{
                'type': 'regional.municipality',
                'name': 'Brno',
              },
            ],
          },
        ],
      };

      expect(buildLocationLabel(payload), 'Brno, Masarykova');
    });

    test('does not duplicate municipality when place name matches it', () {
      final payload = <String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'Brno',
            'regionalStructure': <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'municipality',
                'name': 'Brno',
              },
            ],
          },
        ],
      };

      expect(buildLocationLabel(payload), 'Brno');
    });
  });
}
