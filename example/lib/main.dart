import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';

void main() => runApp(const VrmExampleApp());

class VrmExampleApp extends StatelessWidget {
  const VrmExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'flutter_three_vrm',
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
  final VrmController _controller = VrmController();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  VrmGraphicsPreset _graphicsPreset = VrmGraphicsPreset.balanced;
  VrmPerformanceSnapshot? _performance;
  VrmModelAssessment? _modelAssessment;
  VrmTransform? _savedTransform;
  String _status = 'Инициализация VRM runtime…';
  bool _modelLoaded = false;
  bool _busy = false;
  bool _animationPaused = false;
  bool _adaptiveQuality = true;
  double _amplitude = 0;

  @override
  void initState() {
    super.initState();
    _subscriptions
      ..add(
        _controller.onModelLoaded.listen((event) {
          _update(() {
            _modelLoaded = true;
            _status = 'Загружен ${event.name} (VRM ${event.version})';
          });
        }),
      )
      ..add(
        _controller.onModelReport.listen((event) {
          final report = event.report;
          _update(() {
            _status =
                '${report.name}: ${report.triangles} triangles, '
                '${report.textures} textures, ${report.humanoidBones} bones';
          });
        }),
      )
      ..add(
        _controller.onModelAssessment.listen((event) {
          _update(() => _modelAssessment = event.assessment);
        }),
      )
      ..add(
        _controller.onModelUnloaded.listen((_) {
          _update(() {
            _modelLoaded = false;
            _modelAssessment = null;
            _status = 'Аватар выгружен';
          });
        }),
      )
      ..add(
        _controller.onAnimationStarted.listen(
          (event) => _update(() => _status = 'Анимация: ${event.name}'),
        ),
      )
      ..add(
        _controller.onAnimationFinished.listen(
          (event) => _update(() => _status = 'Завершено: ${event.name}'),
        ),
      )
      ..add(
        _controller.onPerformance.listen(
          (event) => _update(() => _performance = event.snapshot),
        ),
      )
      ..add(
        _controller.onWebGlContextChanged.listen((event) {
          _update(() {
            _status = switch (event.state) {
              VrmWebGlContextState.lost =>
                'WebGL context потерян, ожидаю восстановления…',
              VrmWebGlContextState.restored => 'WebGL context восстановлен',
            };
          });
        }),
      )
      ..add(
        _controller.onError.listen(
          (event) => _update(() => _status = 'Ошибка: ${event.message}'),
        ),
      );
  }

