import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File('lib/map/RecordingPage.dart').readAsStringSync();
  });

  test('recording detail uses the same admin-first source policy as the map',
      () {
    final int methodStart =
        source.indexOf('Future<List<_DialectDisplayEntry>>');
    final int methodEnd = source.indexOf(
      '({String? code, _DialectConfidence confidence})',
      methodStart,
    );
    final String method = source.substring(methodStart, methodEnd);

    expect(method, contains('selectDialectSourceParts<Map<String, dynamic>>('));
    expect(method, contains('hasSubstantiveConfirmedDialect:'));
    expect(method, contains('hasAuthoritativeNoDialect:'));
    expect(method, contains('for (final map in sourceParts)'));
    expect(method, isNot(contains('for (final item in decoded)')));
  });

  test('recording detail filters sentinels before applying source priority',
      () {
    final int methodStart = source.indexOf(
      '({String? code, _DialectConfidence confidence})',
    );
    final int methodEnd = source.indexOf(
      'bool _parseBool',
      methodStart,
    );
    final String selectionMethods = source.substring(methodStart, methodEnd);

    expect(selectionMethods, contains('summarizeRecordingDialects('));
    expect(selectionMethods, contains('DialectSummaryMode.all'));
    expect(
      selectionMethods,
      contains('if (summary.hasAuthoritativeNoDialect)'),
    );
    expect(
      selectionMethods,
      contains('!isSemanticDialectSentinel(canonical)'),
    );
  });
}
