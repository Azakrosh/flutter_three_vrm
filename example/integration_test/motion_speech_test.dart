import 'package:example/sample_poses.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';
import 'package:integration_test/integration_test.dart';

import 'support/vrm_integration_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('transitions motion and completes both speech modes', (
    tester,
  ) async {
    final harness = await VrmIntegrationHarness.start(tester);
    final controller = harness.controller;
    await harness.waitForModel();
    await harness.waitForAnimation();

    await _verifyMotionTransitions(harness);

    for (var index = 0; index < 300; index += 1) {
      controller.setLipSyncAmplitude((index % 100) / 100);
      controller.setLookAtTarget(Offset(index / 300, 1.4));
    }
    await controller.cancelSpeech();

    final visemeSpeechFinished = controller.onSpeechFinished.first;
    final staleSpeech = await controller.beginSpeech();
    final visemeSpeech = await controller.beginSpeech(
      startDelay: Duration.zero,
    );
    expect(staleSpeech.isActive, isFalse);
    expect(
      await staleSpeech.appendVisemes(<VisemeFrame>[
        const VisemeFrame(viseme: VrmViseme.oh, timestamp: Duration.zero),
      ]),
      isFalse,
    );
    expect(
      await visemeSpeech.appendVisemes(<VisemeFrame>[
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
      ]),
      isTrue,
    );
    expect(await visemeSpeech.finish(const Duration(milliseconds: 30)), isTrue);
    expect(
      (await visemeSpeechFinished.timeout(
        const Duration(seconds: 5),
      )).sessionId,
      visemeSpeech.id,
    );
    expect(controller.isSpeechActive, isFalse);

    final amplitudeSpeechFinished = controller.onSpeechFinished.first;
    final amplitudeSpeech = await controller.beginSpeech(
      mode: VrmSpeechMode.amplitude,
      startDelay: Duration.zero,
    );
    expect(
      await amplitudeSpeech.appendAmplitudes(<AmplitudeFrame>[
        const AmplitudeFrame(
          amplitude: 0.8,
          timestamp: Duration.zero,
          duration: Duration(milliseconds: 40),
        ),
        const AmplitudeFrame(
          amplitude: 0,
          timestamp: Duration(milliseconds: 40),
          duration: Duration.zero,
        ),
      ]),
      isTrue,
    );
    expect(
      await amplitudeSpeech.finish(const Duration(milliseconds: 40)),
      isTrue,
    );
    expect(
      (await amplitudeSpeechFinished.timeout(
        const Duration(seconds: 5),
      )).sessionId,
      amplitudeSpeech.id,
    );
    expect(controller.isSpeechActive, isFalse);

    await harness.disposeView();
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<void> _verifyMotionTransitions(VrmIntegrationHarness harness) async {
  final controller = harness.controller;
  final presenterRotation =
      presenterOpenPose[VrmHumanBone.leftUpperArm]!.rotation!;
  final loungeRotation = loungePose[VrmHumanBone.leftUpperArm]!.rotation!;

  await controller.setPose(presenterOpenPose, fadeDuration: 0.4);
  await _waitForBoneRotation(
    harness,
    VrmHumanBone.leftUpperArm,
    presenterRotation,
  );

  await controller.setPose(loungePose, fadeDuration: 1.0);
  await _waitForIntermediateBoneRotation(
    harness,
    VrmHumanBone.leftUpperArm,
    from: presenterRotation,
    to: loungeRotation,
  );
  await _waitForBoneRotation(
    harness,
    VrmHumanBone.leftUpperArm,
    loungeRotation,
  );

  final animationStarted = controller.onAnimationStarted.first;
  final loopingPlayback = await controller.playAnimation(
    'assets/vrma/',
    'sample.vrma',
    fadeDuration: 0.4,
  );
  expect(
    (await animationStarted.timeout(const Duration(seconds: 5))).playbackId,
    loopingPlayback.id,
  );
  await harness.waitForAnimation();
  await Future<void>.delayed(const Duration(milliseconds: 450));
  await controller.setPose(presenterOpenPose, fadeDuration: 0.4);
  await _waitForBoneRotation(
    harness,
    VrmHumanBone.leftUpperArm,
    presenterRotation,
  );

  await controller.resetPose(fadeDuration: 0.4);
  expect((await controller.getRuntimeHealth()).animationActive, isTrue);
  await _waitForBoneRotation(
    harness,
    VrmHumanBone.leftUpperArm,
    const VrmQuaternion.identity(),
  );

  final animationFinished = controller.onAnimationFinished.first;
  final finitePlayback = await controller.playAnimation(
    'assets/vrma/',
    'sample.vrma',
    loop: false,
    fadeDuration: 0,
  );
  expect(
    (await animationFinished.timeout(const Duration(seconds: 30))).playbackId,
    finitePlayback.id,
  );
}

Future<void> _waitForIntermediateBoneRotation(
  VrmIntegrationHarness harness,
  VrmHumanBone bone, {
  required VrmQuaternion from,
  required VrmQuaternion to,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  VrmQuaternion? lastRotation;
  while (DateTime.now().isBefore(deadline)) {
    lastRotation = (await harness.controller.getPose())[bone]?.rotation;
    if (lastRotation != null &&
        quaternionAngle(lastRotation, from) > 0.015 &&
        quaternionAngle(lastRotation, to) > 0.015) {
      return;
    }
    await harness.tester.pump(const Duration(milliseconds: 40));
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
  fail('Expected an intermediate rotation for $bone, got $lastRotation.');
}

Future<void> _waitForBoneRotation(
  VrmIntegrationHarness harness,
  VrmHumanBone bone,
  VrmQuaternion expected,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  VrmQuaternion? lastRotation;
  while (DateTime.now().isBefore(deadline)) {
    lastRotation = (await harness.controller.getPose())[bone]?.rotation;
    if (lastRotation != null &&
        quaternionAngle(lastRotation, expected) < 0.02) {
      return;
    }
    await harness.tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  final angle = lastRotation == null
      ? null
      : quaternionAngle(lastRotation, expected);
  fail(
    'Expected $bone rotation $expected, got $lastRotation '
    '(angular error: $angle radians).',
  );
}
