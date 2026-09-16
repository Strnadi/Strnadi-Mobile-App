import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application diagnostics use the shared logging boundary', () {
    // Supplemental architecture check; behavior is covered by logging tests.
    final violations = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') ||
          file.path.startsWith('lib/logging/')) {
        continue;
      }
      final source = file.readAsStringSync();
      if (source.contains('package:logger/') ||
          source.contains('Sentry.captureException(') ||
          source.contains('Sentry.captureEvent(') ||
          RegExp(r'\b(?:print|debugPrint)\s*\(').hasMatch(source)) {
        violations.add(file.path);
      }
    }
    expect(violations, isEmpty);
  });
}
