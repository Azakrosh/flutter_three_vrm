import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/src/bridge/latest_value_dispatcher.dart';

void main() {
  group('LatestValueDispatcher', () {
    test(
      'keeps one in-flight value and only the latest queued value',
      () async {
        final firstDispatch = Completer<void>();
        final values = <int>[];
        final errors = <Object>[];
        final dispatcher = LatestValueDispatcher<int>(
          dispatch: (value) async {
            values.add(value);
            if (value == 1) await firstDispatch.future;
          },
          onError: (error, _) => errors.add(error),
        );

        dispatcher.add(1);
        dispatcher.add(2);
        dispatcher.add(3);
        expect(values, <int>[1]);

        firstDispatch.complete();
        await dispatcher.idle;

        expect(values, <int>[1, 3]);
        expect(errors, isEmpty);
        dispatcher.close();
      },
    );

    test('clear drops queued work and suppresses stale errors', () async {
      final firstDispatch = Completer<void>();
      final values = <int>[];
      final errors = <Object>[];
      final dispatcher = LatestValueDispatcher<int>(
        dispatch: (value) async {
          values.add(value);
          await firstDispatch.future;
        },
        onError: (error, _) => errors.add(error),
      );

      dispatcher.add(1);
      dispatcher.add(2);
      dispatcher.clear();
      firstDispatch.completeError(StateError('stale runtime'));
      await dispatcher.idle;

      expect(values, <int>[1]);
      expect(errors, isEmpty);
      dispatcher.close();
    });

    test('reports active-generation errors and accepts later values', () async {
      final values = <int>[];
      final errors = <Object>[];
      final dispatcher = LatestValueDispatcher<int>(
        dispatch: (value) async {
          values.add(value);
          if (value == 1) throw StateError('dispatch failed');
        },
        onError: (error, _) => errors.add(error),
      );

      dispatcher.add(1);
      dispatcher.add(2);
      await dispatcher.idle;

      expect(values, <int>[1, 2]);
      expect(errors, hasLength(1));
      dispatcher.close();
    });
  });
}
