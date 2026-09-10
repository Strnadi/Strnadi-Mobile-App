import 'package:flutter_test/flutter_test.dart';

import '../../scripts/check_recording_part_dates.dart';

void main() {
  test('identifies null, missing, wrong-type and malformed dates by part ID',
      () {
    expect(
        findInvalidPartDates([
          {
            'id': 42,
            'parts': [
              {'id': 1, 'startDate': null},
              {'id': 2, 'startDate': 123, 'endDate': 'bad'},
              {
                'id': 3,
                'startDate': '2026-09-04T10:00:00Z',
                'endDate': '2026-09-04T10:01:00Z',
              },
            ],
          },
          {'id': 43, 'parts': []},
          {'id': 44},
        ]),
        [
          {
            'recordingId': 42,
            'partId': 1,
            'invalidFields': {'startDate': 'null', 'endDate': 'missing'},
          },
          {
            'recordingId': 42,
            'partId': 2,
            'invalidFields': {
              'startDate': 'not a string',
              'endDate': 'invalid date string',
            },
          },
        ]);
  });

  test('rejects unexpected schemas instead of reporting a clean scan', () {
    for (final payload in [
      {},
      [null],
      [
        {'parts': {}}
      ],
      [
        {
          'parts': [null]
        }
      ],
    ]) {
      expect(() => findInvalidPartDates(payload), throwsFormatException);
    }
  });
}
