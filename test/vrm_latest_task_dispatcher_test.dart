import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/src/runtime/vrm_latest_task_dispatcher.dart';

void main() {
  group('VrmLatestTaskDispatcher', () {
    test('serializes work and retains only the newest queued value', () async {
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final thirdStarted = Completer<void>();
      final releaseThird = Completer<void>();
      final dispatched = <int>[];
      final dispatcher = VrmLatestTaskDispatcher<int>(
        dispatch: (value) async {
          dispatched.add(value);
          if (value == 1) {
            firstStarted.complete();
            await releaseFirst.future;
          } else if (value == 3) {
            thirdStarted.complete();
            await releaseThird.future;
          }
        },
      );

      final first = dispatcher.submit(1);
      await firstStarted.future;
      final second = dispatcher.submit(2);
      final third = dispatcher.submit(3);
      releaseFirst.complete();
      await thirdStarted.future;

      expect(dispatched, <int>[1, 3]);
      expect(await _isCompleted(second), isFalse);
      expect(await _isCompleted(third), isFalse);

      releaseThird.complete();
      await Future.wait<void>([first, second, third, dispatcher.idle]);
      expect(dispatched, <int>[1, 3]);
    });

    test('shares the newest dispatch error with superseded waiters', () async {
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final dispatcher = VrmLatestTaskDispatcher<int>(
        dispatch: (value) async {
          if (value == 1) {
            firstStarted.complete();
            await releaseFirst.future;
            return;
          }
          throw StateError('configuration $value failed');
        },
      );

      final first = dispatcher.submit(1);
      await firstStarted.future;
      final secondExpectation = expectLater(
        dispatcher.submit(2),
        throwsA(isA<StateError>()),
      );
      final thirdExpectation = expectLater(
        dispatcher.submit(3),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'configuration 3 failed',
          ),
        ),
      );
      releaseFirst.complete();

      await first;
      await secondExpectation;
      await thirdExpectation;
      await dispatcher.idle;
    });

    test(
      'close rejects queued and future work but lets active work finish',
      () async {
        final started = Completer<void>();
        final release = Completer<void>();
        final dispatcher = VrmLatestTaskDispatcher<int>(
          dispatch: (_) async {
            started.complete();
            await release.future;
          },
        );

        final active = dispatcher.submit(1);
        await started.future;
        final queuedExpectation = expectLater(
          dispatcher.submit(2),
          throwsA(isA<StateError>()),
        );
        dispatcher.close();

        await queuedExpectation;
        await expectLater(dispatcher.submit(3), throwsA(isA<StateError>()));
        expect(await _isCompleted(active), isFalse);

        release.complete();
        await active;
        await dispatcher.idle;
      },
    );
  });
}

Future<bool> _isCompleted(Future<void> future) async {
  var completed = false;
  unawaited(future.then<void>((_) => completed = true, onError: (_) {}));
  await Future<void>.delayed(Duration.zero);
  return completed;
}
