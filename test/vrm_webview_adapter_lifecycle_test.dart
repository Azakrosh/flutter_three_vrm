import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/src/platform/vrm_webview_adapter_lifecycle.dart';

void main() {
  group('VrmWebViewAdapterLifecycle', () {
    test('shares initialization and terminal dispose futures', () async {
      final initialization = Completer<void>();
      final lifecycle = VrmWebViewAdapterLifecycle();
      var initializationCount = 0;
      var cleanupCount = 0;

      final firstInitialization = lifecycle.initialize(() {
        initializationCount += 1;
        return initialization.future;
      });
      final secondInitialization = lifecycle.initialize(() async {
        initializationCount += 1;
      });
      expect(identical(firstInitialization, secondInitialization), isTrue);

      final firstDispose = lifecycle.dispose([
        () async {
          cleanupCount += 1;
        },
      ]);
      final secondDispose = lifecycle.dispose([
        () async {
          cleanupCount += 1;
        },
      ]);
      expect(identical(firstDispose, secondDispose), isTrue);
      expect(await _isCompleted(firstDispose), isFalse);

      initialization.complete();
      await firstDispose;
      expect(initializationCount, 1);
      expect(cleanupCount, 1);
    });

    test('waits for active operations and rejects later work', () async {
      final operation = Completer<void>();
      final lifecycle = VrmWebViewAdapterLifecycle();
      await lifecycle.initialize(() async {});

      final activeOperation = lifecycle.runOperation(() => operation.future);
      final disposal = lifecycle.dispose(<Future<void> Function()>[]);
      expect(await _isCompleted(disposal), isFalse);
      expect(
        () => lifecycle.runOperation(() async {}),
        throwsA(isA<StateError>()),
      );
      expect(lifecycle.ensureActive, throwsA(isA<StateError>()));

      operation.complete();
      await Future.wait<void>([activeOperation, disposal]);
    });

    test('runs every cleanup phase and preserves the first error', () async {
      final lifecycle = VrmWebViewAdapterLifecycle();
      final initializationError = StateError('initialize failed');
      final cleanupError = StateError('cleanup failed');
      var finalCleanupRan = false;
      final initialization = lifecycle.initialize(
        () => Future<void>.error(initializationError),
      );
      unawaited(initialization.catchError((_) {}));

      final disposal = lifecycle.dispose([
        () => Future<void>.error(cleanupError),
        () async {
          finalCleanupRan = true;
        },
      ]);

      await expectLater(disposal, throwsA(same(initializationError)));
      expect(finalCleanupRan, isTrue);
    });
  });
}

Future<bool> _isCompleted(Future<void> future) async {
  var completed = false;
  unawaited(future.then<void>((_) => completed = true, onError: (_) {}));
  await Future<void>.delayed(Duration.zero);
  return completed;
}
