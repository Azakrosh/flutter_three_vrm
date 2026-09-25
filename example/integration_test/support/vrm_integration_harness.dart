import 'dart:math' as math;

import 'package:example/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';

final class VrmIntegrationHarness {
  VrmIntegrationHarness._(this.tester, this.controller);

  final WidgetTester tester;
  final VrmController controller;

  static Future<VrmIntegrationHarness> start(WidgetTester tester) async {
    await tester.pumpWidget(const VrmExampleApp());
    await tester.pump();

    final view = tester.widget<VrmView>(find.byType(VrmView));
    final harness = VrmIntegrationHarness._(tester, view.controller);
    await harness.controller.waitUntilReady(
      timeout: const Duration(seconds: 30),
    );
    return harness;
  }

  Future<void> waitForModel() async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (!controller.isModelLoaded && DateTime.now().isBefore(deadline)) {
      if (tester.binding.lifecycleState != AppLifecycleState.hidden) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(controller.isModelLoaded, isTrue);
  }

  Future<void> waitForAnimation() async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      if ((await controller.getRuntimeHealth()).animationActive) return;
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('Expected an active animation before the timeout.');
  }

  Future<void> waitForRenderingState({required bool paused}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    VrmRuntimeHealth? lastHealth;
    while (DateTime.now().isBefore(deadline)) {
      lastHealth = await controller.getRuntimeHealth();
      if (lastHealth.renderingPaused == paused) return;
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    fail(
      'Expected renderingPaused=$paused, '
      'last value was ${lastHealth?.renderingPaused}.',
    );
  }

  Future<void> disposeView() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  }
}

double quaternionAngle(VrmQuaternion first, VrmQuaternion second) {
  final dot =
      (first.x * second.x +
              first.y * second.y +
              first.z * second.z +
              first.w * second.w)
          .abs()
          .clamp(0.0, 1.0)
          .toDouble();
  return 2 * math.acos(dot);
}
