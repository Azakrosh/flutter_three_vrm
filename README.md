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
```

Доступны профили `performance` (30 FPS, pixel ratio 1.0), `balanced` и `quality`. `setGraphicsSettings()` оставлен для точного ручного управления. Автоматическая политика изменяет только render resolution и не отключает spring-bone physics без решения приложения.

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

До стабильного релиза запланированы: cancellation для долгих загрузок, валидация и диагностический отчёт по модели, восстановление очереди после смены приложения, а также интеграционные smoke-тесты на физических Android/Windows устройствах.

## Лицензия

MIT