import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/PostRecordingForm/recording_form_rendering.dart';
import 'package:strnadi/database/Models/recordingPart.dart';

void main() {
  group('firstRecordingPartOrNull', () {
    test('returns null when part conversion produced no renderable rows', () {
      expect(firstRecordingPartOrNull(const <RecordingPart>[]), isNull);
    });

    test('returns the first converted part', () {
      final RecordingPart first = _part(id: 1);
      final RecordingPart second = _part(id: 2);

      expect(
        firstRecordingPartOrNull(<RecordingPart>[first, second]),
        same(first),
      );
    });
  });
}

RecordingPart _part({required int id}) {
  final DateTime start = DateTime.utc(2026, 7, 18, 10);
  return RecordingPart(
    id: id,
    recordingId: 42,
    startTime: start,
    endTime: start.add(const Duration(seconds: 5)),
    gpsLatitudeStart: 50.0755,
    gpsLatitudeEnd: 50.0756,
    gpsLongitudeStart: 14.4378,
    gpsLongitudeEnd: 14.4379,
    path: 'logical://part-$id.wav',
  );
}
