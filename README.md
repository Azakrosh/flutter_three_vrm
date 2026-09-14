# flutter_three_vrm

Flutter-пакет для отображения и управления одним VRM-аватаром внутри WebView. Целевые платформы — Android и Windows.

> Версия `0.2.0-dev.1` находится в активной переработке. Обратная совместимость с `0.1.x` не гарантируется.

## Что уже поддерживается

- VRM 0.x/1.0 через `@pixiv/three-vrm`;
- VRMA-анимации и очереди анимаций;
- слои выражений, моргание, взгляд, wind и spring bones;
- amplitude lip sync и timeline визем без воспроизведения аудио;
- pan/zoom, ограниченный и свободный режим камеры, автоматическое кадрирование;
- сохранение и восстановление `VrmTransform`;
- прозрачный или цветной фон, свет, тени и настройки качества;
- загрузка из Flutter assets, локального файла или URL;
- остановка render loop при уходе приложения в фон.

Runtime собирается из зафиксированных зависимостей:

- `three 0.180.0`;
- `@pixiv/three-vrm 3.5.5`;
- `@pixiv/three-vrm-animation 3.5.5`.

`VrmCameraPreset` и `setCameraPreset()` не являются частью API. Камера управляется ограничениями, pan/zoom и сериализуемым состоянием.

## Подключение с GitHub

```yaml
dependencies:
  flutter_three_vrm:
    git:
      url: https://github.com/OWNER/flutter_three_vrm.git
      ref: <commit-or-tag>
```

Требования: Dart `>=3.12`, Flutter `>=3.44`, Android System WebView; на Windows — установленный Microsoft Edge WebView2 Runtime.

## Android

Runtime доступен WebView через случайный loopback-порт. Разрешите cleartext только для loopback, а не для всех доменов. Пример настройки находится в `example/android/app/src/main/res/xml/network_security_config.xml`.

```xml
<application
    android:networkSecurityConfig="@xml/network_security_config"
    ...>
```

Для загрузки модели с внешнего сервера приложению также нужен `android.permission.INTERNET`.

## Быстрый старт

Добавьте VRM в assets приложения:

```yaml
flutter:
  assets:
    - assets/vrm/
```

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';

class AvatarScreen extends StatefulWidget {
  const AvatarScreen({super.key});

  @override
  State<AvatarScreen> createState() => _AvatarScreenState();
}

class _AvatarScreenState extends State<AvatarScreen> {
  final VrmController controller = VrmController();

  @override
  void dispose() {
    unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VrmView(
      controller: controller,
      transparent: true,
      onCreated: (controller) async {
        await controller.loadModel('assets/vrm/', 'avatar.vrm');
      },
    );
  }
}
```

Вызывайте методы загрузки только после `onCreated`.

## Runtime health и восстановление

`onCreated` вызывается только после инициализации command protocol; callback может возвращать `Future`, и `VrmView` дождётся его завершения. Для внешней orchestration доступен отдельный readiness API:

```dart
await controller.waitUntilReady();
final health = await controller.getRuntimeHealth();

debugPrint(
  'runtime=${health.runtimeVersion}, '
  'three=r${health.threeRevision}, '
  'WebGL ${health.webGlVersion}, '
  'maxTexture=${health.maxTextureSize}',
);
```

`VrmRuntimeHealth` также сообщает версии protocol/three-vrm, наличие модели и анимации, pause render loop и потерю WebGL context. Это предназначено для диагностики и integration smoke-тестов, а не для доступа к низкоуровневому renderer.

При ошибке главного документа `VrmView` выполняет не более двух попыток восстановления с exponential backoff. Ошибки текстур и других дочерних ресурсов не перезапускают весь runtime. Политику можно изменить или отключить:

```dart
VrmView(
  controller: controller,
  recoveryPolicy: const VrmRuntimeRecoveryPolicy(
    enabled: true,
    maxAttempts: 3,
    baseDelay: Duration(milliseconds: 500),
    maxDelay: Duration(seconds: 4),
  ),
  onCreated: (controller) async {
    // Вызывается снова после успешного восстановления runtime.
    await controller.loadModelFromFile(await obtainAuthenticatedModel());
  },
);
```

Для ручного восстановления вызовите `await controller.reloadRuntime()`, а затем `await controller.waitUntilReady()`. Незавершённые команды завершаются ошибкой сразу при начале reload и не остаются ждать timeout.

## Камера

```dart
controller.setCameraMode(VrmCameraMode.constrained);

