import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';
import 'package:flutter_three_vrm/src/lifecycle/vrm_render_lifecycle_coordinator.dart';

void main() {
  group('shouldPauseVrmRendering', () {
    test('uses platform-specific defaults for inactive applications', () {
      expect(
        _resolve(TargetPlatform.android, AppLifecycleState.inactive),
        isTrue,
      );
      expect(
        _resolve(TargetPlatform.windows, AppLifecycleState.inactive),
        isFalse,
      );
    });

    test('always pauses hidden, paused, and detached applications', () {
      for (final platform in <TargetPlatform>[
        TargetPlatform.android,
        TargetPlatform.windows,
      ]) {
        for (final state in <AppLifecycleState>[
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.detached,
        ]) {
          expect(_resolve(platform, state), isTrue);
        }
      }
    });

    test('explicit policies override inactive platform defaults', () {
      expect(
        _resolve(
          TargetPlatform.android,
          AppLifecycleState.inactive,
          policy: VrmRenderLifecyclePolicy.pauseWhenHidden,
        ),
        isFalse,
      );
      expect(
        _resolve(
          TargetPlatform.windows,
          AppLifecycleState.inactive,
          policy: VrmRenderLifecyclePolicy.pauseWhenUnfocused,
        ),
        isTrue,
      );
    });

    test('renderingEnabled false takes precedence over lifecycle', () {
      expect(
        _resolve(
          TargetPlatform.windows,
          AppLifecycleState.resumed,
          renderingEnabled: false,
        ),
        isTrue,
      );
    });
  });

  test(
    'coordinator serializes commands and retains only latest state',
    () async {
      final firstDispatch = Completer<void>();
      final values = <bool>[];
      final errors = <Object>[];
      final coordinator = VrmRenderLifecycleCoordinator(
        platform: TargetPlatform.windows,
        initialLifecycleState: AppLifecycleState.resumed,
        renderingEnabled: true,
        policy: VrmRenderLifecyclePolicy.platformDefault,
        dispatch: (paused) async {
          values.add(paused);
          if (values.length == 1) await firstDispatch.future;
        },
        onError: (error, _) => errors.add(error),
      );

      final attaching = coordinator.attachRuntime();
      coordinator.updateLifecycleState(AppLifecycleState.hidden);
      coordinator.updateLifecycleState(AppLifecycleState.resumed);
      expect(values, <bool>[false]);

      firstDispatch.complete();
      await attaching;

      expect(values, <bool>[false, false]);
      expect(errors, isEmpty);
      await coordinator.dispose();
    },
  );

  test(
    'runtime detach drops queued state and suppresses stale errors',
    () async {
      final dispatch = Completer<void>();
      final errors = <Object>[];
      final coordinator = VrmRenderLifecycleCoordinator(
        platform: TargetPlatform.android,
        initialLifecycleState: AppLifecycleState.resumed,
        renderingEnabled: true,
        policy: VrmRenderLifecyclePolicy.platformDefault,
        dispatch: (_) => dispatch.future,
        onError: (error, _) => errors.add(error),
      );

      final attaching = coordinator.attachRuntime();
      coordinator.updateLifecycleState(AppLifecycleState.paused);
      coordinator.detachRuntime();
      dispatch.completeError(StateError('stale runtime'));
      await attaching;

      expect(errors, isEmpty);
      await coordinator.dispose();
    },
  );

  test('dispose waits for active dispatch and shares one future', () async {
    final dispatchStarted = Completer<void>();
    final releaseDispatch = Completer<void>();
    final errors = <Object>[];
    final coordinator = VrmRenderLifecycleCoordinator(
      platform: TargetPlatform.windows,
      initialLifecycleState: AppLifecycleState.resumed,
      renderingEnabled: true,
      policy: VrmRenderLifecyclePolicy.platformDefault,
      dispatch: (_) async {
        dispatchStarted.complete();
        await releaseDispatch.future;
      },
      onError: (error, _) => errors.add(error),
    );

    final attaching = coordinator.attachRuntime();
    await dispatchStarted.future;
    final first = coordinator.dispose();
    final second = coordinator.dispose();

    expect(identical(first, second), isTrue);
    expect(await _isCompleted(first), isFalse);

    releaseDispatch.complete();
    await Future.wait<void>([attaching, first]);
    expect(errors, isEmpty);
  });
  test('configuration changes are declarative and deduplicated', () async {
    final values = <bool>[];
    final coordinator = VrmRenderLifecycleCoordinator(
      platform: TargetPlatform.windows,
      initialLifecycleState: AppLifecycleState.inactive,
      renderingEnabled: true,
      policy: VrmRenderLifecyclePolicy.platformDefault,
      dispatch: (paused) async => values.add(paused),
      onError: (error, _) => fail('Unexpected error: $error'),
    );

    await coordinator.attachRuntime();
    coordinator.updateConfiguration(
      renderingEnabled: false,
      policy: VrmRenderLifecyclePolicy.platformDefault,
    );
    await coordinator.idle;
    coordinator.updateConfiguration(
      renderingEnabled: true,
      policy: VrmRenderLifecyclePolicy.pauseWhenUnfocused,
    );
    await coordinator.idle;
    coordinator.updateConfiguration(
      renderingEnabled: true,
      policy: VrmRenderLifecyclePolicy.pauseWhenHidden,
    );
    await coordinator.idle;

    expect(values, <bool>[false, true, false]);
    await coordinator.dispose();
  });
}

Future<bool> _isCompleted(Future<void> future) async {
  var completed = false;
  unawaited(future.then<void>((_) => completed = true, onError: (_) {}));
  await Future<void>.delayed(Duration.zero);
  return completed;
}

bool _resolve(
  TargetPlatform platform,
  AppLifecycleState state, {
  VrmRenderLifecyclePolicy policy = VrmRenderLifecyclePolicy.platformDefault,
  bool renderingEnabled = true,
}) => shouldPauseVrmRendering(
  policy: policy,
  platform: platform,
  lifecycleState: state,
  renderingEnabled: renderingEnabled,
);
