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

import 'package:strnadi/database/src/database_logger.dart';

typedef UploadProgress = void Function(int sent, int total);
typedef DownloadProgress = void Function(double progress);

/// Broadcasts per-part upload progress to the UI.
class UploadProgressBus {
  static int _listeners = 0;
  static int _emissionSeq = 0;
  // How long to keep 100% items before clearing (set to Duration.zero to disable clearing)
  static Duration _retainAfterDone = const Duration(seconds: 3);
  static StreamController<Map<int, double>>? _controller;

  static StreamController<Map<int, double>> _ensureController() {
    if (_controller == null || _controller!.isClosed) {
      _controller = StreamController<Map<int, double>>.broadcast(
        onListen: () {
          _listeners++;
          logger.i('[UploadProgressBus] onListen: listeners=' +
              _listeners.toString() +
              '; current keys=' +
              _progress.keys.toList().toString());
          // Immediately send the current snapshot to the new listener
          final copy =
              Map<int, double>.unmodifiable(Map<int, double>.from(_progress));
          _emissionSeq++;
          logger.i('[UploadProgressBus] onListen -> emit #' +
              _emissionSeq.toString() +
              ' (initial snapshot): size=' +
              copy.length.toString() +
              ', keys=' +
              copy.keys.toList().toString());
          // Defer to next microtask to avoid re-entrancy
          scheduleMicrotask(() => _controller!.add(copy));
        },
        onCancel: () {
          _listeners = (_listeners > 0) ? _listeners - 1 : 0;
          logger.i('[UploadProgressBus] onCancel: listeners=' +
              _listeners.toString());
        },
      );
      logger.i('[UploadProgressBus] controller (re)created');
    }
    return _controller!;
  }

  static final Map<int, double> _progress = <int, double>{};

  static void debugState([String label = '']) {
    logger.i('[UploadProgressBus] debugState ' +
        (label.isEmpty ? '' : '(' + label + ')') +
        ': listeners=' +
        _listeners.toString() +
        ', emissions=' +
        _emissionSeq.toString() +
        ', size=' +
        _progress.length.toString() +
        ', keys=' +
        _progress.keys.toList().toString() +
        ', map=' +
        _progress.toString());
  }

  static Stream<Map<int, double>> get stream =>
      _ensureController().stream.map((event) {
        logger.i('[UploadProgressBus] stream emit: size=' +
            event.length.toString() +
            ', keys=' +
            event.keys.toList().toString());
        return event;
      });

  static Map<int, double> get snapshot {
    logger.d('[UploadProgressBus] snapshot requested: size=' +
        _progress.length.toString() +
        ', keys=' +
        _progress.keys.toList().toString() +
        ', map=' +
        _progress.toString());
    return Map<int, double>.from(_progress);
  }

  /// Set how long to retain 100% progress before clearing. Pass null/zero to disable.
  static void setRetainAfterDone(Duration? d) {
    _retainAfterDone = d ?? Duration.zero;
    logger.i('[UploadProgressBus] setRetainAfterDone -> ' +
        _retainAfterDone.inMilliseconds.toString() +
        ' ms');
  }

  static void update(int partId, int sent, int total) {
    final double progress = (total <= 0) ? 0.0 : (sent / total).clamp(0.0, 1.0);
    final double safe = progress.isNaN ? 0.0 : progress;
    _progress[partId] = safe;
    logger.d(
        '[UploadProgressBus] update(partId=$partId, sent=$sent, total=$total) -> progress=$safe');
    _ensureController().add(Map<int, double>.from(_progress));
  }

  static void markDone(int partId) {
    _progress.remove(partId);
    logger
        .d('[UploadProgressBus] markDone($partId) -> size=${_progress.length}');
    _ensureController().add(Map<int, double>.from(_progress));
  }

  static void clear(int partId) {
    _progress.remove(partId);
    logger.d('[UploadProgressBus] clear($partId) -> size=${_progress.length}');
    _ensureController().add(Map<int, double>.from(_progress));
  }
}
