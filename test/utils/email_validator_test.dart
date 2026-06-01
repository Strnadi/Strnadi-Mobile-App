import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/auth/email_input_formatter.dart';
import 'package:strnadi/auth/email_validator.dart';

void main() {
  group('EmailValidator', () {
    test('accepts emails with hyphens in local and domain parts', () {
      expect(
        EmailValidator.isValid('jane-doe@bird-song-data.example'),
        isTrue,
      );
    });

    test('rejects domains starting with hyphen', () {
      expect(
        EmailValidator.isValid('jane.doe@-example.com'),
        isFalse,
      );
    });

    test('normalizes emails by trimming and lowercasing', () {
      expect(
        EmailValidator.normalize('  Jane-Doe@Bird-Song-Data.EXAMPLE  '),
        'jane-doe@bird-song-data.example',
      );
    });
  });

  group('LowerCaseEmailInputFormatter', () {
    test('lowercases typed email text', () {
      const formatter = LowerCaseEmailInputFormatter();

      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: 'Jane-Doe@Bird-Song-Data.EXAMPLE'),
      );

      expect(result.text, 'jane-doe@bird-song-data.example');
    });
  });
}