final saved = await controller.getTransform();
await controller.setTransform(saved);
```

`VrmTransform` содержит `x`, `y` и `zoom` и подходит для хранения в настройках приложения.

## Анимации и выражения

```dart
await controller.playAnimation(
  'assets/vrma/',
  'idle.vrma',
  loop: true,
  fadeDuration: 0.35,
);

controller.setExpression(
  VrmExpression.happy,
  layer: ExpressionLayer.eyes,
  weight: 0.8,
);
```

### Очередь и восстановление

`VrmAnimationQueue` сохраняет точный порядок воспроизведения, текущий индекс, состояние паузы и активный interrupt:

```dart
final queue = VrmAnimationQueue(
  controller: controller,
  folderPath: 'assets/vrma/',
  fileNames: const ['idle_01.vrma', 'idle_02.vrma'],
  random: true,
);

queue.onError.listen((event) {
  debugPrint('${event.operation}: ${event.error}');
});

final json = queue.snapshot().toJson();

// После восстановления состояния приложения:
queue.restore(
  VrmAnimationQueueSnapshot.fromJson(json),
  resumePlayback: true,
);
```

Если runtime или WebView был создан заново, очередь автоматически перезапустит текущую анимацию после следующего `onModelLoaded`. Саму модель следует повторно загрузить в `VrmView.onCreated`: для authenticated API это позволяет Flutter-клиенту безопасно обновить токен и не заставляет пакет удерживать большие byte buffers в памяти.

Обычный переход приложения в background не перезапускает очередь: render loop приостанавливается и продолжает работу с того же места после `resumed`.

## Pose API

Pose API работает с нормализованным humanoid-скелетом three-vrm. Позу можно получить, сохранить, применить к совместимому VRM-аватару или сбросить:

```dart
final pose = await controller.getPose();
await controller.setPose(
  VrmPose({
    VrmHumanBone.head: const VrmPoseTransform(
      rotation: VrmQuaternion(0, 0.15, 0, 0.9887),
    ),
  }),
);
await controller.resetPose();
```

По умолчанию `setPose()` и `resetPose()` останавливают текущую анимацию, иначе AnimationMixer перезапишет те же кости на следующем кадре.

## GLB/glTF и Mixamo

VRMA обрабатывается `@pixiv/three-vrm-animation`. Обычные humanoid-анимации из GLB/glTF автоматически ретаргетятся на normalized bones VRM. Ретаргетер поддерживает Mixamo-названия костей, namespace-варианты, rest-pose rotation, масштаб hips и VRM 0 handedness.

```dart
await controller.playAnimationFromFile(
  File('/app/cache/talking.glb'),
  clipName: 'Talking',
  rootMotion: VrmRootMotion.inPlace,
  fadeDuration: 0.3,
);
```

`VrmRootMotion.inPlace` фиксирует горизонтальное перемещение hips, но сохраняет вертикальную составляющую. Для движения по сцене используйте `VrmRootMotion.full`.

GLB и self-contained glTF передаются одним файлом. Если `.gltf` ссылается на внешние `.bin` или текстуры, передайте явный защищённый bundle:

```dart
await controller.playAnimationFromBytesBundle(
  {
    'animation.gltf': gltfBytes,
    'buffers/motion.bin': motionBytes,
  },
  entryFileName: 'animation.gltf',
);
```

Bundle доступен только внутри текущей loopback-сессии, не раскрывает файловые пути или API-токены и освобождается целиком после парсинга.
## Отмена загрузки и диагностика

Повторный `loadModel*()` автоматически отменяет предыдущую незавершённую загрузку, сохраняя текущий аватар до успешного парсинга нового. Загрузку также можно отменить явно:

```dart
final loading = controller.loadModelFromFile(modelFile);
await controller.cancelModelLoad();
try {
  await loading;
} on VrmRuntimeException catch (error) {
  if (error.code != 'canceled') rethrow;
}

