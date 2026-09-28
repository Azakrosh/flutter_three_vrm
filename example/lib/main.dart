import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';

import 'sample_poses.dart';

part 'demo_commands.dart';

void main() => runApp(const VrmExampleApp());

class VrmExampleApp extends StatelessWidget {
  const VrmExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'flutter_three_vrm command gallery',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7657FF),
          brightness: Brightness.dark,
        ),
      ),
      home: const AvatarDemoPage(),
    );
  }
}

class AvatarDemoPage extends StatefulWidget {
  const AvatarDemoPage({super.key});

  @override
  State<AvatarDemoPage> createState() => _AvatarDemoPageState();
}

class _AvatarDemoPageState extends State<AvatarDemoPage> {
  static const modelFolder = 'assets/vrm/';
  static const modelFile = 'sample.vrm';
  static const animationFolder = 'assets/vrma/';
  static const animationFile = 'sample.vrma';
  static const backgroundAsset = 'assets/images/backgrounds/background.svg';

  final VrmController controller = VrmController();
  final List<StreamSubscription<dynamic>> subscriptions = [];

  VrmGraphicsPreset graphicsPreset = VrmGraphicsPreset.balanced;
  VrmCameraMode cameraMode = VrmCameraMode.constrained;
  VrmExpression expression = VrmExpression.happy;
  VrmPerformanceSnapshot? performance;
  VrmModelAssessment? modelAssessment;
  VrmTransform? savedTransform;
  String status = 'Инициализация VRM runtime…';
  bool modelLoaded = false;
  bool busy = false;
  bool animationPaused = false;
  bool adaptiveQuality = true;
  bool autoBlink = true;
  bool autoSaccades = true;
  bool shadows = true;
  double amplitude = 0;
  double animationSpeed = 1;
  double expressionWeight = 0.8;

  @override
  void initState() {
    super.initState();
    subscriptions
      ..add(
        controller.onModelLoaded.listen((event) {
          update(() {
            modelLoaded = true;
            status = 'Загружен ${event.name} (VRM ${event.version})';
          });
        }),
      )
      ..add(
        controller.onModelReport.listen((event) {
          final report = event.report;
          update(() {
            status =
                '${report.name}: ${report.triangles} triangles, '
                '${report.textures} textures, ${report.humanoidBones} bones';
          });
        }),
      )
      ..add(
        controller.onModelAssessment.listen((event) {
          update(() => modelAssessment = event.assessment);
        }),
      )
      ..add(
        controller.onModelUnloaded.listen((_) {
          update(() {
            modelLoaded = false;
            modelAssessment = null;
            animationPaused = false;
            status = 'Аватар выгружен';
          });
        }),
      )
      ..add(
        controller.onAnimationStarted.listen((event) {
          update(() {
            animationPaused = false;
            status = 'Анимация: ${event.name}';
          });
        }),
      )
      ..add(
        controller.onAnimationFinished.listen((event) {
          update(() {
            animationPaused = false;
            status = 'Завершено: ${event.name}';
          });
        }),
      )
      ..add(
        controller.onExpressionChanged.listen((event) {
          update(() => status = 'Выражение: ${event.expression}');
        }),
      )
      ..add(
        controller.onSpeechFinished.listen((_) {
          update(() => status = 'Speech timeline завершён');
        }),
      )
      ..add(
        controller.onPerformance.listen(
          (event) => update(() => performance = event.snapshot),
        ),
      )
      ..add(
        controller.onWebGlContextChanged.listen((event) {
          update(() {
            status = switch (event.state) {
              VrmWebGlContextState.lost =>
                'WebGL context потерян, ожидаю восстановления…',
              VrmWebGlContextState.restored => 'WebGL context восстановлен',
            };
          });
        }),
      )
      ..add(
        controller.onError.listen(
          (event) => update(() => status = 'Ошибка: ${event.message}'),
        ),
      );
  }

  void update(VoidCallback callback) {
    if (mounted) setState(callback);
  }