  void _update(VoidCallback callback) {
    if (mounted) setState(callback);
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
    } on Object catch (error) {
      _update(() => _status = 'Ошибка: $error');
    } finally {
      _update(() => _busy = false);
    }
  }

  Future<void> _initialize(VrmController controller) {
    return _run(() async {
      final health = await controller.getRuntimeHealth();
      debugPrint(
        'VRM runtime ${health.runtimeVersion}, three r${health.threeRevision}, '
        'WebGL ${health.webGlVersion}',
      );
      await controller.loadModel('assets/vrm/', 'sample.vrm');
      await controller.playAnimation(
        'assets/vrma/',
        'sample.vrma',
        fadeDuration: 0.25,
      );
    });
  }

  Future<void> _loadModel() {
    return _run(() => _controller.loadModel('assets/vrm/', 'sample.vrm'));
  }

  Future<void> _play({bool loop = true}) {
    return _run(
      () => _controller.playAnimation(
        'assets/vrma/',
        'sample.vrma',
        loop: loop,
        fadeDuration: 0.3,
      ),
    );
  }

  Future<void> _applyHeadPose() {
    return _run(
      () => _controller.setPose(
        VrmPose({
          VrmHumanBone.head: const VrmPoseTransform(
            rotation: VrmQuaternion(0, 0.21644, 0, 0.9763),
          ),
          VrmHumanBone.leftUpperArm: const VrmPoseTransform(
            rotation: VrmQuaternion(0, 0, 0.13053, 0.99144),
          ),
        }),
      ),
    );
  }

  Future<void> _toggleAnimation() async {
    if (_animationPaused) {
      await _controller.resumeAnimation();
    } else {
      await _controller.pauseAnimation();
    }
    _update(() => _animationPaused = !_animationPaused);
  }

  Future<void> _setGraphicsPreset(VrmGraphicsPreset preset) async {
    await _controller.setGraphicsPreset(preset);
    _update(() => _graphicsPreset = preset);
  }

  Future<void> _setAdaptiveQuality(bool enabled) async {
    await _controller.setAdaptiveQuality(
      VrmAdaptiveQualitySettings(enabled: enabled),
    );
    _update(() => _adaptiveQuality = enabled);
  }

  Future<void> _saveCamera() async {
    final transform = await _controller.getTransform();
    _update(() {
      _savedTransform = transform;
      _status = 'Положение камеры сохранено';
    });
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: VrmView(
              controller: _controller,
              graphicsPreset: _graphicsPreset,
              adaptiveQuality: VrmAdaptiveQualitySettings(
                enabled: _adaptiveQuality,
                targetFps: 55,
                minPixelRatio: 0.75,
                maxPixelRatio: 1.5,
              ),
              backgroundColor: const Color(0xFF171823),
              lifecyclePolicy: VrmRenderLifecyclePolicy.platformDefault,
              onCreated: _initialize,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _StatusBar(
                    status: _status,
                    busy: _busy,
                    modelLoaded: _modelLoaded,
                    performance: _performance,
                    modelAssessment: _modelAssessment,
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: _ControlPanel(
                        graphicsPreset: _graphicsPreset,
                        adaptiveQuality: _adaptiveQuality,
                        animationPaused: _animationPaused,
                        amplitude: _amplitude,
                        hasSavedCamera: _savedTransform != null,
                        onLoadModel: _loadModel,
                        onPlayAnimation: _play,
                        onToggleAnimation: _toggleAnimation,
                        onApplyPose: _applyHeadPose,
                        onResetPose: () => _run(_controller.resetPose),
                        onPresetChanged: _setGraphicsPreset,
                        onAdaptiveChanged: _setAdaptiveQuality,
                        onSaveCamera: _saveCamera,
                        onRestoreCamera: () {
                          final transform = _savedTransform;
                          if (transform != null) {
                            _run(() => _controller.setTransform(transform));
                          }
                        },
                        onAmplitudeChanged: (value) {
                          setState(() => _amplitude = value);
                          _controller.setLipSyncAmplitude(value);
                        },
                        onHappy: () => _controller.setExpression(
                          VrmExpression.happy,
                          weight: 0.8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
      color: const Color(0xD9202130),
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
            if (stats != null)
              Text(
                '${stats.fps.toStringAsFixed(0)} FPS  '
                '${stats.pixelRatio.toStringAsFixed(2)}×  '
                '${stats.triangles ~/ 1000}k △',
                style: Theme.of(context).textTheme.labelMedium,
              ),
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

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.graphicsPreset,
    required this.adaptiveQuality,
    required this.animationPaused,
    required this.amplitude,
    required this.hasSavedCamera,
    required this.onLoadModel,
    required this.onPlayAnimation,
    required this.onToggleAnimation,
    required this.onApplyPose,
    required this.onResetPose,
    required this.onPresetChanged,
    required this.onAdaptiveChanged,
    required this.onSaveCamera,
    required this.onRestoreCamera,
    required this.onAmplitudeChanged,
    required this.onHappy,
  });

  final VrmGraphicsPreset graphicsPreset;
  final bool adaptiveQuality;
  final bool animationPaused;
  final double amplitude;
  final bool hasSavedCamera;
  final Future<void> Function() onLoadModel;
  final Future<void> Function({bool loop}) onPlayAnimation;
  final Future<void> Function() onToggleAnimation;
  final Future<void> Function() onApplyPose;
  final Future<void> Function() onResetPose;
  final Future<void> Function(VrmGraphicsPreset) onPresetChanged;
  final Future<void> Function(bool) onAdaptiveChanged;
  final Future<void> Function() onSaveCamera;
  final VoidCallback onRestoreCamera;
  final ValueChanged<double> onAmplitudeChanged;
  final VoidCallback onHappy;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xE6202130),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 310),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Аватар'),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: onLoadModel,
                    child: const Text('Перезагрузить модель'),
                  ),
                ],
              ),
              const Text('Анимация и поза'),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: onPlayAnimation,
                    child: const Text('VRMA'),
                  ),
                  IconButton.filledTonal(
                    onPressed: onToggleAnimation,
                    icon: Icon(
                      animationPaused ? Icons.play_arrow : Icons.pause,
                    ),
                    tooltip: animationPaused ? 'Продолжить' : 'Пауза',
                  ),
                  OutlinedButton(
                    onPressed: onApplyPose,
                    child: const Text('Pose'),
                  ),
                  OutlinedButton(
                    onPressed: onResetPose,
                    child: const Text('Reset pose'),
                  ),
                  OutlinedButton(
                    onPressed: onHappy,
                    child: const Text('Happy'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text('Lip amplitude'),
                  Expanded(
                    child: Slider(
                      value: amplitude,
                      onChanged: onAmplitudeChanged,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<VrmGraphicsPreset>(
                      segments: const [
                        ButtonSegment(
                          value: VrmGraphicsPreset.performance,
                          label: Text('30 FPS'),
                        ),
                        ButtonSegment(
                          value: VrmGraphicsPreset.balanced,
                          label: Text('Balanced'),
                        ),
                        ButtonSegment(
                          value: VrmGraphicsPreset.quality,
                          label: Text('Quality'),
                        ),
                      ],
                      selected: {graphicsPreset},
                      onSelectionChanged: (value) =>
                          onPresetChanged(value.first),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('Auto'),
                  Switch(value: adaptiveQuality, onChanged: onAdaptiveChanged),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: onSaveCamera,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Сохранить камеру'),
                  ),
                  TextButton.icon(
                    onPressed: hasSavedCamera ? onRestoreCamera : null,
                    icon: const Icon(Icons.restore),
                    label: const Text('Восстановить'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
