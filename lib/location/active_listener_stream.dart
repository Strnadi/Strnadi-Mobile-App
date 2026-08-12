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

import 'dart:async';

/// Shares one source subscription while consumers are actively listening.
///
/// The source is cancelled when the last consumer detaches, so a singleton
/// owner does not accidentally keep a process-lifetime sensor subscription.
class ActiveListenerStream<T> {
  final Stream<T> Function() _sourceFactory;
  final void Function(T value) _onValue;
  late final StreamController<T> _controller;

  StreamSubscription<T>? _sourceSubscription;
  int _sourceGeneration = 0;

  ActiveListenerStream({
    required Stream<T> Function() sourceFactory,
    required void Function(T value) onValue,
  })  : _sourceFactory = sourceFactory,
        _onValue = onValue {
    _controller = StreamController<T>.broadcast(
      onListen: _startSource,
      onCancel: _stopSource,
    );
  }

  Stream<T> get stream => _controller.stream;

  void _startSource() {
    if (_sourceSubscription != null) return;
    final int generation = ++_sourceGeneration;
    _sourceSubscription = _sourceFactory().listen(
      (T value) {
        if (generation != _sourceGeneration) return;
        _onValue(value);
        _controller.add(value);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (generation != _sourceGeneration) return;
        _controller.addError(error, stackTrace);
      },
      onDone: () {
        if (generation == _sourceGeneration) {
          _sourceSubscription = null;
        }
      },
    );
  }

  void _stopSource() {
    final StreamSubscription<T>? subscription = _sourceSubscription;
    _sourceSubscription = null;
    _sourceGeneration += 1;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }
}
