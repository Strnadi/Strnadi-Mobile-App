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

import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

final logger = Logger();

Future<String> getPath() async {
  final dir = await getApplicationDocumentsDirectory();
  final String path =
      dir.path + 'audio_${DateTime.now().millisecondsSinceEpoch}.wav';
  logger.i('Generated file path: $path');
  return path;
}
