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
import 'package:flutter/foundation.dart';

class ElapsedTimer {
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  final ValueChanged<Duration> onTick;

  ElapsedTimer({required this.onTick});

  void start() {
    _stopwatch.start();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      onTick(_stopwatch.elapsed);
    });
  }

  void pause() {
    _stopwatch.stop();
    _ticker?.cancel();
  }

  void resume() {
    _stopwatch.start();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      onTick(_stopwatch.elapsed);
    });
  }

  void reset() {
    _stopwatch.reset();
    _ticker?.cancel();
    onTick(_stopwatch.elapsed);
  }

  Duration get elapsed => _stopwatch.elapsed;

  void dispose() {
    _stopwatch.stop();
    _ticker?.cancel();
  }
}
