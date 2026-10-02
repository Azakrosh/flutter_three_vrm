import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';
import 'package:flutter_three_vrm/src/runtime/vrm_cleanup.dart';

void main() {
  test('dispose shares one terminal future', () async {
    final controller = VrmController();

    final first = controller.dispose();
    final second = controller.dispose();

    expect(identical(first, second), isTrue);
    await first;
  });

  test(
    'cleanup runner executes every phase and preserves first error',
    () async {
      final firstError = StateError('thermal cleanup failed');
      final secondError = StateError('subscription cleanup failed');
      final phases = <String>[];

      final cleanup = runVrmCleanupPhases([
        () async {
          phases.add('thermal');
          throw firstError;
        },
        () async {
          phases.add('subscription');
          throw secondError;
        },
        () async => phases.add('bridge'),
      ]);

      await expectLater(cleanup, throwsA(same(firstError)));
      expect(phases, <String>['thermal', 'subscription', 'bridge']);
    },
  );
  test('every public controller mutation rejects work after dispose', () async {
    final controller = VrmController();
    await controller.dispose();

    final operations = <String, FutureOr<Object?> Function()>{
      'loadModel': () => controller.loadModel('assets/', 'avatar.vrm'),
      'loadModelFromFile': () =>
          controller.loadModelFromFile(File('avatar.vrm')),
      'loadModelFromBytes': () =>
          controller.loadModelFromBytes(Uint8List(0), fileName: 'avatar.vrm'),
      'loadModelFromUrl': () =>
          controller.loadModelFromUrl('https://example.com/avatar.vrm'),
      'cancelModelLoad': controller.cancelModelLoad,
      'reloadRuntime': controller.reloadRuntime,
      'unloadModel': controller.unloadModel,
      'playAnimation': () => controller.playAnimation('assets/', 'idle.vrma'),
      'playAnimationFromFile': () =>
          controller.playAnimationFromFile(File('idle.vrma')),
      'playAnimationFromBytes': () => controller.playAnimationFromBytes(
        Uint8List(0),
        fileName: 'idle.vrma',
      ),
      'playAnimationFromFileBundle': () =>
          controller.playAnimationFromFileBundle({
            'idle.gltf': File('idle.gltf'),
          }, entryFileName: 'idle.gltf'),
      'playAnimationFromBytesBundle': () =>
          controller.playAnimationFromBytesBundle({
            'idle.gltf': Uint8List(0),
          }, entryFileName: 'idle.gltf'),
      'playAnimationFromUrl': () =>
          controller.playAnimationFromUrl('https://example.com/idle.vrma'),
      'pauseAnimation': controller.pauseAnimation,
      'resumeAnimation': controller.resumeAnimation,
      'cancelAnimationLoad': controller.cancelAnimationLoad,
      'stopAnimation': controller.stopAnimation,
      'setAnimationSpeed': () => controller.setAnimationSpeed(1),
      'setPose': () => controller.setPose(VrmPose()),
      'resetPose': controller.resetPose,
      'setMood': () => controller.setMood(VrmMood.happy),
      'clearMood': controller.clearMood,
      'setExpression': () => controller.setExpression(VrmExpression.happy),
      'clearExpressionLayer': () =>
          controller.clearExpressionLayer(ExpressionLayer.eyes),
      'clearAllExpressions': controller.clearAllExpressions,
      'setCustomBlendShape': () => controller.setCustomBlendShape('custom', 1),
      'setLipSyncAmplitude': () => controller.setLipSyncAmplitude(0.5),
      'setViseme': () => controller.setViseme(VrmViseme.aa),
      'enqueueSpeechVisemes': () => controller.enqueueSpeechVisemes(const [
        VisemeFrame(viseme: VrmViseme.aa, timestamp: Duration.zero),
      ]),
      'enqueueSpeechAmplitudes': () => controller.enqueueSpeechAmplitudes(
        const [AmplitudeFrame(amplitude: 0.5, timestamp: Duration.zero)],
      ),
      'beginSpeech': controller.beginSpeech,
      'cancelSpeech': controller.cancelSpeech,
      'setAutoSaccades': controller.setAutoSaccades,
      'setAutoBlink': () => controller.setAutoBlink(true),
      'setLookAtTarget': () => controller.setLookAtTarget(const Offset(0, 0)),
      'setLookAtConfig': controller.setLookAtConfig,
      'setCameraMode': () =>
          controller.setCameraMode(VrmCameraMode.constrained),
      'setTransform': () =>
          controller.setTransform(const VrmTransform(x: 0, y: 0, zoom: 1)),
      'resetCamera': controller.resetCamera,
      'setLighting': controller.setLighting,
      'setEnvironmentColor': () => controller.setEnvironmentColor(Colors.black),
      'setShadows': () => controller.setShadows(true),
      'setPhysics': controller.setPhysics,
      'setWind': controller.setWind,
      'stopWind': controller.stopWind,
      'setBackground': () => controller.setBackground(color: Colors.black),
      'setBackgroundFromFile': () => controller.setBackgroundFromFile(
        File('background.png'),
        color: Colors.black,
      ),
      'setBackgroundFromBytes': () => controller.setBackgroundFromBytes(
        Uint8List(0),
        fileName: 'background.png',
        color: Colors.black,
      ),
      'setRenderQuality': () => controller.setRenderQuality(1),
      'setGraphicsPreset': () =>
          controller.setGraphicsPreset(VrmGraphicsPreset.balanced),
      'setAdaptiveQuality': () =>
          controller.setAdaptiveQuality(const VrmAdaptiveQualitySettings()),
      'setGraphicsSettings': controller.setGraphicsSettings,
    };

    for (final MapEntry(key: name, value: operation) in operations.entries) {
      await _expectDisposed(name, operation);
    }

    await controller.dispose();
  });
}

Future<void> _expectDisposed(
  String name,
  FutureOr<Object?> Function() operation,
) async {
  Object? error;
  try {
    final result = operation();
    if (result is Future<Object?>) {
      await result;
    }
  } on Object catch (caught) {
    error = caught;
  }
  expect(error, isA<StateError>(), reason: name);
}
