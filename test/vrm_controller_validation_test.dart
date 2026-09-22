import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';

void main() {
  group('VrmController production input validation', () {
    late VrmController controller;

    setUp(() => controller = VrmController());
    tearDown(() => controller.dispose());

    test('rejects invalid animation and pose transitions synchronously', () {
      expect(
        () =>
            controller.playAnimation('assets/', 'idle.vrma', speed: double.nan),
        throwsArgumentError,
      );
      expect(
        () => controller.playAnimationFromUrl(
          'https://example.com/talk.glb',
          fadeDuration: -0.1,
        ),
        throwsArgumentError,
      );
      expect(
        () => controller.playAnimation('assets/', 'idle.vrma', clipName: '  '),
        throwsArgumentError,
      );
      expect(() => controller.resumeAnimation(speed: 0), throwsArgumentError);
      expect(
        () => controller.setAnimationSpeed(double.infinity),
        throwsArgumentError,
      );
      expect(
        () => controller.stopAnimation(fadeDuration: -1),
        throwsArgumentError,
      );
      expect(
        () => controller.setPose(VrmPose(), fadeDuration: double.nan),
        throwsArgumentError,
      );
      expect(
        () => controller.resetPose(fadeDuration: -0.1),
        throwsArgumentError,
      );
    });

    test('rejects invalid facial control values synchronously', () {
      expect(
        () => controller.setExpression(VrmExpression.happy, weight: -0.1),
        throwsArgumentError,
      );
      expect(
        () => controller.setExpression(
          VrmExpression.happy,
          duration: const Duration(milliseconds: -1),
        ),
        throwsArgumentError,
      );
      expect(
        () => controller.setCustomBlendShape('  ', 0.5),
        throwsArgumentError,
      );
      expect(
        () => controller.setCustomBlendShape('customSmile', double.nan),
        throwsArgumentError,
      );
      expect(
        () => controller.setMood(
          VrmMood.custom(
            expression: VrmExpression.happy,
            expressionWeight: 1.1,
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => controller.setMood(
          VrmMood.custom(physics: const VrmMoodPhysics(drag: double.infinity)),
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid scene and renderer values synchronously', () {
      expect(
        () => controller.setLookAtConfig(
          holdDuration: const Duration(milliseconds: -1),
        ),
        throwsArgumentError,
      );
      expect(
        () => controller.setLighting(ambientIntensity: -0.1),
        throwsArgumentError,
      );
      expect(
        () => controller.setLighting(directionalIntensity: double.infinity),
        throwsArgumentError,
      );
      expect(
        () =>
            controller.setEnvironmentColor(Colors.white, intensity: double.nan),
        throwsArgumentError,
      );
      expect(() => controller.setPhysics(stiffness: -0.1), throwsArgumentError);
      expect(
        () => controller.setPhysics(gravity: double.nan),
        throwsArgumentError,
      );
      expect(
        () => controller.setGraphicsSettings(pixelRatio: 0),
        throwsArgumentError,
      );
      expect(
        () => controller.setGraphicsSettings(pixelRatio: double.infinity),
        throwsArgumentError,
      );
      expect(
        () => controller.setGraphicsSettings(fpsCap: -1),
        throwsArgumentError,
      );
      expect(
        () => controller.setGraphicsSettings(fpsCap: 121),
        throwsArgumentError,
      );
    });
  });
}
