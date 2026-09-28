part of 'main.dart';

extension _DemoCommandPages on _AvatarDemoPageState {
  Widget buildCommandPanel() {
    return _CommandPanel(
      tabs: const [
        Tab(icon: Icon(Icons.view_in_ar), text: 'Модель'),
        Tab(icon: Icon(Icons.directions_run), text: 'Движение'),
        Tab(icon: Icon(Icons.face), text: 'Лицо'),
        Tab(icon: Icon(Icons.record_voice_over), text: 'Речь'),
        Tab(icon: Icon(Icons.landscape), text: 'Сцена'),
        Tab(icon: Icon(Icons.videocam), text: 'Камера'),
        Tab(icon: Icon(Icons.speed), text: 'Графика'),
      ],
      pages: [
        modelCommands(),
        motionCommands(),
        faceCommands(),
        speechCommands(),
        sceneCommands(),
        cameraCommands(),
        graphicsCommands(),
      ],
    );
  }

  Widget modelCommands() {
    return _CommandPage(
      children: [
        const _CommandSectionHeader(
          title: 'Жизненный цикл модели',
          description: 'Загрузка, выгрузка и восстановление runtime.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: command(
                'Модель загружена',
                () => controller.loadModel(
                  _AvatarDemoPageState.modelFolder,
                  _AvatarDemoPageState.modelFile,
                ),
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('Загрузить заново'),
            ),
            OutlinedButton.icon(
              onPressed: command('Модель выгружена', controller.unloadModel),
              icon: const Icon(Icons.eject),
              label: const Text('Выгрузить'),
            ),
            OutlinedButton.icon(
              onPressed: command(
                'Runtime перезагружен, состояние восстановлено',
                controller.reloadRuntime,
              ),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reload runtime'),
            ),
          ],
        ),
        const _CommandSectionHeader(
          title: 'Информация',
          description: 'Отчёт модели и состояние WebGL runtime.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: command(null, controller.getModelReport),
              child: const Text('Model report'),
            ),
            OutlinedButton(
              onPressed: command(null, showRuntimeHealth),
              child: const Text('Runtime health'),
            ),
            OutlinedButton(
              onPressed: busy ? null : showHostResources,
              child: const Text('Host RSS'),
            ),
          ],
        ),
      ],
    );
  }

  Widget motionCommands() {
    return _CommandPage(
      children: [
        const _CommandSectionHeader(
          title: 'VRMA-анимация',
          description: 'Loop, finite playback, pause и плавная остановка.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: command(
                'VRMA запущена в цикле',
                () => playAnimation(loop: true),
              ),
              icon: const Icon(Icons.loop),
              label: const Text('VRMA loop'),
            ),
            FilledButton.tonalIcon(
              onPressed: command(
                'VRMA запущена один раз',
                () => playAnimation(loop: false),
              ),
              icon: const Icon(Icons.play_arrow),
              label: const Text('VRMA once'),
            ),
            IconButton.filledTonal(
              onPressed: command(
                animationPaused ? 'Продолжено' : 'Пауза',
                toggleAnimation,
              ),
              icon: Icon(animationPaused ? Icons.play_arrow : Icons.pause),
              tooltip: animationPaused ? 'Продолжить' : 'Пауза',
            ),
            OutlinedButton.icon(
              onPressed: command(
                'Анимация остановлена плавно',
                () => controller.stopAnimation(fadeDuration: 0.45),
              ),
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
            ),
          ],
        ),
        _LabeledSlider(
          label: 'Скорость',
          value: animationSpeed,
          min: 0.25,
          max: 2,
          divisions: 7,
          valueLabel: '${animationSpeed.toStringAsFixed(2)}×',
          onChanged: busy
              ? null
              : (value) => update(() => animationSpeed = value),
          onChangeEnd: busy
              ? null
              : (value) => unawaited(
                  runCommand(
                    'Скорость ${value.toStringAsFixed(2)}×',
                    () => controller.setAnimationSpeed(value),
                  ),
                ),
        ),
        const _CommandSectionHeader(
          title: 'Pose API',
          description: 'Переход VRMA ↔ Pose выполняется общим crossfade.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: command(
                'Presenter pose',
                () => controller.setPose(presenterOpenPose, fadeDuration: 0.65),
              ),
              child: const Text('Presenter'),
            ),
            OutlinedButton(
              onPressed: command(
                'Lounge pose',
                () => controller.setPose(loungePose, fadeDuration: 0.65),
              ),
              child: const Text('Lounge'),
            ),
            OutlinedButton(
              onPressed: command(
                'Rest pose',
                () => controller.resetPose(fadeDuration: 0.65),
              ),
              child: const Text('Reset pose'),
            ),
          ],
        ),
      ],
    );
  }

  Widget faceCommands() {
    const faceExpressions = <VrmExpression>[
      VrmExpression.happy,
      VrmExpression.sad,
      VrmExpression.angry,
      VrmExpression.relaxed,
      VrmExpression.surprised,
      VrmExpression.neutral,
      VrmExpression.blink,
      VrmExpression.blinkLeft,
      VrmExpression.blinkRight,
    ];
    return _CommandPage(
      children: [
        const _CommandSectionHeader(
          title: 'Выражения',
          description: 'Независимые layers глаз, бровей и рта.',
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final item in faceExpressions)
              FilterChip(
                selected: expression == item,
                label: Text(item.name),
                onSelected: busy
                    ? null
                    : (_) {
                        update(() => expression = item);
                        controller.setExpression(
                          item,
                          weight: expressionWeight,
                        );
                      },
              ),
          ],
        ),
        _LabeledSlider(
          label: 'Вес выражения',
          value: expressionWeight,
          min: 0,
          max: 1,
          divisions: 10,
          valueLabel: expressionWeight.toStringAsFixed(1),
          onChanged: busy
              ? null
              : (value) {
                  update(() => expressionWeight = value);
                  controller.setExpression(expression, weight: value);
                },
        ),
        OutlinedButton.icon(
          onPressed: command(
            'Выражения очищены',
            controller.clearAllExpressions,
          ),
          icon: const Icon(Icons.backspace_outlined),
          label: const Text('Очистить выражения'),
        ),
        const _CommandSectionHeader(
          title: 'Mood presets',
          description: 'Комбинация лица, физики, ветра и саккад.',
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            moodButton('Happy', VrmMood.happy),
            moodButton('Sad', VrmMood.sad),
            moodButton('Angry', VrmMood.angry),
            moodButton('Thinking', VrmMood.thinking),
            moodButton('Surprised', VrmMood.surprised),
            moodButton('Relaxed', VrmMood.relaxed),
            ActionChip(
              avatar: const Icon(Icons.clear_all, size: 18),
              label: const Text('Neutral'),
              onPressed: command('Mood сброшен', controller.clearMood),
            ),
          ],
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Автоматическое моргание'),
          value: autoBlink,
          onChanged: busy
              ? null
              : (value) {
                  update(() => autoBlink = value);
                  controller.setAutoBlink(value);
                },
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Автоматические саккады'),
          value: autoSaccades,
          onChanged: busy
              ? null
              : (value) {
                  update(() => autoSaccades = value);
                  controller.setAutoSaccades(enabled: value);
                },
        ),
      ],
    );
  }

  Widget moodButton(String label, VrmMood mood) {
    return ActionChip(
      label: Text(label),
      onPressed: command('$label mood', () => controller.setMood(mood)),
    );
  }

  Widget speechCommands() {
    return _CommandPage(
      children: [
        const _CommandSectionHeader(
          title: 'Realtime amplitude',
          description: 'Прямой вход уровня аудио без воспроизведения звука.',
        ),
        _LabeledSlider(
          label: 'Amplitude',
          value: amplitude,
          min: 0,
          max: 1,
          divisions: 20,
          valueLabel: amplitude.toStringAsFixed(2),
          onChanged: (value) {
            update(() => amplitude = value);
            controller.setLipSyncAmplitude(value);
          },
        ),
        const _CommandSectionHeader(
          title: 'Прямые viseme',
          description:
              'Последнее значение заменяет устаревшее bridge-сообщение.',
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final viseme in VrmViseme.values)
              ActionChip(
                label: Text(viseme.name.toUpperCase()),
                onPressed: busy ? null : () => controller.setViseme(viseme),
              ),
          ],
        ),
        const _CommandSectionHeader(
          title: 'Timeline demo',
          description: 'Готовые timestamped последовательности для TTS API.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: command('Viseme timeline запущен', runVisemeTimeline),
              child: const Text('Viseme timeline'),
            ),
            FilledButton.tonal(
              onPressed: command(
                'Amplitude timeline запущен',
                runAmplitudeTimeline,
              ),
              child: const Text('Amplitude timeline'),
            ),
            OutlinedButton.icon(
              onPressed: command('Speech остановлен', controller.cancelSpeech),
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Stop speech'),
            ),
          ],
        ),
      ],
    );
  }

  Widget sceneCommands() {
    return _CommandPage(
      children: [
        const _CommandSectionHeader(
          title: 'Фон и окружение',
          description: 'Цвет также подмешивается в ambient/rim lighting.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            backgroundButton('Studio', const Color(0xFF171823)),
            backgroundButton('Warm', const Color(0xFF4B2E2B)),
            backgroundButton('Forest', const Color(0xFF17372E)),
            backgroundButton('Sky', const Color(0xFF27486B)),
            ActionChip(
              avatar: const Icon(Icons.image, size: 18),
              label: const Text('SVG asset'),
              onPressed: command(
                null,
                () => setBackground(
                  'SVG asset',
                  const Color(0xFF171823),
                  asset: _AvatarDemoPageState.backgroundAsset,
                ),
              ),
            ),
            ActionChip(
              avatar: const Icon(Icons.layers_clear, size: 18),
              label: const Text('Transparent'),
              onPressed: command(
                null,
                () => setBackground(
                  'Transparent',
                  Colors.transparent,
                  transparent: true,
                ),
              ),
            ),
          ],
        ),
        const _CommandSectionHeader(
          title: 'Свет и тени',
          description: 'Готовые схемы освещения для демонстрации API.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: command('Мягкий свет', () {
                controller.setLighting(
                  ambientColor: const Color(0xFFD8D9FF),
                  ambientIntensity: 0.8,
                  directionalColor: Colors.white,
                  directionalIntensity: 1.1,
                );
              }),
              child: const Text('Soft light'),
            ),
            OutlinedButton(
              onPressed: command('Контрастный свет', () {
                controller.setLighting(
                  ambientColor: const Color(0xFF7B6FAF),
                  ambientIntensity: 0.35,
                  directionalColor: const Color(0xFFFFE0C0),
                  directionalIntensity: 2,
                );
              }),
              child: const Text('Dramatic'),
            ),
          ],
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Динамические тени'),
          value: shadows,
          onChanged: busy
              ? null
              : (value) {
                  update(() => shadows = value);
                  controller.setShadows(value);
                },
        ),
        const _CommandSectionHeader(
          title: 'Spring bones',
          description: 'Ветер и физические коэффициенты волос/одежды.',
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final wind in VrmWindType.values)
              ActionChip(
                label: Text('Wind ${wind.name}'),
                onPressed: command('Wind ${wind.name}', () {
                  controller.setWind(
                    type: wind,
                    direction: VrmWindDirection.right,
                  );
                }),
              ),
            ActionChip(
              label: const Text('Soft physics'),
              onPressed: command('Мягкая физика', () {
                controller.setPhysics(stiffness: 0.55, gravity: 0.7, drag: 1.2);
              }),
            ),
            ActionChip(
              label: const Text('Default physics'),
              onPressed: command('Физика сброшена', controller.setPhysics),
            ),
          ],
        ),
      ],
    );
  }

  Widget backgroundButton(String label, Color color) {
    return ActionChip(
      avatar: CircleAvatar(backgroundColor: color, radius: 8),
      label: Text(label),
      onPressed: command(null, () => setBackground(label, color)),
    );
  }

  Widget cameraCommands() {
    return _CommandPage(
      children: [
        const _CommandSectionHeader(
          title: 'Режим управления',
          description: 'Constrained для приложения, free для инспекции.',
        ),
        SegmentedButton<VrmCameraMode>(
          segments: const [
            ButtonSegment(
              value: VrmCameraMode.constrained,
              icon: Icon(Icons.person),
              label: Text('Constrained'),
            ),
            ButtonSegment(
              value: VrmCameraMode.free,
              icon: Icon(Icons.threed_rotation),
              label: Text('Free'),
            ),
          ],
          selected: {cameraMode},
          onSelectionChanged: busy
              ? null
              : (selection) {
                  final mode = selection.first;
                  update(() => cameraMode = mode);
                  unawaited(
                    runCommand(
                      'Camera mode: ${mode.name}',
                      () => controller.setCameraMode(mode),
                    ),
                  );
                },
        ),
        const _CommandSectionHeader(
          title: 'Pan и zoom state',
          description: 'Снимок можно сохранить и восстановить после жестов.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: command(null, saveCamera),
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Сохранить'),
            ),
            OutlinedButton.icon(
              onPressed: savedTransform == null
                  ? null
                  : command(
                      'Камера восстановлена',
                      () => controller.setTransform(savedTransform!),
                    ),
              icon: const Icon(Icons.restore),
              label: const Text('Восстановить'),
            ),
            OutlinedButton.icon(
              onPressed: command(
                'Автоматическое кадрирование',
                controller.resetCamera,
              ),
              icon: const Icon(Icons.center_focus_strong),
              label: const Text('Auto frame'),
            ),
            OutlinedButton(
              onPressed: command(null, () async {
                final transform = await controller.getTransform();
                update(() => status = transform.toString());
              }),
              child: const Text('Текущий transform'),
            ),
          ],
        ),
      ],
    );
  }

  Widget graphicsCommands() {
    return _CommandPage(
      children: [
        const _CommandSectionHeader(
          title: 'Graphics preset',
          description: 'Готовые профили производительности и качества.',
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in VrmGraphicsPreset.values)
              ChoiceChip(
                selected: graphicsPreset == preset,
                label: Text(preset.name),
                onSelected: busy
                    ? null
                    : (_) {
                        update(() => graphicsPreset = preset);
                        unawaited(
                          runCommand(
                            'Graphics: ${preset.name}',
                            () => controller.setGraphicsPreset(preset),
                          ),
                        );
                      },
              ),
          ],
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Adaptive quality'),
          subtitle: const Text('Target 55 FPS, pixel ratio 0.75–1.5'),
          value: adaptiveQuality,
          onChanged: busy
              ? null
              : (value) {
                  update(() => adaptiveQuality = value);
                  unawaited(
                    runCommand(
                      value
                          ? 'Adaptive quality включено'
                          : 'Adaptive quality выключено',
                      () => controller.setAdaptiveQuality(
                        VrmAdaptiveQualitySettings(enabled: value),
                      ),
                    ),
                  );
                },
        ),
        const _CommandSectionHeader(
          title: 'Точные настройки',
          description: 'Значения могут быть позже изменены adaptive policy.',
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final ratio in const [0.75, 1.0, 1.5])
              ActionChip(
                label: Text('$ratio×'),
                onPressed: command(
                  'Pixel ratio $ratio',
                  () => controller.setGraphicsSettings(pixelRatio: ratio),
                ),
              ),
            for (final fps in const [30, 60, 0])
              ActionChip(
                label: Text(fps == 0 ? 'VSync' : '$fps FPS'),
                onPressed: command(
                  fps == 0 ? 'FPS cap: VSync' : 'FPS cap: $fps',
                  () => controller.setGraphicsSettings(fpsCap: fps),
                ),
              ),
          ],
        ),
        const _CommandSectionHeader(
          title: 'Diagnostics',
          description: 'Актуальный snapshot renderer и host process.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: command(null, showPerformance),
              child: const Text('Performance snapshot'),
            ),
            OutlinedButton(
              onPressed: command(null, showRuntimeHealth),
              child: const Text('Runtime health'),
            ),
            OutlinedButton(
              onPressed: busy ? null : showHostResources,
              child: const Text('Host resources'),
            ),
          ],
        ),
      ],
    );
  }
}

class _CommandPanel extends StatelessWidget {
  const _CommandPanel({required this.tabs, required this.pages});

  final List<Tab> tabs;
  final List<Widget> pages;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: tabs.length,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: const Color(0xEB202130),
        child: Column(
          children: [
            Material(
              color: const Color(0xFF292A3C),
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: tabs,
              ),
            ),
            Expanded(child: TabBarView(children: pages)),
          ],
        ),
      ),
    );
  }
}

class _CommandPage extends StatelessWidget {
  const _CommandPage({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(14), children: children);
  }
}

class _CommandSectionHeader extends StatelessWidget {
  const _CommandSectionHeader({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
    this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 108, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(width: 46, child: Text(valueLabel, textAlign: TextAlign.end)),
      ],
    );
  }
}
