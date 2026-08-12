/*
 * Copyright (C) 2026 Marian Pecqueur && Jan Drobílek
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/navigation/recorder_exit_policy.dart';

void main() {
  group('permitsRecorderExit', () {
    test('allows navigation when a screen has no recorder policy', () async {
      expect(await permitsRecorderExit(null), isTrue);
    });

    test('returns the policy decision and invokes it exactly once', () async {
      var invocations = 0;

      final allowed = await permitsRecorderExit(() async {
        invocations++;
        return true;
      });

      expect(allowed, isTrue);
      expect(invocations, 1);
    });

    test('blocks navigation when recorder cleanup is cancelled', () async {
      var invocations = 0;

      final allowed = await permitsRecorderExit(() async {
        invocations++;
        return false;
      });

      expect(allowed, isFalse);
      expect(invocations, 1);
    });

    test('does not turn a failed cleanup into an allowed exit', () async {
      final failure = StateError('cleanup failed');

      await expectLater(
        permitsRecorderExit(() => Future<bool>.error(failure)),
        throwsA(same(failure)),
      );
    });
  });
}
