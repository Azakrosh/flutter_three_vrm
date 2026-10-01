import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/src/runtime/vrm_view_lifecycle_coordinator.dart';

void main() {
  group('VrmViewLifecycleCoordinator', () {
    test('waits for initialization and runs one cleanup', () async {
      final initializationBarrier = Completer<void>();
      var cleanupCount = 0;
      final coordinator = VrmViewLifecycleCoordinator(
        initialize: () => initializationBarrier.future,
      );

      final first = coordinator.dispose(cleanup: () async => cleanupCount += 1);
      final second = coordinator.dispose(
        cleanup: () async => cleanupCount += 100,
      );
      var completed = false;
      unawaited(first.then<void>((_) => completed = true));
      await Future<void>.delayed(Duration.zero);

      expect(identical(first, second), isTrue);
      expect(cleanupCount, 0);
      expect(completed, isFalse);

      initializationBarrier.complete();
      await first;
      expect(cleanupCount, 1);
      expect(completed, isTrue);
    });

    test('waits for active work before cleanup', () async {
      final initializationBarrier = Completer<void>();
      final activeWorkBarrier = Completer<void>();
      final phases = <String>[];
      final coordinator = VrmViewLifecycleCoordinator(
        initialize: () async {
          phases.add('initialize');
          await initializationBarrier.future;
        },
      );

      final disposal = coordinator.dispose(
        settleBeforeCleanup: () async {
          phases.add('settle');
          await activeWorkBarrier.future;
        },
        cleanup: () async => phases.add('cleanup'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(phases, <String>['initialize']);

      initializationBarrier.complete();
      await Future<void>.delayed(Duration.zero);
      expect(phases, <String>['initialize', 'settle']);

      activeWorkBarrier.complete();
      await disposal;
      expect(phases, <String>['initialize', 'settle', 'cleanup']);
    });

    test('runs cleanup when initialization fails', () async {
      final initializationBarrier = Completer<void>();
      final failure = StateError('initialization failed');
      var cleanupCount = 0;
      final coordinator = VrmViewLifecycleCoordinator(
        initialize: () => initializationBarrier.future,
      );

      final disposal = coordinator.dispose(
        cleanup: () async => cleanupCount += 1,
      );
      initializationBarrier.completeError(failure);

      await expectLater(disposal, throwsA(same(failure)));
      expect(cleanupCount, 1);
    });

    test('runs cleanup and preserves an active work failure', () async {
      final failure = StateError('active work failed');
      var cleanupCount = 0;
      final coordinator = VrmViewLifecycleCoordinator(initialize: () async {});

      final disposal = coordinator.dispose(
        settleBeforeCleanup: () => Future<void>.error(failure),
        cleanup: () async => cleanupCount += 1,
      );

      await expectLater(disposal, throwsA(same(failure)));
      expect(cleanupCount, 1);
    });
  });
}
