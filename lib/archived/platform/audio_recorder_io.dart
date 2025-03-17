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
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

mixin AudioRecorderMixin {
  Future<String> recordStream(
      AudioRecorder recorder, RecordConfig config, String filepath) async {
    final file = File(filepath);
    final stream = await recorder.startStream(config);

    final completer = Completer<String>();

    stream.listen(
      (data) {
        file.writeAsBytes(data, mode: FileMode.append);
      },
      onDone: () {
        print('End of stream. File written to $filepath.');
        completer.complete(filepath);
      },
      onError: (error) {
        completer.completeError(error);
      },
    );

    return completer.future;
  }
}
