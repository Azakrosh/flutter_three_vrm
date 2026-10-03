import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';
import 'package:flutter_three_vrm/src/runtime/vrm_runtime_session_coordinator.dart';

void main() {
  group('VrmRuntimeSessionCoordinator', () {
    test('owns ordered replay and runtime readiness', () async {
      final harness = _SessionHarness();
      final order = <String>[];

      await harness.coordinator.activateRuntime(
        VrmRuntimeSessionReplayPlan(
          applyGraphics: () async => order.add('graphics'),
          applyBackground: () async => order.add('background'),
          loadPackageModel: () async => order.add('model'),
          applyApplicationState: () async => order.add('application'),
        ),
      );

      expect(harness.lifecyclePauses, <bool>[false]);
      expect(order, <String>['graphics', 'background', 'model', 'application']);
      expect(harness.coordinator.isRuntimeReady, isTrue);
      expect(harness.changedCount, 1);
      await harness.coordinator.dispose();
    });

    test('runtime failure supersedes an in-flight replay', () async {
      final harness = _SessionHarness(
        recoveryPolicy: const VrmRuntimeRecoveryPolicy(enabled: false),
      );
      final graphicsStarted = Completer<void>();
      final releaseGraphics = Completer<void>();
      var applicationStateApplied = false;

      final activation = harness.coordinator.activateRuntime(
        VrmRuntimeSessionReplayPlan(
          applyGraphics: () {
            graphicsStarted.complete();
            return releaseGraphics.future;
          },
          applyBackground: () async {},
          applyApplicationState: () async {
            applicationStateApplied = true;
          },
        ),
      );
      await graphicsStarted.future;

      harness.coordinator.handleRuntimeResourceError('document failed');
      releaseGraphics.complete();
      await activation;

      expect(applicationStateApplied, isFalse);
      expect(harness.coordinator.isRuntimeReady, isFalse);
      expect(harness.coordinator.errorMessage, 'document failed');
      expect(harness.unavailableReasons, hasLength(1));
      await harness.coordinator.dispose();
    });

    test('recovery retries are bounded and serialized', () async {
      var reloadFailures = 1;
      final harness = _SessionHarness(
        recoveryPolicy: const VrmRuntimeRecoveryPolicy(
          maxAttempts: 2,
          baseDelay: Duration.zero,
          maxDelay: Duration.zero,
        ),
        reload: () async {
          if (reloadFailures > 0) {
            reloadFailures -= 1;
            throw StateError('reload failed');
          }
        },
      );

      harness.coordinator.handleRuntimeResourceError('main frame failed');
      await harness.coordinator.recoveryIdle;

      expect(harness.reloadCount, 2);
      expect(harness.coordinator.recoveryAttempts, 2);
      expect(harness.coordinator.recoveryInProgress, isFalse);
      expect(harness.coordinator.errorMessage, isNull);
      expect(harness.reportedErrors, hasLength(1));
      expect(harness.unavailableReasons, hasLength(3));
      await harness.coordinator.dispose();
    });

    test('successful activation cancels delayed recovery reload', () async {
      final harness = _SessionHarness(
        recoveryPolicy: const VrmRuntimeRecoveryPolicy(
          maxAttempts: 1,
          baseDelay: Duration(milliseconds: 20),
          maxDelay: Duration(milliseconds: 20),
        ),
      );

      harness.coordinator.handleRuntimeResourceError('transient failure');
      await harness.coordinator.activateRuntime(
        VrmRuntimeSessionReplayPlan(
          applyGraphics: () async {},
          applyBackground: () async {},
          applyApplicationState: () async {},
        ),
      );
      await harness.coordinator.recoveryIdle;

      expect(harness.reloadCount, 0);
      expect(harness.coordinator.isRuntimeReady, isTrue);
      await harness.coordinator.dispose();
    });

    test(
      'dispose cancels delayed recovery and shares one cleanup future',
      () async {
        final harness = _SessionHarness(
          recoveryPolicy: const VrmRuntimeRecoveryPolicy(
            maxAttempts: 1,
            baseDelay: Duration(minutes: 1),
            maxDelay: Duration(minutes: 1),
          ),
        );

        harness.coordinator.handleRuntimeResourceError('waiting to recover');
        await Future<void>.delayed(Duration.zero);
        expect(harness.coordinator.recoveryInProgress, isTrue);

        final first = harness.coordinator.dispose();
        final second = harness.coordinator.dispose();

        expect(identical(first, second), isTrue);
        await first.timeout(const Duration(milliseconds: 200));
        expect(harness.reloadCount, 0);
        expect(harness.coordinator.recoveryInProgress, isFalse);
        expect(harness.coordinator.isRuntimeReady, isFalse);
      },
    );

    test('dispose waits for an active render lifecycle dispatch', () async {
      final dispatchStarted = Completer<void>();
      final releaseDispatch = Completer<void>();
      final harness = _SessionHarness(
        renderDispatch: (_) async {
          dispatchStarted.complete();
          await releaseDispatch.future;
        },
      );

      final activation = harness.coordinator.activateRuntime(
        VrmRuntimeSessionReplayPlan(
          applyGraphics: () async {},
          applyBackground: () async {},
          applyApplicationState: () async {},
        ),
      );
      await dispatchStarted.future;

      final disposal = harness.coordinator.dispose();
      expect(await _isCompleted(disposal), isFalse);

      releaseDispatch.complete();
      await disposal;
      await activation;
      expect(harness.coordinator.isRuntimeReady, isFalse);
    });
    test('camera snapshot survives reload and restores exactly once', () async {
      const transform = VrmTransform(x: 0.2, y: -0.1, zoom: 1.3);
      final harness = _SessionHarness(
        cameraTransform: transform,
        cameraRevision: 4,
      );

      await harness.coordinator.reloadRuntime();
      expect(
        harness.unavailableReasons.single,
        isA<VrmRuntimeException>().having(
          (error) => error.code,
          'code',
          'canceled',
        ),
      );
      await harness.coordinator.activateRuntime(
        VrmRuntimeSessionReplayPlan(
          applyGraphics: () async {},
          applyBackground: () async {},
          applyApplicationState: () async {},
        ),
      );
      expect(harness.appliedCameraTransforms, isEmpty);

      harness.modelLoaded = true;
      await harness.coordinator.restoreCameraAfterModelLoad();
      await harness.coordinator.restoreCameraAfterModelLoad();

      expect(harness.appliedCameraTransforms, <VrmTransform>[transform]);
      await harness.coordinator.dispose();
    });
  });
}

