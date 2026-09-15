import 'dart:async';
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:strnadi/logging/app_logger.dart';
import 'package:strnadi/logging/markdown_download_failure.dart';

class _Sink implements AppLogSink {
  final List<AppLogRecord> records = [];

  @override
  void add(AppLogRecord record) => records.add(record);
}

void main() {
  final candidate = Uri.parse('https://files.test/attachment.wav?sig=SECRET');
  final originalStack = StackTrace.fromString('original download failure');
  late _Sink sink;
  late AppLogger logger;

  setUp(() {
    sink = _Sink();
    logger = AppLogger(consoleSink: sink, telemetrySink: sink);
  });

  for (final status in [404, 500]) {
    test(
      'public attachment HTTP $status retains status and reporting policy',
      () {
        final error = HttpExceptionWithStatus(
          status,
          'Rejected',
          uri: candidate,
        );
        logMarkdownDownloadFailure(
          logger: logger,
          candidate: candidate,
          error: error,
          stackTrace: originalStack,
        );
        expect(sink.records, hasLength(2));
        final record = sink.records.first;
        expect(record.context['statusCode'], status);
        expect(record.failure!.expected, status < 500);
        expect(record.stackTrace.toString(), originalStack.toString());
        expect(record.context['endpoint'], 'https://files.test/attachment.wav');
        expect(sink.records.last, same(record));
      },
    );
  }

  test(
    'cache filesystem failure is unexpected and has no fabricated status',
    () {
      const error = FileSystemException('No space left on device');
      logMarkdownDownloadFailure(
        logger: logger,
        candidate: candidate,
        error: error,
        stackTrace: originalStack,
      );
      final record = sink.records.first;
      expect(record.failure!.expected, isFalse);
      expect(
        record.reason,
        'Unable to store or read the cached Markdown attachment',
      );
      expect(record.context, isNot(contains('statusCode')));
      expect(record.stackTrace.toString(), originalStack.toString());
    },
  );

  test(
    'offline, timeout and cancellation remain expected without an HTTP status',
    () {
      for (final error in [
        const SocketException('Offline'),
        TimeoutException('Timed out'),
        http.RequestAbortedException(candidate),
      ]) {
        logMarkdownDownloadFailure(
          logger: logger,
          candidate: candidate,
          error: error,
          stackTrace: originalStack,
        );
        expect(sink.records.last.failure!.expected, isTrue);
        expect(sink.records.last.context, isNot(contains('statusCode')));
      }
    },
  );
}
