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
