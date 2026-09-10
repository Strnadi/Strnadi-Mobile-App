import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/api/models/administration_profile.dart';

void main() {
  const owner = '01a08608-44b7-7aba-8d0c-542148b30bf2';
  Map<String, dynamic> profile(List<String> roles) => {
        'id': owner,
        'firstName': 'Jan',
        'lastName': 'Novak',
        'userName': null,
        'email': 'person@example.test',
        'roles': roles,
      };
  test('empty or unrelated roles do not enable privileged controls', () {
    for (final roles in [
      <String>[],
      ['another-project-role']
    ]) {
      final normalized =
          normalizeAdministrationProfile(profile(roles), expectedUserId: owner);
      expect(normalized['role'], isNull);
      expect(normalized['nickname'], isNull);
    }
  });
  test('explicit admin role has precedence for the existing single-role UI',
      () {
    expect(
        normalizeAdministrationProfile(profile(['tester', 'admin']),
            expectedUserId: owner)['role'],
        'admin');
  });
  test('invalid identities and malformed role lists fail closed', () {
    expect(
        () => normalizeAdministrationProfile(profile([]), expectedUserId: 42),
        throwsFormatException);
    expect(
        () => normalizeAdministrationProfile({
              ...profile([]),
              'roles': [42]
            }, expectedUserId: owner),
        throwsFormatException);
  });
}
