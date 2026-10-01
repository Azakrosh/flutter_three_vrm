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

      final first = coordinator.dispose(() async => cleanupCount += 1);
      final second = coordinator.dispose(() async => cleanupCount += 100);
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

    test('runs cleanup when initialization fails', () async {
      final initializationBarrier = Completer<void>();
      final failure = StateError('initialization failed');
      var cleanupCount = 0;
      final coordinator = VrmViewLifecycleCoordinator(
        initialize: () => initializationBarrier.future,
      );

      final disposal = coordinator.dispose(() async => cleanupCount += 1);
      initializationBarrier.completeError(failure);

      await expectLater(disposal, throwsA(same(failure)));
      expect(cleanupCount, 1);
    });
  });
}
