# flutter_three_vrm

Flutter-пакет для отображения и управления одним VRM-аватаром внутри WebView. Целевые платформы — Android и Windows.

> Версия `0.2.0-dev.1` находится в активной переработке. Обратная совместимость с `0.1.x` не гарантируется.

## Что уже поддерживается

- VRM 0.x/1.0 через `@pixiv/three-vrm`;
- VRMA-анимации и очереди анимаций;
- слои выражений, моргание, взгляд, wind и spring bones;
- realtime amplitude, amplitude timeline и timeline визем без воспроизведения аудио;
- pan/zoom, ограниченный и свободный режим камеры, автоматическое кадрирование;
- сохранение и восстановление `VrmTransform`;
- прозрачный или цветной фон, свет, тени и настройки качества;
- загрузка из Flutter assets, локального файла или URL;
- платформо-зависимое управление render loop: экономия ресурсов Android без зависания видимого окна Windows.

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

Управление render loop зависит от платформы. С политикой `platformDefault` Android ставит renderer на паузу при потере фокуса, а Windows продолжает рендеринг видимого окна в состоянии `inactive`. Это позволяет аватару работать при переключении фокуса между Flutter и WebView2 или другим окном. Скрытое, свёрнутое, paused или detached приложение приостанавливает renderer на обеих платформах.

```dart
VrmView(
  controller: controller,
  renderingEnabled: true,
  lifecyclePolicy: VrmRenderLifecyclePolicy.platformDefault,
)
```

`pauseWhenHidden` сохраняет рендеринг любого видимого окна, а `pauseWhenUnfocused` включает строгую паузу при потере фокуса. Для явной паузы перестройте `VrmView` с `renderingEnabled: false`. Lifecycle управляет только WebGL render loop и не останавливает Flutter-аудио, AI API, чат или bridge. Выбранное состояние автоматически восстанавливается после reload runtime.

## Фон сцены

Цвет, прозрачность и публичный URL задаются через `setBackground()`. Метод возвращает `Future`: после его завершения asset уже скопирован в Blob внутри WebView, а временный loopback URL освобождён.

```dart
await controller.setBackground(
  color: const Color(0xFF171823),
  imageAssetPath: 'assets/images/avatar_room.jpg',
);

await controller.setBackgroundFromFile(
  cachedBackgroundFile,
  color: const Color(0xFF171823),
);

await controller.setBackgroundFromBytes(
  authenticatedImageBytes,
  fileName: 'avatar-room.webp',
  color: const Color(0xFF171823),
);
```

Для защищённого API загружайте изображение Flutter-клиентом с авторизацией и передавайте файл или байты. `imageUrl` предназначен для публичного URL и не получает Flutter-токены. Новая команда отменяет незавершённую предыдущую загрузку; старый фон сохраняется до успешной подготовки нового. Blob URL отзывается при смене фона и уничтожении runtime.

## Камера

```dart
await controller.setCameraMode(VrmCameraMode.constrained);

final saved = await controller.getTransform();
await controller.setTransform(saved);
await controller.resetCamera(); // Повторное автоматическое кадрирование.
```

`VrmTransform` содержит `x`, `y` и `zoom` и подходит для хранения в настройках приложения.
Пользовательские pan/zoom и состояние, явно заданное через `setTransform()`,
автоматически восстанавливаются после reload runtime. Обычное автокадрирование
новой модели не считается пользовательским состоянием и не переопределяется.
`VrmCameraMode.free` включает полноценные orbit rotate/pan/zoom, тогда как
`constrained` оставляет фронтальный avatar-safe pan/zoom с ограниченной дистанцией.

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

Числовые параметры управления проверяются синхронно на стороне Flutter:
скорость должна быть положительной, длительности и коэффициенты физики —
неотрицательными, а веса выражений и нормализованные интенсивности должны
находиться в диапазоне 0–1. Некорректная команда не отправляется в WebView.
`VrmView` также проверяет adaptive-quality, recovery и model-performance
конфигурации при создании и обновлении. Эти гарантии работают в release-сборке
и не зависят от включённых Dart assertions.

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

Каждый вызов playAnimation возвращает объект VrmAnimationPlayback с opaque ID.
Тот же playbackId присутствует в событиях запуска и завершения.
VrmAnimationQueue использует его автоматически и не реагирует на прямые
анимации или Pose-команды, запущенные другими частями приложения.

Если runtime или WebView был создан заново, очередь автоматически перезапустит текущую анимацию после следующего `onModelLoaded`. Саму модель следует повторно загрузить в `VrmView.onCreated`: для authenticated API это позволяет Flutter-клиенту безопасно обновить токен и не заставляет пакет удерживать большие byte buffers в памяти.

Обычный переход приложения в background не перезапускает очередь: render loop приостанавливается и продолжает работу с того же места после `resumed`.

