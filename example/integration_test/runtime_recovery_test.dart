import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';
import 'package:integration_test/integration_test.dart';

import 'support/vrm_integration_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('restores model, camera, and lifecycle state after reload', (
    tester,
  ) async {
    final harness = await VrmIntegrationHarness.start(tester);
    final controller = harness.controller;
    await harness.waitForModel();

    const expectedTransform = VrmTransform(x: 0.2, y: -0.1, zoom: 1.4);
    await controller.setTransform(expectedTransform);

    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await harness.waitForRenderingState(paused: !isWindows);
    if (!isWindows) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await harness.waitForRenderingState(paused: true);
    }

    await controller.reloadRuntime();
    await controller.waitUntilReady(timeout: const Duration(seconds: 30));
    await harness.waitForModel();
    await harness.waitForRenderingState(paused: !isWindows);

    final restoredHealth = await controller.getRuntimeHealth();
    expect(restoredHealth.modelLoaded, isTrue);
    expect(restoredHealth.contextLost, isFalse);
    _expectTransform(await controller.getTransform(), expectedTransform);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await harness.waitForRenderingState(paused: false);

    await controller.unloadModel();
    expect(controller.isModelLoaded, isFalse);
    expect((await controller.getRuntimeHealth()).modelLoaded, isFalse);

    await controller.loadModel('assets/vrm/', 'sample.vrm');
    await harness.waitForModel();
    expect((await controller.getRuntimeHealth()).contextLost, isFalse);

    await controller.setTransform(expectedTransform);
    for (var cycle = 0; cycle < 2; cycle += 1) {
      await controller.reloadRuntime();
      await controller.waitUntilReady(timeout: const Duration(seconds: 30));
      await harness.waitForModel();

      final cycleHealth = await controller.getRuntimeHealth();
      expect(cycleHealth.modelLoaded, isTrue);
      expect(cycleHealth.renderingPaused, isFalse);
      expect(cycleHealth.contextLost, isFalse);
      _expectTransform(await controller.getTransform(), expectedTransform);
    }

    await harness.disposeView();
  }, timeout: const Timeout(Duration(minutes: 3)));
}

void _expectTransform(VrmTransform actual, VrmTransform expected) {
  expect(actual.x, closeTo(expected.x, 0.001));
  expect(actual.y, closeTo(expected.y, 0.001));
  expect(actual.zoom, closeTo(expected.zoom, 0.001));
}
