import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';
import 'package:integration_test/integration_test.dart';

import 'support/vrm_integration_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('validates runtime, model, scene, and pointer contracts', (
    tester,
  ) async {
    final harness = await VrmIntegrationHarness.start(tester);
    final controller = harness.controller;
    debugPrint('runtime_smoke: runtime ready');

    final initialHealth = await controller.getRuntimeHealth();
    expect(initialHealth.protocolVersion, 3);
    expect(initialHealth.threeRevision, '180');
    expect(initialHealth.threeVrmVersion, '3.5.5');
    expect(initialHealth.maxTextureSize, greaterThan(0));
    expect(initialHealth.contextLossCount, 0);
    expect(initialHealth.lastModelLoadDurationMs, greaterThanOrEqualTo(0));

    await harness.waitForModel();
    final report = await controller.getModelReport();
    final loadedHealth = await controller.getRuntimeHealth();
    expect(report.meshes, greaterThan(0));
    expect(report.triangles, greaterThan(0));
    expect(report.humanoidBones, greaterThan(0));
    expect(loadedHealth.lastModelLoadDurationMs, greaterThan(0));
    expect(
      loadedHealth.estimatedTextureMemoryBytes,
      report.estimatedTextureMemoryBytes,
    );
    expect(loadedHealth.rendererTextureCount, greaterThanOrEqualTo(0));
    debugPrint('runtime_smoke: model diagnostics verified');

    final avatarRect = tester.getRect(find.byType(VrmView));
    final supportsSyntheticWebViewTap =
        defaultTargetPlatform == TargetPlatform.windows;
    if (supportsSyntheticWebViewTap) {
      await controller.resetPose(fadeDuration: 0);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final beforeTap = await controller.getPose();
      final tapEvent = controller.onTap.first;
      await tester.tapAt(
        Offset(
          avatarRect.left + avatarRect.width * 0.2,
          avatarRect.top + avatarRect.height * 0.3,
        ),
      );
      await tester.pump();
      await tapEvent.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final afterTap = await controller.getPose();
      for (final bone in [VrmHumanBone.head, VrmHumanBone.chest]) {
        expect(
          quaternionAngle(
            beforeTap[bone]!.rotation!,
            afterTap[bone]!.rotation!,
          ),
          lessThan(0.01),
          reason: 'A tap must not rotate $bone',
        );
      }
      debugPrint('runtime_smoke: tap does not rotate avatar');
    } else {
      debugPrint('runtime_smoke: synthetic PlatformView tap skipped');
    }

    await controller.setBackground(
      color: const Color(0xFF171823),
      imageAssetPath: 'assets/images/backgrounds/background.svg',
    );
    await controller.setBackground(color: const Color(0xFF171823));

    await controller.setGraphicsPreset(VrmGraphicsPreset.performance);
    expect((await controller.getRuntimeHealth()).contextLost, isFalse);
    await controller.setGraphicsPreset(VrmGraphicsPreset.balanced);
    expect((await controller.getRuntimeHealth()).contextLost, isFalse);
    if (supportsSyntheticWebViewTap) {
      final tapAfterRendererRecreation = controller.onTap.first;
      await tester.tapAt(
        Offset(
          avatarRect.left + avatarRect.width * 0.2,
          avatarRect.top + avatarRect.height * 0.3,
        ),
      );
      await tester.pump();
      await tapAfterRendererRecreation.timeout(const Duration(seconds: 5));
    }

    await controller.setGraphicsSettings(enablePhysics: false);
    controller.setPhysics(stiffness: 1.1, gravity: 1.2, drag: 0.9);
    controller.setWind(
      type: VrmWindType.light,
      direction: VrmWindDirection.left,
    );
    await controller.setGraphicsSettings(enablePhysics: true);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect((await controller.getRuntimeHealth()).contextLost, isFalse);
    controller.stopWind();
    controller.setPhysics();

    await controller.setCameraMode(VrmCameraMode.free);
    await controller.setCameraMode(VrmCameraMode.constrained);
    await controller.resetCamera(duration: Duration.zero);
    expect((await controller.getTransform()).zoom, greaterThan(0));

    await harness.disposeView();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
