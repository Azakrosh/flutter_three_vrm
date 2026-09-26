import 'package:example/sample_poses.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';
import 'package:integration_test/integration_test.dart';

const _soakSeconds = int.fromEnvironment('VRM_SOAK_SECONDS', defaultValue: 20);
const _loadCycles = int.fromEnvironment(
  'VRM_SOAK_LOAD_CYCLES',
  defaultValue: 3,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('profiles Android rendering and keeps resources bounded', (
    tester,
  ) async {
    if (_soakSeconds < 5) {
      fail('VRM_SOAK_SECONDS must be at least 5.');
    }
    if (_loadCycles < 2) {
      fail('VRM_SOAK_LOAD_CYCLES must be at least 2.');
    }

    final controller = VrmController();
    final errors = <String>[];
    final loadPhaseSamples = <VrmPerformanceSnapshot>[];
    final steadyStateSamples = <VrmPerformanceSnapshot>[];
    final healthSamples = <VrmRuntimeHealth>[];
    var performancePhase = _PerformancePhase.load;
    final errorSubscription = controller.onError.listen(
      (event) => errors.add(event.message),
    );
    final performanceSubscription = controller.onPerformance.listen(
      (event) => switch (performancePhase) {
        _PerformancePhase.load => loadPhaseSamples.add(event.snapshot),
        _PerformancePhase.steady => steadyStateSamples.add(event.snapshot),
      },
    );
    addTearDown(() async {
      await errorSubscription.cancel();
      await performanceSubscription.cancel();
      await controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VrmView(
            controller: controller,
            graphicsPreset: VrmGraphicsPreset.performance,
            adaptiveQuality: const VrmAdaptiveQualitySettings(
              targetFps: 30,
              minPixelRatio: 0.75,
              maxPixelRatio: 1,
            ),
          ),
        ),
      ),
    );
    await controller.waitUntilReady(timeout: const Duration(seconds: 30));

    final loadedTextureCounts = <int>[];
    final unloadedTextureCounts = <int>[];
    final loadDurationsMs = <double>[];
    int? expectedTextureMemoryBytes;
    for (var cycle = 0; cycle < _loadCycles; cycle += 1) {
      await controller.loadModel('assets/vrm/', 'sample.vrm');
      await _settleRenderer(tester);

      final report = await controller.getModelReport();
      final health = await controller.getRuntimeHealth();
      expectedTextureMemoryBytes ??= report.estimatedTextureMemoryBytes;
      expect(
        report.estimatedTextureMemoryBytes,
        expectedTextureMemoryBytes,
        reason: 'The same model must produce a stable texture estimate.',
      );
      expect(health.modelLoaded, isTrue);
      expect(health.lastModelLoadDurationMs, greaterThan(0));
      expect(
        health.estimatedTextureMemoryBytes,
        report.estimatedTextureMemoryBytes,
      );
      expect(health.contextLost, isFalse);
      expect(health.contextLossCount, 0);
      loadedTextureCounts.add(health.rendererTextureCount);
      loadDurationsMs.add(health.lastModelLoadDurationMs);

      await controller.unloadModel();
      await _settleRenderer(tester);
      final unloaded = await controller.getRuntimeHealth();
      expect(unloaded.modelLoaded, isFalse);
      expect(unloaded.estimatedTextureMemoryBytes, 0);
      expect(unloaded.contextLossCount, 0);
      unloadedTextureCounts.add(unloaded.rendererTextureCount);
    }

    expect(
      loadedTextureCounts.reduce(_max) - loadedTextureCounts.reduce(_min),
      lessThanOrEqualTo(1),
      reason: 'Repeated loads must not accumulate renderer textures.',
    );
    expect(
      unloadedTextureCounts.last,
      lessThanOrEqualTo(unloadedTextureCounts.first + 1),
      reason: 'Repeated unloads must return to a stable texture baseline.',
    );

    await controller.loadModel('assets/vrm/', 'sample.vrm');
    await controller.playAnimation(
      'assets/vrma/',
      'sample.vrma',
      fadeDuration: 0.25,
    );

    final speechFinished = controller.onSpeechFinished.first;
    final speech = await controller.beginSpeech(
      mode: VrmSpeechMode.amplitude,
      startDelay: const Duration(milliseconds: 250),
    );
    const batchDuration = Duration(milliseconds: 500);
    const frameDuration = Duration(milliseconds: 50);
    final totalDuration = Duration(seconds: _soakSeconds);
    performancePhase = _PerformancePhase.steady;
    final stopwatch = Stopwatch()..start();
    var batchIndex = 0;
    while (stopwatch.elapsed < totalDuration) {
      final batchStart = batchDuration * batchIndex;
      final frames = <AmplitudeFrame>[
        for (var index = 0; index < 10; index += 1)
          AmplitudeFrame(
            amplitude: index.isEven ? 0.75 : 0.2,
            timestamp: batchStart + frameDuration * index,
            duration: frameDuration,
          ),
      ];
      expect(await speech.appendAmplitudes(frames), isTrue);

      if (batchIndex > 0 && batchIndex % 10 == 0) {
        await controller.setPose(
          (batchIndex ~/ 10).isEven ? presenterOpenPose : loungePose,
          fadeDuration: 0.3,
        );
      } else if (batchIndex > 0 && batchIndex % 10 == 5) {
        await controller.playAnimation(
          'assets/vrma/',
          'sample.vrma',
          fadeDuration: 0.3,
        );
      }

      if (batchIndex.isEven) {
        healthSamples.add(await controller.getRuntimeHealth());
      }
      await tester.pump(const Duration(milliseconds: 50));
      final elapsedWithinBatch = Duration(
        milliseconds:
            stopwatch.elapsedMilliseconds % batchDuration.inMilliseconds,
      );
      final remaining = batchDuration - elapsedWithinBatch;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
      batchIndex += 1;
    }

    expect(await speech.finish(totalDuration), isTrue);
    expect(
      (await speechFinished.timeout(const Duration(seconds: 5))).sessionId,
      speech.id,
    );

    final finalSnapshot = await controller.getPerformanceSnapshot();
    final finalHealth = await controller.getRuntimeHealth();
    final measuredLoadSamples = loadPhaseSamples
        .where((sample) => sample.fps > 0)
        .toList();
    final measuredSteadySamples = <VrmPerformanceSnapshot>[
      ...steadyStateSamples.where((sample) => sample.fps > 0),
      if (finalSnapshot.fps > 0) finalSnapshot,
    ];
    expect(measuredSteadySamples, isNotEmpty);
    for (final sample in [...measuredLoadSamples, ...measuredSteadySamples]) {
      expect(sample.fpsCap, 30);
      expect(sample.pixelRatio, inInclusiveRange(0.75, 1));
      expect(sample.frameTimeP50Ms, lessThanOrEqualTo(sample.frameTimeP95Ms));
    }
    for (final health in healthSamples) {
      expect(health.contextLost, isFalse);
      expect(health.contextLossCount, 0);
      expect(
        health.rendererTextureCount,
        lessThanOrEqualTo(loadedTextureCounts.first + 1),
      );
    }
    expect(finalHealth.contextLost, isFalse);
    expect(finalHealth.contextLossCount, 0);
    expect(errors, isEmpty);

    final fpsValues = measuredSteadySamples
        .map((sample) => sample.fps)
        .toList();
    expect(
      _average(fpsValues),
      lessThanOrEqualTo(finalSnapshot.fpsCap + 5),
      reason: 'The sustained FPS average must respect the configured cap.',
    );
    final ratios = measuredSteadySamples
        .map((sample) => sample.pixelRatio)
        .toList();
    final p50Values = measuredSteadySamples
        .map((sample) => sample.frameTimeP50Ms)
        .toList();
    final p95Values = measuredSteadySamples
        .map((sample) => sample.frameTimeP95Ms)
        .toList();
    if (measuredLoadSamples.isNotEmpty) {
      final loadP50Values = measuredLoadSamples
          .map((sample) => sample.frameTimeP50Ms)
          .toList();
      final loadP95Values = measuredLoadSamples
          .map((sample) => sample.frameTimeP95Ms)
          .toList();
      debugPrint(
        'runtime_soak_load: loads=$_loadCycles, '
        'samples=${measuredLoadSamples.length}, '
        'frameP50Max=${loadP50Values.reduce(_max).toStringAsFixed(1)}ms, '
        'frameP95Max=${loadP95Values.reduce(_max).toStringAsFixed(1)}ms',
      );
    }
    debugPrint(
      'runtime_soak_steady: duration=${_soakSeconds}s, loads=$_loadCycles, '
      'samples=${measuredSteadySamples.length}, '
      'fps=${fpsValues.reduce(_min).toStringAsFixed(1)}-'
      '${fpsValues.reduce(_max).toStringAsFixed(1)} '
      '(avg=${_average(fpsValues).toStringAsFixed(1)}), '
      'frameP50Max=${p50Values.reduce(_max).toStringAsFixed(1)}ms, '
      'frameP95Max=${p95Values.reduce(_max).toStringAsFixed(1)}ms, '
      'pixelRatio=${ratios.reduce(_min).toStringAsFixed(2)}-'
      '${ratios.reduce(_max).toStringAsFixed(2)}, '
      'textures=${loadedTextureCounts.join(',')}/'
      '${unloadedTextureCounts.join(',')}, '
      'modelTextureBytes=$expectedTextureMemoryBytes, modelTextureMiB='
      '${(expectedTextureMemoryBytes! / (1024 * 1024)).toStringAsFixed(1)}, '
      'loadMs=${loadDurationsMs.map((value) => value.toStringAsFixed(1)).join(',')}/'
      '${finalHealth.lastModelLoadDurationMs.toStringAsFixed(1)}',
    );

    await controller.unloadModel();
    // Model assessment restores adaptive-quality settings asynchronously after
    // onModelUnloaded. Let that bridge command finish before detaching WebView.
    await _settleRenderer(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

Future<void> _settleRenderer(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 50));
  await Future<void>.delayed(const Duration(milliseconds: 750));
}

T _min<T extends num>(T first, T second) => first < second ? first : second;

T _max<T extends num>(T first, T second) => first > second ? first : second;

double _average(List<double> values) =>
    values.reduce((first, second) => first + second) / values.length;

enum _PerformancePhase { load, steady }