  Future<void> runCommand(
    String? successMessage,
    FutureOr<void> Function() operation,
  ) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await Future<void>.sync(operation);
      if (successMessage != null) {
        update(() => status = successMessage);
      }
    } on Object catch (error) {
      update(() => status = 'Ошибка: $error');
    } finally {
      update(() => busy = false);
    }
  }

  VoidCallback? command(
    String? successMessage,
    FutureOr<void> Function() operation,
  ) {
    if (busy) return null;
    return () => unawaited(runCommand(successMessage, operation));
  }

  Future<void> initialize(VrmController controller) {
    return runCommand(null, () async {
      final health = await controller.getRuntimeHealth();
      update(() {
        status =
            'Runtime ${health.runtimeVersion}, three r${health.threeRevision}, '
            'three-vrm ${health.threeVrmVersion}';
      });
      await controller.loadModel(modelFolder, modelFile);
      await controller.playAnimation(
        animationFolder,
        animationFile,
        fadeDuration: 0.25,
      );
    });
  }

  Future<void> playAnimation({required bool loop}) async {
    await controller.playAnimation(
      animationFolder,
      animationFile,
      loop: loop,
      speed: animationSpeed,
      fadeDuration: 0.35,
    );
  }

  Future<void> toggleAnimation() async {
    if (animationPaused) {
      await controller.resumeAnimation(speed: animationSpeed);
    } else {
      await controller.pauseAnimation();
    }
    update(() => animationPaused = !animationPaused);
  }

  Future<void> setBackground(
    String label,
    Color color, {
    String? asset,
    bool transparent = false,
  }) async {
    await controller.setBackground(
      color: color,
      transparent: transparent,
      imageAssetPath: asset,
    );
    controller.setEnvironmentColor(color, intensity: 0.45);
    update(() => status = 'Фон: $label');
  }

  Future<void> saveCamera() async {
    final transform = await controller.getTransform();
    update(() {
      savedTransform = transform;
      status = 'Камера сохранена: $transform';
    });
  }

  Future<void> showRuntimeHealth() async {
    final health = await controller.getRuntimeHealth();
    final textureMiB = health.estimatedTextureMemoryBytes / (1024 * 1024);
    update(() {
      status =
          'WebGL ${health.webGlVersion}; textures ${health.rendererTextureCount} '
          '(${textureMiB.toStringAsFixed(1)} MiB); '
          'context loss ${health.contextLossCount}';
    });
  }

  Future<void> showPerformance() async {
    final snapshot = await controller.getPerformanceSnapshot();
    update(() {
      performance = snapshot;
      status =
          '${snapshot.fps.toStringAsFixed(1)} FPS; '
          'p50/p95 ${snapshot.frameTimeP50Ms.toStringAsFixed(1)}/'
          '${snapshot.frameTimeP95Ms.toStringAsFixed(1)} ms; '
          '${snapshot.drawCalls} draw calls';
    });
  }

  void showHostResources() {
    final snapshot = controller.captureHostResourceSnapshot();
    const mib = 1024 * 1024;
    update(() {
      status =
          'Host RSS ${(snapshot.currentRssBytes / mib).toStringAsFixed(1)} MiB; '
          'max ${(snapshot.maxRssBytes / mib).toStringAsFixed(1)} MiB; '
          'thermal ${snapshot.thermalStatus.name}';
    });
  }

  Future<void> runVisemeTimeline() {
    const step = 170;
    const sequence = <VrmViseme>[
      VrmViseme.aa,
      VrmViseme.ih,
      VrmViseme.ou,
      VrmViseme.ee,
      VrmViseme.oh,
      VrmViseme.sil,
    ];
    return controller.enqueueSpeechVisemes([
      for (var index = 0; index < sequence.length; index += 1)
        VisemeFrame(
          viseme: sequence[index],
          timestamp: Duration(milliseconds: index * step),
          duration: const Duration(milliseconds: 150),
        ),
    ]);
  }

  Future<void> runAmplitudeTimeline() {
    const values = <double>[0, 0.25, 0.7, 1, 0.45, 0.8, 0.2, 0];
    return controller.enqueueSpeechAmplitudes([
      for (var index = 0; index < values.length; index += 1)
        AmplitudeFrame(
          amplitude: values[index],
          timestamp: Duration(milliseconds: index * 120),
          duration: const Duration(milliseconds: 110),
        ),
    ]);
  }

  @override
  void dispose() {
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: VrmView(
              controller: controller,
              graphicsPreset: graphicsPreset,
              adaptiveQuality: VrmAdaptiveQualitySettings(
                enabled: adaptiveQuality,
                targetFps: 55,
                minPixelRatio: 0.75,
                maxPixelRatio: 1.5,
              ),
              backgroundColor: const Color(0xFF171823),
              lifecyclePolicy: VrmRenderLifecyclePolicy.platformDefault,
              onCreated: initialize,
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _StatusBar(
                        status: status,
                        busy: busy,
                        modelLoaded: modelLoaded,
                        performance: performance,
                        modelAssessment: modelAssessment,
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Align(
                          alignment: wide
                              ? Alignment.centerRight
                              : Alignment.bottomCenter,
                          child: SizedBox(
                            width: wide ? 430 : double.infinity,
                            height: wide
                                ? double.infinity
                                : (constraints.maxHeight * 0.55).clamp(
                                    330.0,
                                    470.0,
                                  ),
                            child: buildCommandPanel(),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.status,
    required this.busy,
    required this.modelLoaded,
    required this.performance,
    required this.modelAssessment,
  });

  final String status;
  final bool busy;
  final bool modelLoaded;
  final VrmPerformanceSnapshot? performance;
  final VrmModelAssessment? modelAssessment;

  @override
  Widget build(BuildContext context) {
    final stats = performance;
    return Card(
      margin: EdgeInsets.zero,
      color: const Color(0xE6202130),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            if (busy)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                modelLoaded ? Icons.check_circle : Icons.hourglass_top,
                size: 18,
                color: modelLoaded ? Colors.greenAccent : Colors.amberAccent,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(status, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            if (stats != null) ...[
              const SizedBox(width: 8),
              Text(
                '${stats.fps.toStringAsFixed(0)} FPS  '
                '${stats.pixelRatio.toStringAsFixed(2)}×',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
            if (modelAssessment case final assessment?) ...[
              const SizedBox(width: 8),
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(assessment.complexity.name),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
