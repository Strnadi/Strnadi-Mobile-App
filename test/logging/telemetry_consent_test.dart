import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/logging/telemetry_consent.dart';

void main() {
  test('Android requires a persisted grant and never queries ATT', () async {
    String? stored;
    var attReads = 0;
    final consent = TelemetryConsent(
      isIos: false,
      readStoredStatus: () async => stored,
      readTrackingStatus: () async {
        attReads++;
        return TrackingStatus.authorized;
      },
    );
    for (final value in [null, '', 'denied', 'invalid', 'notDetermined']) {
      stored = value;
      expect(await consent.isAuthorized(), isFalse);
    }
    stored = 'authorized';
    expect(await consent.isAuthorized(), isTrue);
    expect(attReads, 0);
  });

  test(
    'iOS rereads current ATT status and fails closed after revocation',
    () async {
      var status = TrackingStatus.authorized;
      final consent = TelemetryConsent(
        isIos: true,
        readStoredStatus: () async => 'authorized',
        readTrackingStatus: () async => status,
      );
      expect(await consent.isAuthorized(), isTrue);
      for (final value in TrackingStatus.values) {
        status = value;
        expect(
          await consent.isAuthorized(),
          value == TrackingStatus.authorized,
        );
      }
    },
  );

  test('locked storage and missing ATT plugin disable telemetry', () async {
    final storageFailure = TelemetryConsent(
      isIos: false,
      readStoredStatus: () async => throw StateError('storage unavailable'),
    );
    final attFailure = TelemetryConsent(
      isIos: true,
      readStoredStatus: () async => 'authorized',
      readTrackingStatus: () async => throw StateError('plugin unavailable'),
    );
    expect(await storageFailure.isAuthorized(), isFalse);
    expect(await attFailure.isAuthorized(), isFalse);
  });
}
