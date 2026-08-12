/*
 * Copyright (C) 2025 Marian Pecqueur && Jan Drobílek
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

import 'package:flutter/material.dart';

/// A recording note which wraps to the available width and grows vertically.
///
/// The parent detail page owns scrolling. Deliberately omitting a fixed height
/// and a horizontal [Row] keeps long prose and long unbroken tokens within
/// narrow screens.
class RecordingNoteCard extends StatelessWidget {
  const RecordingNoteCard({
    super.key,
    required this.note,
  });

  static const Key textKey = Key('recording-note-card-text');

  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        note,
        key: textKey,
        softWrap: true,
        overflow: TextOverflow.visible,
        textWidthBasis: TextWidthBasis.parent,
        style: const TextStyle(fontSize: 16),
      ),
    );
  }
}
