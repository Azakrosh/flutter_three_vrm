import 'package:flutter/material.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';

void main() {
  runApp(const VtuberDemoApp());
}

class VtuberDemoApp extends StatelessWidget {
  const VtuberDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_three-vrm Vtuber Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF12141C),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: Brightness.dark,
        ),
      ),
      home: const ThreeVRMDemo(),
    );
  }
}

class ThreeVRMDemo extends StatefulWidget {
  const ThreeVRMDemo({super.key});

  @override
  State<ThreeVRMDemo> createState() => _ThreeVRMDemoState();
}

class _ThreeVRMDemoState extends State<ThreeVRMDemo>
    with WidgetsBindingObserver {
  final VrmController _vrmController = VrmController();
  late VrmAnimationQueue _queue;

  // Очередь анимаций
  final List<String> _testAnimationQueue = [
    'VRMA_04.vrma',
    'VRMA_05.vrma',
    'VRMA_06.vrma'
  ];
  int _currentQueueIndex = -1;

  void _playQueueAnimation() {
    if (_currentQueueIndex >= 0 &&
        _currentQueueIndex < _testAnimationQueue.length) {
      final anim = _testAnimationQueue[_currentQueueIndex];
      setState(() {
        _statusMessage = 'Очередь: играю $anim';
      });
      _vrmController.playAnimation('assets/vrma/', anim,
          loop: false, speed: 1.0);
    }
  }

  void _playAnimationQueue() {
    _queue = VrmAnimationQueue(
      controller: _vrmController,
      folderPath: 'assets/vrma/',
      fileNames: ['VRMA_04.vrma', 'VRMA_05.vrma', 'VRMA_06.vrma'],
      random: false,
      loop: false,
    );

    setState(() {
      _statusMessage = 'Запуск очереди анимаций...';
      _queue.start();
    });
  }

  double _lipSyncAmplitude = 0.0;
  String _statusMessage = 'Инициализация WebGL...';
  bool _isModelLoaded = false;
  bool _isAnimPaused = false;
  bool _shadowsEnabled = true;
  bool _antiAliasing = true;
  bool _vrmPhisics = true;
  double _animSpeed = 1.0;
  Color _bgColor = const Color(0xFF1E1E2C);
  double _directionalIntensity = 1.0;
  double _renderQuality = 1.5;
  int _fps = 60;
  double _camX = 0;
  double _camY = 0;
  double _camZoom = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribeToEvents();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Полностью останавливаем WebGL рендеринг для жесткой экономии батареи в фоне
      _vrmController.pauseRendering();
    } else if (state == AppLifecycleState.resumed) {
      // Возобновляем рендеринг при возврате в приложение
      _vrmController.resumeRendering();
    }
  }

  void _subscribeToEvents() {
    _vrmController.onAnimationFinished.listen((event) {
      if (_currentQueueIndex >= 0 &&
          _currentQueueIndex < _testAnimationQueue.length - 1) {
        _currentQueueIndex++;
        _playQueueAnimation();
      } else if (_currentQueueIndex == _testAnimationQueue.length - 1) {
        _currentQueueIndex = -1;
        _vrmController.stopAnimation();
        setState(() {
          _statusMessage = 'Очередь анимаций завершена';
        });
      }
    });

    _vrmController.onModelLoaded.listen((event) {
      setState(() {
        _isModelLoaded = true;
        _statusMessage = 'Модель загружена: ${event.name} (v${event.version})';
      });
    });

    _vrmController.onModelUnloaded.listen((_) {
      setState(() {
        _isModelLoaded = false;
        _statusMessage = 'Модель выгружена из сцены';
      });
    });

    _vrmController.onAnimationStarted.listen((event) {
      setState(() {
        _statusMessage = 'Воспроизведение VRMA: ${event.name}';
      });
    });

    _vrmController.onAnimationFinished.listen((event) {
      setState(() {
        _statusMessage = 'Завершено: ${event.name}';
      });
    });

    _vrmController.onError.listen((event) {
      debugPrint('⚠️ [VRM WebGL Error]: ${event.message}');
    });

    _vrmController.onTap.listen((event) {
      setState(() {
        _statusMessage =
            'Тап на 3D сцене: X=${event.x.toStringAsFixed(1)}, Y=${event.y.toStringAsFixed(1)}';
      });
    });
  }

  void _showModelsMenu() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext modelContext) {
        return Container(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Загрузка аватара',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white70),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.person, size: 18),
                      label: const Text('Аватар 1'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C5CE7),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        setState(() => _statusMessage = 'Аватар 1');
                        await _vrmController.loadModel(
                            'assets/vrm/', 'sample_0.vrm');
                        setState(() {}); // refresh UI after loading
                        if (!modelContext.mounted) return;
                        Navigator.pop(modelContext);
                      },
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.person_outline, size: 18),
                      label: const Text('Аватар 2'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0984E3),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        setState(() => _statusMessage = 'Аватар 2');
                        await _vrmController.loadModel(
                            'assets/vrm/', 'sample_1.vrm');
                        setState(() {}); // refresh UI after loading
                        if (!modelContext.mounted) return;
                        Navigator.pop(modelContext);
                      },
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.person_outline, size: 18),
                      label: const Text('Аватар 2'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0984E3),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        setState(() => _statusMessage = 'Аватар 3');
                        await _vrmController.loadModel(
                            'assets/vrm/', 'sample_2.vrm');
                        setState(() {}); // refresh UI after loading
                        if (!modelContext.mounted) return;
                        Navigator.pop(modelContext);
                      },
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Выгрузить модель'),
                onPressed: () {
                  _vrmController.unloadModel();
                  if (!modelContext.mounted) return;
                  Navigator.pop(modelContext);
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Управление камерой',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white70),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Сохранить камеру'),
                onPressed: () async {
                  final transform = await _vrmController.getTransform();
                  _camX = transform.x;
                  _camY = transform.y;
                  _camZoom = transform.zoom;
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Загрузить камеру'),
                onPressed: () {
                  _vrmController.setTransform(
                      VrmTransform(x: _camX, y: _camY, zoom: _camZoom));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showVRMAAnimationsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
            builder: (BuildContext context, StateSetter setModalState) {
          return Container(
            padding: const EdgeInsets.all(16.0),
            child: ListView(
              children: [
                const Text(
                  'VRMA Анимации Тела',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Wrap(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.directions_walk, size: 16),
                      label: const Text('Осмотреться'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00B894),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        _vrmController.playAnimation(
                            'assets/vrma/', 'LookAround.vrma');
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.directions_walk, size: 16),
                      label: const Text('VRMA_01'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00B894),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        _vrmController.playAnimation(
                            'assets/vrma/', 'VRMA_01.vrma');
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.directions_walk, size: 16),
                      label: const Text('VRMA_02'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00B894),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        _vrmController.playAnimation(
                            'assets/vrma/', 'VRMA_02.vrma');
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.directions_walk, size: 16),
                      label: const Text('VRMA_03'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00B894),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        _vrmController.playAnimation(
                            'assets/vrma/', 'VRMA_03.vrma');
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.directions_walk, size: 16),
                      label: const Text('VRMA_04'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00B894),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        _vrmController.playAnimation(
                            'assets/vrma/', 'VRMA_04.vrma');
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.directions_walk, size: 16),
                      label: const Text('VRMA_05'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00B894),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        _vrmController.playAnimation(
                            'assets/vrma/', 'VRMA_05.vrma');
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.directions_walk, size: 16),
                      label: const Text('VRMA_06'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00B894),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        _vrmController.playAnimation(
                            'assets/vrma/', 'VRMA_06.vrma');
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.directions_walk, size: 16),
                      label: const Text('VRMA_07'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00B894),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        _vrmController.playAnimation(
                            'assets/vrma/', 'VRMA_07.vrma');
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.psychology, size: 16),
                      label: const Text('Задуматься'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0984E3),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        _vrmController.playAnimation(
                            'assets/vrma/', 'Thinking.vrma');
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.sentiment_dissatisfied, size: 16),
                      label: const Text('Поникнуть'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD63031),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        _vrmController.playAnimation(
                            'assets/vrma/', 'Sad.vrma');
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      icon:
                          Icon(_isAnimPaused ? Icons.play_arrow : Icons.pause),
                      tooltip: _isAnimPaused ? 'Продолжить' : 'Пауза',
                      onPressed: () {
                        if (_isAnimPaused) {
                          _vrmController.resumeAnimation(speed: _animSpeed);
                        } else {
                          _vrmController.pauseAnimation();
                        }
                        setModalState(() {
                          _isAnimPaused = !_isAnimPaused;
                        });
                        // this.setState(() {
                        //   _isAnimPaused = !_isAnimPaused;
                        // });
                      },
                    ),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.stop),
                      tooltip: 'Остановить',
                      onPressed: () {
                        _vrmController.stopAnimation();
                        setState(() {
                          _isAnimPaused = false;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    const Icon(Icons.speed, size: 16, color: Color(0xFF00B894)),
                    const SizedBox(width: 8),
                    const Text('Скорость анимации:',
                        style: TextStyle(fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: _animSpeed,
                        min: 0.25,
                        max: 2.0,
                        divisions: 7,
                        label: '${_animSpeed}x',
                        onChanged: (val) {
                          setModalState(() {
                            _animSpeed = val;
                          });
                          setState(() {
                            _animSpeed = val;
                          });
                          _vrmController.setAnimationSpeed(val);
                        },
                      ),
                    ),
                    Text('${_animSpeed}x',
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.stream, size: 16),
                  label: const Text('Тест Очереди Анимаций'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (_testAnimationQueue.isNotEmpty) {
                      _currentQueueIndex = 0;
                      _playQueueAnimation();
                    }
                  },
                ),
                const SizedBox(height: 8),
                const Text('Очередь из пакета', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                Column(
                  children: [
                    Row(
                      children: [
                        TextButton(
                            onPressed: () {
                              _playAnimationQueue();
                            },
                            child: const Text('Старт')),
                        TextButton(
                            onPressed: () {
                              _queue.stop();
                            },
                            child: const Text('Стоп')),
                      ],
                    ),
                    Row(
                      children: [
                        TextButton(
                            onPressed: () {
                              _queue.pause();
                            },
                            child: const Text('Пауза')),
                        TextButton(
                            onPressed: () {
                              _queue.resume();
                            },
                            child: const Text('Продолжить')),
                      ],
                    ),
                    TextButton(
                        onPressed: () {
                          _queue.interrupt(
                              folderPath: 'assets/vrma/',
                              fileName: 'LookAround.vrma');
                        },
                        child: const Text('Вызов эмоции во время очереди')),
                  ],
                )
              ],
            ),
          );
        });
      },
    );
  }

  void _showEmotionsMenu() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext modelContext) {
        return Container(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Эмоции и Мимика',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar:
                        const Icon(Icons.sentiment_very_satisfied, size: 16),
                    label: const Text('Радость'),
                    onPressed: () => _vrmController.setExpression(
                        VrmExpression.happy,
                        layer: ExpressionLayer.eyes,
                        disableAutoBlink: true),
                  ),
                  ActionChip(
                    avatar:
                        const Icon(Icons.sentiment_very_dissatisfied, size: 16),
                    label: const Text('Грусть'),
                    onPressed: () => _vrmController.setExpression(
                        VrmExpression.sad,
                        layer: ExpressionLayer.brows,
                        disableAutoBlink: true),
                  ),
                  ActionChip(
                    avatar:
                        const Icon(Icons.sentiment_very_dissatisfied, size: 16),
                    label: const Text('Расслабление'),
                    onPressed: () => _vrmController.setExpression(
                        VrmExpression.relaxed,
                        layer: ExpressionLayer.eyes),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.sentiment_neutral, size: 16),
                    label: const Text('Злость'),
                    onPressed: () => _vrmController.setExpression(
                        VrmExpression.angry,
                        layer: ExpressionLayer.brows),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.sentiment_neutral, size: 16),
                    label: const Text('Удивление'),
                    onPressed: () => _vrmController.setExpression(
                        VrmExpression.surprised,
                        layer: ExpressionLayer.eyes),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.sentiment_neutral, size: 16),
                    label: const Text('Нейтральный'),
                    onPressed: () => _vrmController.clearAllExpressions(),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.visibility_off, size: 16),
                    label: const Text('Моргнуть'),
                    onPressed: () => _vrmController.setExpression(
                        VrmExpression.blink,
                        layer: ExpressionLayer.eyes),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.cleaning_services,
                        size: 16, color: Colors.orangeAccent),
                    label: const Text('Сбросить Мимику'),
                    onPressed: () => _vrmController.clearAllExpressions(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Набор эмоциий',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white70),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar:
                        const Icon(Icons.sentiment_very_satisfied, size: 16),
                    label: const Text('Радость'),
                    onPressed: () => _vrmController.setMood(VrmMood.happy,
                        disableAutoBlink: true),
                  ),
                  ActionChip(
                    avatar:
                        const Icon(Icons.sentiment_very_satisfied, size: 16),
                    label: const Text('Злость'),
                    onPressed: () => _vrmController.setMood(VrmMood.angry),
                  ),
                  ActionChip(
                    avatar:
                        const Icon(Icons.sentiment_very_satisfied, size: 16),
                    label: const Text('Грусть'),
                    onPressed: () => _vrmController.setMood(VrmMood.sad),
                  ),
                  ActionChip(
                    avatar:
                        const Icon(Icons.sentiment_very_satisfied, size: 16),
                    label: const Text('Удивление'),
                    onPressed: () => _vrmController.setMood(VrmMood.surprised),
                  ),
                  ActionChip(
                    avatar:
                        const Icon(Icons.sentiment_very_satisfied, size: 16),
                    label: const Text('Думает'),
                    onPressed: () => _vrmController.setMood(VrmMood.thinking),
                  ),
                  ActionChip(
                    avatar:
                        const Icon(Icons.sentiment_very_satisfied, size: 16),
                    label: const Text('Сонный'),
                    onPressed: () => _vrmController.setMood(VrmMood.custom(
                        expression: VrmExpression.happy,
                        expressionWeight: 0.7,
                        browExpression: VrmExpression.sad,
                        browWeight: 0.5,
                        wind: const VrmMoodWind(
                            type: VrmWindType.light,
                            direction: VrmWindDirection.left),
                        physics: const VrmMoodPhysics(
                            stiffness: 1.0, gravity: 1.0, drag: 1.0),
                        autoSaccades: true)),
                  ),
                  ActionChip(
                    avatar:
                        const Icon(Icons.sentiment_very_satisfied, size: 16),
                    label: const Text('Сброс'),
                    onPressed: () => _vrmController.clearMood(),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  void _showLipSyncMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext modelContext) {
        return StatefulBuilder(builder: (context, setModalState) {
          return Container(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Звук и Визуал',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.graphic_eq, color: Color(0xFFA29BFE)),
                    const SizedBox(width: 8),
                    const Text('Lip Sync (Громкость речи):',
                        style: TextStyle(fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: _lipSyncAmplitude,
                        onChanged: (val) {
                          setModalState(() {
                            _lipSyncAmplitude = val;
                          });
                          this.setState(() {
                            _lipSyncAmplitude = val;
                          });
                          _vrmController.setLipSyncAmplitude(val);
                        },
                      ),
                    ),
                    Text('${(_lipSyncAmplitude * 100).toInt()}%',
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Text('Виземы (ElevenLabs):',
                          style:
                              TextStyle(fontSize: 12, color: Colors.white60)),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => _vrmController.setViseme(VrmViseme.aa),
                        child: const Text('AA'),
                      ),
                      const SizedBox(width: 4),
                      OutlinedButton(
                        onPressed: () => _vrmController.setViseme(VrmViseme.ih),
                        child: const Text('IH'),
                      ),
                      const SizedBox(width: 4),
                      OutlinedButton(
                        onPressed: () => _vrmController.setViseme(VrmViseme.ou),
                        child: const Text('OU'),
                      ),
                      const SizedBox(width: 4),
                      OutlinedButton(
                        onPressed: () => _vrmController.setViseme(VrmViseme.ee),
                        child: const Text('EE'),
                      ),
                      const SizedBox(width: 4),
                      OutlinedButton(
                        onPressed: () => _vrmController.setViseme(VrmViseme.oh),
                        child: const Text('OH'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.clear, size: 14),
                        label: const Text('Сбросить Рот'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orangeAccent,
                        ),
                        onPressed: () {
                          _vrmController
                              .clearExpressionLayer(ExpressionLayer.mouth);
                          setModalState(() {
                            _lipSyncAmplitude = 0.0;
                          });
                          this.setState(() {
                            _lipSyncAmplitude = 0.0;
                          });
                          _vrmController.setLipSyncAmplitude(0.0);
                        },
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.stream, size: 16),
                  label: const Text('Тест Очереди Визем'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    // Фейковый поток визем (таймлайн на 2 секунды)
                    final fakeFrames = [
                      const VisemeFrame(
                          viseme: VrmViseme.oh,
                          timestamp: Duration(milliseconds: 0)),
                      const VisemeFrame(
                          viseme: VrmViseme.ee,
                          timestamp: Duration(milliseconds: 300)),
                      const VisemeFrame(
                          viseme: VrmViseme.aa,
                          timestamp: Duration(milliseconds: 600)),
                      const VisemeFrame(
                          viseme: VrmViseme.ih,
                          timestamp: Duration(milliseconds: 900)),
                      const VisemeFrame(
                          viseme: VrmViseme.ou,
                          timestamp: Duration(milliseconds: 1200)),
                      const VisemeFrame(
                          viseme: VrmViseme.aa,
                          timestamp: Duration(milliseconds: 1500)),
                      const VisemeFrame(
                          viseme: VrmViseme.oh,
                          timestamp: Duration(milliseconds: 1800)),
                    ];
                    _vrmController.enqueueSpeechVisemes(fakeFrames);
                    this.setState(() {
                      _statusMessage =
                          'Проигрывание очереди визем (LipSync)...';
                    });

                    // Имитируем событие от бэкенда об окончании аудио потока через 2 секунды
                    Future.delayed(const Duration(milliseconds: 2100), () {
                      if (mounted) {
                        _vrmController
                            .clearExpressionLayer(ExpressionLayer.mouth);
                        this.setState(() {
                          _statusMessage = 'Поток визем завершен. Рот закрыт.';
                        });
                      }
                    });
                  },
                ),
              ],
            ),
          );
        });
      },
    );
  }

  void _showBackgroundMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext modelContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                children: [
                  const Text(
                    'Фон и Освещение Сцены',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        TextButton(
                            onPressed: () {
                              _vrmController.setBackground(
                                  color: _bgColor,
                                  imageAssetPath:
                                      'assets/images/backgrounds/bg_0.jpg');
                              _vrmController.setEnvironmentColor(_bgColor,
                                  intensity: 0.7);
                            },
                            child: const Text('Установить фон 1')),
                        TextButton(
                            onPressed: () {
                              _vrmController.setBackground(
                                  color: _bgColor,
                                  imageAssetPath:
                                      'assets/images/backgrounds/bg_1.jpg');
                              _vrmController.setEnvironmentColor(_bgColor,
                                  intensity: 0.7);
                            },
                            child: const Text('Установить фон 2')),
                        TextButton(
                          onPressed: () {
                            _vrmController.setBackground(color: _bgColor);
                            _vrmController.setEnvironmentColor(
                                const Color(0xFFFFFFFF),
                                intensity: 0.7);
                          },
                          child: const Text('Удалить фон'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      spacing: 4,
                      children: [
                        TextButton(
                            onPressed: () {
                              _vrmController.setEnvironmentColor(
                                  const Color(0xFF11DF18),
                                  intensity: 0.7);
                            },
                            child: const Text('Подсветка модели 1')),
                        TextButton(
                            onPressed: () {
                              _vrmController.setEnvironmentColor(
                                  const Color(0xFF910BAF),
                                  intensity: 0.7);
                            },
                            child: const Text('Подсветка модели 2')),
                        TextButton(
                            onPressed: () {
                              _vrmController.setEnvironmentColor(
                                  const Color(0xFFAAAAAA),
                                  intensity: 0.7);
                            },
                            child: const Text('Подсветка модели 3')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Цвет фона'),
                      const SizedBox(width: 16),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.circle,
                            color: Color(0xFF1E1E2C), size: 18),
                        tooltip: 'Темный',
                        onPressed: () {
                          setState(() {
                            _bgColor = const Color(0xFF1E1E2C);
                          });
                          _vrmController.setBackground(color: _bgColor);
                        },
                      ),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.circle,
                            color: Color(0xFF6C5CE7), size: 18),
                        tooltip: 'Фиолетовый',
                        onPressed: () {
                          setState(() {
                            _bgColor = const Color(0xFF6C5CE7);
                          });
                          _vrmController.setBackground(color: _bgColor);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.wb_sunny, size: 16, color: Colors.amber),
                      const SizedBox(width: 8),
                      const Text('Свет:', style: TextStyle(fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: _directionalIntensity,
                          min: 0.0,
                          max: 3.0,
                          divisions: 30,
                          label: _directionalIntensity.toStringAsFixed(2),
                          onChanged: (val) {
                            setModalState(() {
                              _directionalIntensity = val;
                            });
                            this.setState(() {
                              _directionalIntensity = val;
                            });
                            _vrmController.setLighting(
                                directionalIntensity: val,
                                ambientIntensity: val * 0.8);
                          },
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'Ветер',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text('Left:'),
                        const SizedBox(width: 8),
                        TextButton(
                            onPressed: () {
                              _vrmController.setWind(
                                type: VrmWindType.light,
                                direction: VrmWindDirection.left,
                              );
                            },
                            child: const Text('light')),
                        TextButton(
                            onPressed: () {
                              _vrmController.setWind(
                                type: VrmWindType.strong,
                                direction: VrmWindDirection.left,
                              );
                            },
                            child: const Text('strong')),
                        TextButton(
                            onPressed: () {
                              _vrmController.setWind(
                                type: VrmWindType.storm,
                                direction: VrmWindDirection.left,
                              );
                            },
                            child: const Text('storm')),
                      ],
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text('Right:'),
                        const SizedBox(width: 8),
                        TextButton(
                            onPressed: () {
                              _vrmController.setWind(
                                type: VrmWindType.light,
                                direction: VrmWindDirection.right,
                              );
                            },
                            child: const Text('light')),
                        TextButton(
                            onPressed: () {
                              _vrmController.setWind(
                                type: VrmWindType.strong,
                                direction: VrmWindDirection.right,
                              );
                            },
                            child: const Text('strong')),
                        TextButton(
                            onPressed: () {
                              _vrmController.setWind(
                                type: VrmWindType.storm,
                                direction: VrmWindDirection.right,
                              );
                            },
                            child: const Text('storm')),
                      ],
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text('Front:'),
                        const SizedBox(width: 8),
                        TextButton(
                            onPressed: () {
                              _vrmController.setWind(
                                type: VrmWindType.light,
                                direction: VrmWindDirection.front,
                              );
                            },
                            child: const Text('light')),
                        TextButton(
                            onPressed: () {
                              _vrmController.setWind(
                                type: VrmWindType.strong,
                                direction: VrmWindDirection.front,
                              );
                            },
                            child: const Text('strong')),
                        TextButton(
                            onPressed: () {
                              _vrmController.setWind(
                                type: VrmWindType.storm,
                                direction: VrmWindDirection.front,
                              );
                            },
                            child: const Text('storm')),
                      ],
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text('Back:'),
                        const SizedBox(width: 8),
                        TextButton(
                            onPressed: () {
                              _vrmController.setWind(
                                type: VrmWindType.light,
                                direction: VrmWindDirection.back,
                              );
                            },
                            child: const Text('light')),
                        TextButton(
                            onPressed: () {
                              _vrmController.setWind(
                                type: VrmWindType.strong,
                                direction: VrmWindDirection.back,
                              );
                            },
                            child: const Text('strong')),
                        TextButton(
                            onPressed: () {
                              _vrmController.setWind(
                                type: VrmWindType.storm,
                                direction: VrmWindDirection.back,
                              );
                            },
                            child: const Text('storm')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _vrmController.stopWind();
                      },
                      label: const Text('Без ветра')),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showGraphicsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext modelContext) {
        return StatefulBuilder(builder: (context, setModalState) {
          return Container(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Параметры графики',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white70),
                ),
                const SizedBox(width: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Text('Качество:', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 8),
                      SegmentedButton<double>(
                        segments: const [
                          ButtonSegment(
                              value: 1.0,
                              label:
                                  Text('Low', style: TextStyle(fontSize: 11))),
                          ButtonSegment(
                              value: 1.5,
                              label:
                                  Text('Med', style: TextStyle(fontSize: 11))),
                          ButtonSegment(
                              value: 2.0,
                              label:
                                  Text('High', style: TextStyle(fontSize: 11))),
                        ],
                        selected: {_renderQuality},
                        showSelectedIcon: false,
                        onSelectionChanged: (set) {
                          setModalState(() {
                            _renderQuality = set.first;
                          });
                          this.setState(() {
                            _renderQuality = set.first;
                          });
                          _vrmController.setGraphicsSettings(
                              pixelRatio: _renderQuality);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Тени:', style: TextStyle(fontSize: 12)),
                    Switch(
                      value: _shadowsEnabled,
                      activeThumbColor: const Color(0xFF6C5CE7),
                      onChanged: (val) {
                        setModalState(() {
                          _shadowsEnabled = val;
                        });
                        this.setState(() {
                          _shadowsEnabled = val;
                        });
                        _vrmController.setShadows(val);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Сглаживание:', style: TextStyle(fontSize: 12)),
                    Switch(
                      value: _antiAliasing,
                      activeThumbColor: const Color(0xFF6C5CE7),
                      onChanged: (val) {
                        setModalState(() {
                          _antiAliasing = val;
                        });
                        this.setState(() {
                          _antiAliasing = val;
                        });
                        _vrmController.setGraphicsSettings(antialias: val);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Физика VRM:', style: TextStyle(fontSize: 12)),
                    Switch(
                      value: _vrmPhisics,
                      activeThumbColor: const Color(0xFF6C5CE7),
                      onChanged: (val) {
                        setModalState(() {
                          _vrmPhisics = val;
                        });
                        this.setState(() {
                          _vrmPhisics = val;
                        });
                        _vrmController.setGraphicsSettings(enablePhysics: val);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('FPS:', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 8),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(
                            value: 30,
                            label: Text('30', style: TextStyle(fontSize: 11))),
                        ButtonSegment(
                            value: 60,
                            label: Text('60', style: TextStyle(fontSize: 11))),
                        ButtonSegment(
                            value: 0,
                            label: Text('Max', style: TextStyle(fontSize: 11))),
                      ],
                      selected: {_fps},
                      showSelectedIcon: false,
                      onSelectionChanged: (set) {
                        setModalState(() {
                          _fps = set.first;
                        });
                        this.setState(() {
                          _fps = set.first;
                        });
                        _vrmController.setGraphicsSettings(fpsCap: _fps);
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        });
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vrmController.dispose();
    _queue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E1F2C), Color(0xFF0F1017)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: VrmView(
                  controller: _vrmController,
                  transparent: false,
                  onCreated: (controller) {
                    setState(() {
                      _statusMessage =
                          'WebGL Готов. Выберите модель для загрузки.';
                    });
                  },
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Row(
                  children: [
                    if (_vrmController.isLoadingModel)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    else
                      Icon(
                        _isModelLoaded
                            ? Icons.check_circle
                            : Icons.info_outline,
                        color: _isModelLoaded
                            ? Colors.greenAccent
                            : Colors.orangeAccent,
                        size: 18,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.white70),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                  bottom: 0,
                  right: 0,
                  left: 0,
                  child: Wrap(
                    children: [
                      ElevatedButton(
                        child: const Text('Модели'),
                        onPressed: () {
                          _showModelsMenu();
                        },
                      ),
                      ElevatedButton(
                        child: const Text('Анимации'),
                        onPressed: () {
                          _showVRMAAnimationsMenu(context);
                        },
                      ),
                      ElevatedButton(
                        child: const Text('Эмоции'),
                        onPressed: () {
                          _showEmotionsMenu();
                        },
                      ),
                      ElevatedButton(
                        child: const Text('Мимика'),
                        onPressed: () {
                          _showLipSyncMenu(context);
                        },
                      ),
                      ElevatedButton(
                        child: const Text('Фон'),
                        onPressed: () {
                          _showBackgroundMenu(context);
                        },
                      ),
                      ElevatedButton(
                        child: const Text('Графика'),
                        onPressed: () {
                          _showGraphicsMenu(context);
                        },
                      ),
                    ],
                  ))
            ],
          ),
        ),
      ),
    );
  }
}