## Pose API

Pose API работает с нормализованным humanoid-скелетом three-vrm. Позу можно получить, сохранить, применить к совместимому VRM-аватару или сбросить:

```dart
final pose = await controller.getPose();
await controller.setPose(
  VrmPose({
    VrmHumanBone.head: VrmPoseTransform(
      rotation: VrmQuaternion.fromEulerDegrees(4, 0, 0),
    ),
  }),
  fadeDuration: 0.6,
);
await controller.resetPose(fadeDuration: 0.6);
```

Pose и VRMA/glTF-анимации выполняются одним `AnimationMixer`. Поэтому переходы VRMA → Pose, Pose → Pose, Pose → VRMA, `resetPose()` и `stopAnimation()` используют crossfade и не проходят скачком через rest pose. Две адаптированные тестовые позы `presenterOpenPose` и `loungePose` находятся в `example/lib/sample_poses.dart`.

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
final speechFuture = controller.beginSpeech();
final audioStart = audioPlayer.play(audioSource);
final speech = await speechFuture;
await audioStart;

await speech.appendVisemes(frames);
await speech.finish(audioDuration);

// Альтернатива для timestamped amplitude от сервера:
final amplitudeSpeech = await controller.beginSpeech(
  mode: VrmSpeechMode.amplitude,
);
await amplitudeSpeech.appendAmplitudes(amplitudeFrames);
await amplitudeSpeech.finish(audioDuration);

// Если вся timeline уже известна:
await controller.enqueueSpeechAmplitudes(amplitudeFrames);

// Единственная операция транспорта во время воспроизведения — полный stop:
await Future.wait([audioPlayer.stop(), controller.cancelSpeech()]);
```

Сохраняйте возвращённый `VrmSpeechSession` рядом с конкретным аудиосообщением
AI-сервера и используйте его во всех callbacks этого сообщения. После запуска
следующей речи операции старого handle возвращают `false` и не могут изменить
актуальную timeline. `VrmSpeechSession.cancel()` также останавливает речь
только тогда, когда этот handle всё ещё активен.

Для потокового TTS передавайте небольшие порции timeline заранее. Вызов `beginSpeech()`
и запуск аудиоплеера выполняйте одновременно: timeline привязана к моменту вызова
Flutter, а задержка доставки команды в WebView компенсируется автоматически. Пауза
и перемотка намеренно не поддерживаются. Новая speech-сессия заменяет предыдущую,
а пакеты со старым session ID игнорируются.

Viseme и amplitude нельзя смешивать внутри одной сессии. `duration` каждого кадра
ограничивает время его действия: если следующая порция сервера задержалась, рот
автоматически вернётся в нейтральное состояние вместо зависания.

Авторизационные токены сервера нельзя передавать в JavaScript/WebView; защищённую загрузку следует выполнять Flutter-клиентом, а затем вызывать `loadModelFromFile()` (предпочтительно для больших файлов) или `loadModelFromBytes()`.

`setLipSyncAmplitude()`, прямой `setViseme()` и `setLookAtTarget()` используют
latest-value backpressure: в WebView одновременно отправляется не более одного
значения каждого типа, а накопившиеся устаревшие samples заменяются самым новым.
`beginSpeech()` и методы `VrmSpeechSession.appendVisemes()`,
`appendAmplitudes()`, `finish()` и `cancel()` используют упорядоченную
session-safe timeline.

## Сборка web-runtime

```bash
cd web
corepack pnpm install --frozen-lockfile
corepack pnpm typecheck
corepack pnpm test
corepack pnpm verify:contract
corepack pnpm build
corepack pnpm verify:build
```

Собранные `assets/web/dist/vrm-runtime.js` и `manifest.json` входят в репозиторий и проверяются CI. Полные уведомления о лицензиях встроенных библиотек и example-assets находятся в [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). CI также проверяет checksum и право на перераспространение sample-модели, чтобы в публичный пакет случайно не попал avatar с `allowRedistribution: false`.

## Статус roadmap

Канонический план, аудит текущей архитектуры и следующие этапы находятся в
[`docs/ROADMAP.md`](docs/ROADMAP.md).

Расширенный runtime smoke-тест пройден на физическом Android 16 устройстве и в Windows WebView2. Windows lifecycle дополнительно проверен вручную: клики внутри и вне окна, pan/zoom, сворачивание и восстановление не останавливают анимацию видимого аватара.

Runtime smoke-тест находится в `example/integration_test/runtime_smoke_test.dart` и проверяет initialization, health payload, загрузку и выгрузку модели, перенос asset-фона в WebView Blob, lifecycle pause/resume, пересоздание renderer, повторные reload, восстановление камеры и явный dispose `VrmView`:

```bash
cd example
flutter test integration_test/runtime_smoke_test.dart -d <android-device-id>
```

## Лицензия

MIT
