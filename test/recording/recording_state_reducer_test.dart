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
import 'package:record/record.dart';
import 'package:strnadi/recording/recording_state_reducer.dart';

void main() {
  test('late physical STOP cannot overwrite the logical paused workflow', () {
    expect(
      reduceRecorderState(
        currentState: RecordState.pause,
        physicalState: RecordState.stop,
        logicalPauseOwnsState: true,
      ),
      RecordState.pause,
    );
  });

  test('repeated late STOP remains paused until resume owns state', () {
    var state = RecordState.pause;
    for (int index = 0; index < 3; index += 1) {
      state = reduceRecorderState(
        currentState: state,
        physicalState: RecordState.stop,
        logicalPauseOwnsState: true,
      );
    }
    expect(state, RecordState.pause);
  });

  test('physical record and pause events still advance the workflow', () {
    expect(
      reduceRecorderState(
        currentState: RecordState.pause,
        physicalState: RecordState.record,
        logicalPauseOwnsState: true,
      ),
      RecordState.record,
    );
    expect(
      reduceRecorderState(
        currentState: RecordState.record,
        physicalState: RecordState.pause,
        logicalPauseOwnsState: false,
      ),
      RecordState.pause,
    );
  });

  test('STOP is accepted when no logical pause is active', () {
    expect(
      reduceRecorderState(
        currentState: RecordState.record,
        physicalState: RecordState.stop,
        logicalPauseOwnsState: false,
      ),
      RecordState.stop,
    );
  });
}
