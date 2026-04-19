import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/dialects/dialect_keyword_translator.dart';

void main() {
  test('maps backend None dialect to canonical No Dialect', () {
    expect(DialectKeywordTranslator.toEnglish('None'), 'No Dialect');
  });
}
