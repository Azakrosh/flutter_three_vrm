import 'dart:math' as math;

import 'package:example/main.dart';
import 'package:example/sample_poses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('survives lifecycle, model, and runtime recreation cycles', (
    tester,
  ) async {
    await tester.pumpWidget(const VrmExampleApp());
    await tester.pump();

    final view = tester.widget<VrmView>(find.byType(VrmView));
    final controller = view.controller;
    await controller.waitUntilReady(timeout: const Duration(seconds: 30));

    final initialHealth = await controller.getRuntimeHealth();
    expect(initialHealth.protocolVersion, 1);
    expect(initialHealth.threeRevision, '180');
    expect(initialHealth.threeVrmVersion, '3.5.5');
    expect(initialHealth.maxTextureSize, greaterThan(0));

    await _waitForModel(tester, controller);
    final report = await controller.getModelReport();
    expect(report.meshes, greaterThan(0));
    expect(report.triangles, greaterThan(0));
    expect(report.humanoidBones, greaterThan(0));

    await _waitForAnimation(tester, controller);
    await _verifyMotionTransitions(tester, controller);

    await controller.setBackground(
      color: const Color(0xFF171823),
      imageAssetPath: 'assets/images/backgrounds/background.svg',
    );
    await controller.setBackground(color: const Color(0xFF171823));

    await controller.setGraphicsPreset(VrmGraphicsPreset.performance);
    expect((await controller.getRuntimeHealth()).contextLost, isFalse);
    await controller.setGraphicsPreset(VrmGraphicsPreset.balanced);
    expect((await controller.getRuntimeHealth()).contextLost, isFalse);

    await controller.setCameraMode(VrmCameraMode.free);
    await controller.setCameraMode(VrmCameraMode.constrained);
    await controller.resetCamera(duration: Duration.zero);
    expect((await controller.getTransform()).zoom, greaterThan(0));

    for (var index = 0; index < 300; index += 1) {
      controller.setLipSyncAmplitude((index % 100) / 100);
      controller.setLookAtTarget(Offset(index / 300, 1.4));
    }
    await controller.cancelSpeech();

    await controller.beginSpeech(startDelay: Duration.zero);
    await controller.appendSpeechVisemes(<VisemeFrame>[
      const VisemeFrame(
        viseme: VrmViseme.aa,
        timestamp: Duration.zero,
        duration: Duration(milliseconds: 30),
      ),
      const VisemeFrame(
        viseme: VrmViseme.sil,
        timestamp: Duration(milliseconds: 30),
        duration: Duration.zero,
      ),
    ]);
    await controller.finishSpeech(const Duration(milliseconds: 30));

    const expectedTransform = VrmTransform(x: 0.2, y: -0.1, zoom: 1.4);
    await controller.setTransform(expectedTransform);

    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await _waitForRenderingState(tester, controller, paused: !isWindows);

    if (!isWindows) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await _waitForRenderingState(tester, controller, paused: true);
    }

    await controller.reloadRuntime();
    await controller.waitUntilReady(timeout: const Duration(seconds: 30));
    await _waitForModel(tester, controller);
    await _waitForRenderingState(tester, controller, paused: !isWindows);

    final restoredHealth = await controller.getRuntimeHealth();
    expect(restoredHealth.modelLoaded, isTrue);
    expect(restoredHealth.contextLost, isFalse);

    final restoredTransform = await controller.getTransform();
    expect(restoredTransform.x, closeTo(expectedTransform.x, 0.001));
    expect(restoredTransform.y, closeTo(expectedTransform.y, 0.001));
    expect(restoredTransform.zoom, closeTo(expectedTransform.zoom, 0.001));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _waitForRenderingState(tester, controller, paused: false);

    await controller.unloadModel();
    expect(controller.isModelLoaded, isFalse);
    expect((await controller.getRuntimeHealth()).modelLoaded, isFalse);

    await controller.loadModel('assets/vrm/', 'sample.vrm');
    await _waitForModel(tester, controller);
    expect((await controller.getRuntimeHealth()).contextLost, isFalse);

    await controller.setTransform(expectedTransform);
    for (var cycle = 0; cycle < 2; cycle += 1) {
      await controller.reloadRuntime();
      await controller.waitUntilReady(timeout: const Duration(seconds: 30));
      await _waitForModel(tester, controller);

      final cycleHealth = await controller.getRuntimeHealth();
      expect(cycleHealth.modelLoaded, isTrue);
      expect(cycleHealth.renderingPaused, isFalse);
      expect(cycleHealth.contextLost, isFalse);

      final cycleTransform = await controller.getTransform();
      expect(cycleTransform.x, closeTo(expectedTransform.x, 0.001));
      expect(cycleTransform.y, closeTo(expectedTransform.y, 0.001));
      expect(cycleTransform.zoom, closeTo(expectedTransform.zoom, 0.001));
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _verifyMotionTransitions(
  WidgetTester tester,
  VrmController controller,
) async {
  final presenterRotation =
      presenterOpenPose[VrmHumanBone.leftUpperArm]!.rotation!;
  final loungeRotation = loungePose[VrmHumanBone.leftUpperArm]!.rotation!;

  // The example starts with a VRMA clip, so this covers VRMA -> Pose.
  await controller.setPose(presenterOpenPose, fadeDuration: 0.4);
  await _waitForBoneRotation(
    tester,
    controller,
    VrmHumanBone.leftUpperArm,
    presenterRotation,
  );

  // A long fade makes the intermediate Pose -> Pose state observable on both
  // WebView implementations instead of merely checking the final transform.
  await controller.setPose(loungePose, fadeDuration: 1.0);
  await _waitForIntermediateBoneRotation(
    tester,
    controller,
    VrmHumanBone.leftUpperArm,
    from: presenterRotation,
    to: loungeRotation,
  );
  await _waitForBoneRotation(
    tester,
    controller,
    VrmHumanBone.leftUpperArm,
    loungeRotation,
  );

  // Exercise Pose -> VRMA and then another VRMA -> Pose transition.
  await controller.playAnimation(
    'assets/vrma/',
    'sample.vrma',
    fadeDuration: 0.4,
  );
  await _waitForAnimation(tester, controller);
  await Future<void>.delayed(const Duration(milliseconds: 450));
  await controller.setPose(presenterOpenPose, fadeDuration: 0.4);
  await _waitForBoneRotation(
    tester,
    controller,
    VrmHumanBone.leftUpperArm,
    presenterRotation,
  );

  // Reset is also a mixer fade, not an immediate humanoid reset.
  await controller.resetPose(fadeDuration: 0.4);
  expect((await controller.getRuntimeHealth()).animationActive, isTrue);
  await _waitForBoneRotation(
    tester,
    controller,
    VrmHumanBone.leftUpperArm,
    const VrmQuaternion.identity(),
  );
}

Future<void> _waitForAnimation(
  WidgetTester tester,
  VrmController controller,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    if ((await controller.getRuntimeHealth()).animationActive) return;
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('Expected an active animation before the timeout.');
}

Future<void> _waitForIntermediateBoneRotation(
  WidgetTester tester,
  VrmController controller,
  VrmHumanBone bone, {
  required VrmQuaternion from,
  required VrmQuaternion to,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  VrmQuaternion? lastRotation;
  while (DateTime.now().isBefore(deadline)) {
    lastRotation = (await controller.getPose())[bone]?.rotation;
    if (lastRotation != null &&
        _quaternionAngle(lastRotation, from) > 0.015 &&
        _quaternionAngle(lastRotation, to) > 0.015) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 40));
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
  fail('Expected an intermediate rotation for $bone, got $lastRotation.');
}

Future<void> _waitForBoneRotation(
  WidgetTester tester,
  VrmController controller,
  VrmHumanBone bone,
  VrmQuaternion expected,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  VrmQuaternion? lastRotation;
  while (DateTime.now().isBefore(deadline)) {
    lastRotation = (await controller.getPose())[bone]?.rotation;
    if (lastRotation != null &&
        _quaternionAngle(lastRotation, expected) < 0.02) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('Expected $bone rotation $expected, got $lastRotation.');
}

double _quaternionAngle(VrmQuaternion first, VrmQuaternion second) {
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

Future<void> _waitForModel(
  WidgetTester tester,
  VrmController controller,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (!controller.isModelLoaded && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(controller.isModelLoaded, isTrue);
}

Future<void> _waitForRenderingState(
  WidgetTester tester,
  VrmController controller, {
  required bool paused,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  VrmRuntimeHealth? lastHealth;
  while (DateTime.now().isBefore(deadline)) {
    lastHealth = await controller.getRuntimeHealth();
    if (lastHealth.renderingPaused == paused) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail(
    'Expected renderingPaused=$paused, '
    'last value was ${lastHealth?.renderingPaused}.',
  );
}
