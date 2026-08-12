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

import 'package:record/record.dart';

/// Reconciles native recorder events with the app's logical workflow.
///
/// Stopping a physical stream is how this app implements a logical pause.
/// Some platforms publish their STOP event after the pause workflow has
/// already advanced. While [logicalPauseOwnsState] is true, that late event
/// must not hide the resume/finish controls.
RecordState reduceRecorderState({
  required RecordState currentState,
  required RecordState physicalState,
  required bool logicalPauseOwnsState,
}) {
  if (logicalPauseOwnsState && physicalState == RecordState.stop) {
    return RecordState.pause;
  }
  return physicalState;
}