await controller.cancelAnimationLoad();
```

После `onModelLoaded` runtime публикует `onModelReport`. Тот же отчёт доступен по запросу через `getModelReport()` и содержит размер исходника, высоту, количество мешей, вершин, треугольников, материалов, текстур, morph targets и костей. Значения являются диагностикой, а не искусственными ограничениями на модель.
## Производительность Android

По умолчанию `VrmView` использует balanced-профиль, ограничение 60 FPS и адаптирует pixel ratio в диапазоне 0.75–1.5. Политика реагирует только на устойчивое изменение частоты кадров и использует cooldown между переключениями.

```dart
VrmView(
  controller: controller,
  graphicsPreset: VrmGraphicsPreset.balanced,
  adaptiveQuality: const VrmAdaptiveQualitySettings(
    targetFps: 55,
    minPixelRatio: 0.75,
    maxPixelRatio: 1.5,
  ),
);

controller.onPerformance.listen((event) {
  final stats = event.snapshot;
  debugPrint('${stats.fps} FPS, ${stats.triangles} triangles');
});

controller.onModelAssessment.listen((event) {
  final assessment = event.assessment;
  debugPrint(
    '${assessment.complexity.name}: '
    '${assessment.warnings.map((warning) => warning.metric.name).join(', ')}',
  );
});
```

Доступны профили `performance` (30 FPS, pixel ratio 1.0), `balanced` и `quality`. `setGraphicsSettings()` оставлен для точного ручного управления. Автоматическая политика изменяет только render resolution и не отключает spring-bone physics без решения приложения.

`VrmModelPerformancePolicy` дополнительно анализирует размер файла, полигоны, количество и суммарную площадь текстур, morph targets и spring bones. Она не запрещает загрузку моделей. По умолчанию модель получает класс `standard`, `elevated` или `high`; для двух последних классов верхняя граница adaptive pixel ratio заранее снижается до 1.25 или 1.0. Все пороги и оба значения можно переопределить:

```dart
VrmView(
  controller: controller,
  modelPerformancePolicy: const VrmModelPerformancePolicy(
    autoTunePixelRatio: true,
    elevatedMaxPixelRatio: 1.25,
    highMaxPixelRatio: 1,
  ),
);
```

Чтобы получать только предупреждения без автоматической настройки, установите `autoTunePixelRatio: false`. При выключенном `VrmAdaptiveQualitySettings.enabled` политика также не меняет render resolution.

При потере WebGL-контекста runtime приостанавливает обновление сцены, а после восстановления повторно компилирует материалы и продолжает render loop. Состояние доступно через `onWebGlContextChanged`.
## Lip sync

Аудио воспроизводит Flutter-приложение. Пакет получает только амплитуду или временную шкалу визем:

```dart
controller.setLipSyncAmplitude(0.65);
controller.beginSpeech(startDelay: const Duration(milliseconds: 180));
controller.appendSpeechVisemes(frames);
controller.finishSpeech(audioDuration);
```

Для потокового TTS передавайте небольшие порции timeline заранее. Авторизационные токены сервера нельзя передавать в JavaScript/WebView; защищённую загрузку следует выполнять Flutter-клиентом, а затем вызывать `loadModelFromFile()` (предпочтительно для больших файлов) или `loadModelFromBytes()`.

## Сборка web-runtime

```bash
cd web
corepack pnpm install --frozen-lockfile
corepack pnpm typecheck
corepack pnpm test
corepack pnpm build
```

Собранные `assets/web/dist/vrm-engine.js` и `manifest.json` входят в репозиторий и проверяются CI.

## Статус roadmap

До стабильного релиза запланированы интеграционные smoke-тесты на физических Android/Windows устройствах.

Android runtime smoke-тест находится в `example/integration_test/runtime_smoke_test.dart` и проверяет initialization, health payload, загрузку модели и ручное восстановление:

```bash
cd example
flutter test integration_test/runtime_smoke_test.dart -d <android-device-id>
```

## Лицензия

MIT
