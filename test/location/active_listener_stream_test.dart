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

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/location/active_listener_stream.dart';

void main() {
  test('shares and caches only while consumers are actively listening',
      () async {
    var sourceListenCount = 0;
    var sourceCancelCount = 0;
    final StreamController<int> source = StreamController<int>.broadcast(
      sync: true,
      onListen: () => sourceListenCount += 1,
      onCancel: () => sourceCancelCount += 1,
    );
    final List<int> cached = <int>[];
    final ActiveListenerStream<int> active = ActiveListenerStream<int>(
      sourceFactory: () => source.stream,
      onValue: cached.add,
    );

    final List<int> firstValues = <int>[];
    final List<int> secondValues = <int>[];
    final StreamSubscription<int> first = active.stream.listen(firstValues.add);
    final StreamSubscription<int> second =
        active.stream.listen(secondValues.add);

    expect(sourceListenCount, 1);
    source.add(1);
    await _flushEvents();
    expect(firstValues, <int>[1]);
    expect(secondValues, <int>[1]);
    expect(cached, <int>[1]);

    await first.cancel();
    expect(sourceCancelCount, 0);
    source.add(2);
    await _flushEvents();
    expect(firstValues, <int>[1]);
    expect(secondValues, <int>[1, 2]);
    expect(cached, <int>[1, 2]);

    await second.cancel();
    await _flushEvents();
    expect(sourceCancelCount, 1);

    source.add(3);
    expect(cached, <int>[1, 2]);
    await source.close();
  });

  test('reattaches after the last consumer leaves', () async {
    var sourceListenCount = 0;
    var sourceCancelCount = 0;
    final StreamController<int> source = StreamController<int>.broadcast(
      sync: true,
      onListen: () => sourceListenCount += 1,
      onCancel: () => sourceCancelCount += 1,
    );
    final ActiveListenerStream<int> active = ActiveListenerStream<int>(
      sourceFactory: () => source.stream,
      onValue: (_) {},
    );

    final StreamSubscription<int> first = active.stream.listen((_) {});
    await first.cancel();
    await _flushEvents();
    final StreamSubscription<int> second = active.stream.listen((_) {});

    expect(sourceListenCount, 2);
    expect(sourceCancelCount, 1);

    await second.cancel();
    await source.close();
  });

  test('forwards active-source errors without creating a permanent listener',
      () async {
    final StreamController<int> source = StreamController<int>.broadcast();
    final ActiveListenerStream<int> active = ActiveListenerStream<int>(
      sourceFactory: () => source.stream,
      onValue: (_) {},
    );
    final List<Object> errors = <Object>[];
    final StreamSubscription<int> listener = active.stream.listen(
      (_) {},
      onError: errors.add,
    );

    source.addError(StateError('location stream failed'));
    await _flushEvents();
    expect(errors.single, isA<StateError>());

    await listener.cancel();
    await source.close();
  });
}

Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
