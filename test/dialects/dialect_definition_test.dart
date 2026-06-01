import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/dialects/dialect_definition.dart';

void main() {
  group('visibleDialectHintCodes', () {
    test('filters out zero-order dialects and preserves backend order', () {
      final codes = visibleDialectHintCodes(const [
        {'id': 19, 'dialectCode': 'None', 'color': '#FFFFFF', 'hintOrder': 0},
        {'id': 3, 'dialectCode': 'BC', 'color': '#F0F80F', 'hintOrder': 1},
        {'id': 4, 'dialectCode': 'BE', 'color': '#24581A', 'hintOrder': 2},
        {'id': 6, 'dialectCode': 'BhBl', 'color': '#61C1DA', 'hintOrder': 3},
      ]);

      expect(codes, <String>['BC', 'BE', 'BhBl']);
    });

    test('handles string hintOrder values', () {
      final codes = visibleDialectHintCodes(const [
        {'dialectCode': 'Unknown', 'hintOrder': '0'},
        {'dialectCode': 'XB', 'hintOrder': '5'},
        {'dialectCode': 'BBe', 'hintOrder': '6'},
      ]);

      expect(codes, <String>['XB', 'BBe']);
    });

    test('canonicalizes localized backend codes', () {
      final codes = visibleDialectHintCodes(const [
        {'dialectCode': 'Jiné', 'hintOrder': 7},
      ]);

      expect(codes, <String>['Other']);
    });
  });

  test('parseDialectDefinitions includes color and hintOrder metadata', () {
    final definitions = parseDialectDefinitions(const [
      {'id': 15, 'dialectCode': 'BBe', 'color': '#47D45A', 'hintOrder': 6},
    ]);

    expect(definitions, hasLength(1));
    expect(definitions.single.id, 15);
    expect(definitions.single.code, 'BBe');
    expect(definitions.single.color, '#47D45A');
    expect(definitions.single.hintOrder, 6);
  });
}