final class _SessionHarness {
  _SessionHarness({
    this.recoveryPolicy = const VrmRuntimeRecoveryPolicy(),
    this.reload,
    this.cameraTransform,
    this.cameraRevision = 0,
    this.renderDispatch,
  }) {
    coordinator = VrmRuntimeSessionCoordinator(
      platform: TargetPlatform.windows,
      initialLifecycleState: AppLifecycleState.resumed,
      renderingEnabled: true,
      lifecyclePolicy: VrmRenderLifecyclePolicy.platformDefault,
      recoveryPolicy: recoveryPolicy,
      dispatchRenderingPaused: (paused) async {
        lifecyclePauses.add(paused);
        await renderDispatch?.call(paused);
      },
      reloadRuntimeDocument: () async {
        reloadCount += 1;
        await reload?.call();
      },
      markRuntimeUnavailable: unavailableReasons.add,
      reportAsyncError: (error, _) => reportedErrors.add(error),
      onChanged: () => changedCount += 1,
      readCameraTransform: () => cameraTransform,
      readCameraRevision: () => cameraRevision,
      isModelLoaded: () => modelLoaded,
      applyCameraTransform: (transform) async {
        appliedCameraTransforms.add(transform);
      },
    );
  }

  final VrmRuntimeRecoveryPolicy recoveryPolicy;
  final Future<void> Function()? reload;
  final VrmTransform? cameraTransform;
  final int cameraRevision;
  final Future<void> Function(bool paused)? renderDispatch;

  late final VrmRuntimeSessionCoordinator coordinator;
  final List<bool> lifecyclePauses = [];
  final List<Object> unavailableReasons = [];
  final List<Object> reportedErrors = [];
  final List<VrmTransform> appliedCameraTransforms = [];
  bool modelLoaded = false;
  int changedCount = 0;
  int reloadCount = 0;
}

Future<bool> _isCompleted(Future<void> future) async {
  var completed = false;
  unawaited(future.then<void>((_) => completed = true, onError: (_) {}));
  await Future<void>.delayed(Duration.zero);
  return completed;
}
