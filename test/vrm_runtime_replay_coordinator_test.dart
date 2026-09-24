import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';
import 'package:flutter_three_vrm/src/recovery/vrm_runtime_replay_coordinator.dart';

void main() {
  group('VrmRuntimeReplayCoordinator', () {
    test('replays durable state in the declared order', () async {
      final coordinator = VrmRuntimeReplayCoordinator();
      final generation = coordinator.beginRuntime();
      final phases = <VrmRuntimeReplayPhase>[];

      final result = await coordinator.replay(
        generation: generation,
        steps: [
          for (final phase in VrmRuntimeReplayPhase.values)
            VrmRuntimeReplayStep(phase, () async => phases.add(phase)),
        ],
      );

      expect(result, VrmRuntimeReplayResult.completed);
      expect(phases, VrmRuntimeReplayPhase.values);
      coordinator.dispose();
    });

    test('superseded replay stops after its in-flight step', () async {
      final coordinator = VrmRuntimeReplayCoordinator();
      final generation = coordinator.beginRuntime();
      final firstStep = Completer<void>();
      var staleStepRan = false;

      final replay = coordinator.replay(
        generation: generation,
        steps: [
          VrmRuntimeReplayStep(
            VrmRuntimeReplayPhase.lifecycle,
            () => firstStep.future,
          ),
          VrmRuntimeReplayStep(
            VrmRuntimeReplayPhase.graphics,
            () async => staleStepRan = true,
          ),
        ],
      );
      coordinator.invalidateRuntime();
      firstStep.complete();

      expect(await replay, VrmRuntimeReplayResult.superseded);
      expect(staleStepRan, isFalse);
      coordinator.dispose();
    });

    test('step failure aborts replay and preserves the error', () async {
      final coordinator = VrmRuntimeReplayCoordinator();
      final generation = coordinator.beginRuntime();
      var laterStepRan = false;

      await expectLater(
        coordinator.replay(
          generation: generation,
          steps: [
            VrmRuntimeReplayStep(
              VrmRuntimeReplayPhase.graphics,
              () async => throw StateError('graphics failed'),
            ),
            VrmRuntimeReplayStep(
              VrmRuntimeReplayPhase.background,
              () async => laterStepRan = true,
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );
      expect(laterStepRan, isFalse);
      coordinator.dispose();
    });

    test('camera waits for model and is restored exactly once', () async {
      final coordinator = VrmRuntimeReplayCoordinator();
      const transform = VrmTransform(x: 0.25, y: -0.1, zoom: 1.4);
      coordinator.captureCamera(transform, 7);
      final generation = coordinator.beginRuntime();
      final restored = <VrmTransform>[];

      await coordinator.restoreCamera(
        generation: generation,
        modelLoaded: false,
        currentRevision: 7,
        apply: (value) async => restored.add(value),
      );
      await coordinator.restoreCamera(
        generation: generation,
        modelLoaded: true,
        currentRevision: 7,
        apply: (value) async => restored.add(value),
      );
      await coordinator.restoreCamera(
        generation: generation,
        modelLoaded: true,
        currentRevision: 7,
        apply: (value) async => restored.add(value),
      );

      expect(restored, <VrmTransform>[transform]);
      coordinator.dispose();
    });

    test('new user camera revision discards stale recovery snapshot', () async {
      final coordinator = VrmRuntimeReplayCoordinator();
      coordinator.captureCamera(const VrmTransform(x: 0, y: 0, zoom: 1), 2);
      final generation = coordinator.beginRuntime();
      var applyCount = 0;

      await coordinator.restoreCamera(
        generation: generation,
        modelLoaded: true,
        currentRevision: 3,
        apply: (_) async => applyCount += 1,
      );
      await coordinator.restoreCamera(
        generation: generation,
        modelLoaded: true,
        currentRevision: 2,
        apply: (_) async => applyCount += 1,
      );

      expect(applyCount, 0);
      coordinator.dispose();
    });

    test('dispose supersedes replay and rejects a new runtime', () async {
      final coordinator = VrmRuntimeReplayCoordinator();
      final generation = coordinator.beginRuntime();
      coordinator.dispose();

      expect(coordinator.isCurrent(generation), isFalse);
      expect(coordinator.beginRuntime, throwsStateError);
      expect(
        await coordinator.replay(generation: generation, steps: const []),
        VrmRuntimeReplayResult.superseded,
      );
    });
  });
}
