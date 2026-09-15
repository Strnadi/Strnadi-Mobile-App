import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:strnadi/map/search/coordinate_parser.dart';

void main() {
  test('coordinates retain decimal and directional search formats', () {
    for (final prompt in [
      '49.2, 16.6',
      '49,2;16,6',
      'N49.2 E16.6',
      'E16.6 N49.2',
    ]) {
      expect(parseCoordinatesFromPrompt(prompt), const LatLng(49.2, 16.6));
    }
    expect(
      parseCoordinatesFromPrompt('S49.2 W16.6'),
      const LatLng(-49.2, -16.6),
    );
    expect(
      parseCoordinatesFromPrompt('-49.2 -16.6'),
      const LatLng(-49.2, -16.6),
    );
    // The existing search also recognizes an unambiguous longitude-first pair.
    expect(parseCoordinatesFromPrompt('91, 16'), const LatLng(16, 91));
  });

  test(
    'invalid coordinates and place names stay out of coordinate results',
    () {
      for (final prompt in [
        '',
        'Brno',
        '91, 181',
        '49, 181',
        'N49S E16',
        'NaN, 16',
      ]) {
        expect(parseCoordinatesFromPrompt(prompt), isNull, reason: prompt);
      }
    },
  );
}
