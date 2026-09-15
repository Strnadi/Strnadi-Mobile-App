import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/map/state/map_async_request_state.dart';

void main() {
  group('MapLoadingTracker', () {
    test('one overlapping operation cannot hide another active operation', () {
      final MapLoadingTracker tracker = MapLoadingTracker();

      final int recordingsToken = tracker.begin();
      final int dialectToken = tracker.begin();

      expect(tracker.isLoading, isTrue);
      expect(tracker.activeCount, 2);

      expect(tracker.finish(recordingsToken), isTrue);
      expect(tracker.isLoading, isTrue);
      expect(tracker.activeCount, 1);

      expect(tracker.finish(dialectToken), isTrue);
      expect(tracker.isLoading, isFalse);
      expect(tracker.activeCount, 0);
    });

    test('a replacement retires obsolete work without an idle transition', () {
      final MapLoadingTracker tracker = MapLoadingTracker();
      final int oldToken = tracker.begin();

      final int currentToken = tracker.replace(oldToken);

      expect(currentToken, isNot(oldToken));
      expect(tracker.isLoading, isTrue);
      expect(tracker.activeCount, 1);
      expect(tracker.finish(oldToken), isFalse);
      expect(tracker.isLoading, isTrue);
      expect(tracker.activeCount, 1);

      expect(tracker.finish(currentToken), isTrue);
      expect(tracker.isLoading, isFalse);
    });

    test('finishing an unknown or already finished token is harmless', () {
      final MapLoadingTracker tracker = MapLoadingTracker();
      final int token = tracker.begin();

      expect(tracker.finish(token), isTrue);
      expect(tracker.finish(token), isFalse);
      expect(tracker.finish(999), isFalse);
      expect(tracker.activeCount, 0);
    });
  });

  group('isMapDialectRequestCurrent', () {
    test(
      'accepts a request only when every captured generation is current',
      () {
        expect(
          isMapDialectRequestCurrent(
            dialectRequestId: 4,
            activeDialectRequestId: 4,
            recordingsRequestId: 7,
            activeRecordingsRequestId: 7,
            dataGeneration: 11,
            activeDataGeneration: 11,
          ),
          isTrue,
        );
      },
    );

    test('rejects an older dialect API response', () {
      expect(
        isMapDialectRequestCurrent(
          dialectRequestId: 3,
          activeDialectRequestId: 4,
          recordingsRequestId: 7,
          activeRecordingsRequestId: 7,
          dataGeneration: 11,
          activeDataGeneration: 11,
        ),
        isFalse,
      );
    });

    test('rejects a response belonging to an older recordings request', () {
      expect(
        isMapDialectRequestCurrent(
          dialectRequestId: 4,
          activeDialectRequestId: 4,
          recordingsRequestId: 6,
          activeRecordingsRequestId: 7,
          dataGeneration: 11,
          activeDataGeneration: 11,
        ),
        isFalse,
      );
    });

    test('rejects a response for stale recording or filter data', () {
      expect(
        isMapDialectRequestCurrent(
          dialectRequestId: 4,
          activeDialectRequestId: 4,
          recordingsRequestId: 7,
          activeRecordingsRequestId: 7,
          dataGeneration: 10,
          activeDataGeneration: 11,
        ),
        isFalse,
      );
    });

    test(
      'accepts a cache refresh captured from the current recordings data',
      () {
        expect(
          isMapDialectRequestCurrent(
            dialectRequestId: 4,
            activeDialectRequestId: 4,
            recordingsRequestId: 99,
            activeRecordingsRequestId: 99,
            dataGeneration: 11,
            activeDataGeneration: 11,
          ),
          isTrue,
        );
      },
    );
  });
}
