import 'package:flutter_test/flutter_test.dart';
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
  });
}
