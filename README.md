# flutter_three-vrm

Кроссплатформенный пакет для Flutter (Android и Windows), предназначенный для загрузки и управления VRM 1.0 моделями и VRMA анимациями. Пакет служит базовым движком для создания AI Vtuber приложений.

## Возможности

- 🚀 **VRM 1.0 & VRMA**: Полная поддержка спецификации VRM 1.0 и стандарта анимаций `.vrma` на базе Three.js и `@pixiv/three-vrm`.
- 📁 **Раздельная загрузка из Assets**: Простой синтаксис `controller.loadModel('assets/vrm/', 'avatar.vrm');`.
- 🔄 **Управление памятью**: Методы `loadModel()`, `unloadModel()`, `disposeModel()`, а также пауза рендеринга при сворачивании приложения.
- 👁️ **Многослойные эмоции (Multi-Layer Expressions)**: 3 независимых слоя мимики (глаза, рот, брови), исключающие конфликт между анимациями эмоций и синхронизацией речи.
- 🗣️ **Lip Sync & ElevenLabs**: Потоковое сглаженное управление открытием рта по громкости речи (`0.0`–`1.0`) + поддержка визем ElevenLabs (`AA`, `IH`, `OU`, `EE`, `OH`).
- 🔄 **Авторазворот и тапы (Auto-Turnback)**: При развороте модели спиной к пользователю она автоматически поворачивается обратно лицом через 3.5 секунды.
- 📷 **Камера Редактора Персонажей**: Ограничение вращения по оси Y, фиксированный зум и готовые пресеты (`FullBody`, `UpperBody`, `FaceCloseUp`).
- 🎨 **Прозрачный WebGL Canvas**: Прозрачный фон для наложения модели на любые виджеты Flutter.

## Установка

Добавьте пакет в ваш `pubspec.yaml`:

```yaml
dependencies:
  flutter_three_vrm:
    path: ../flutter_three-vrm
  webview_flutter: ^4.14.1
  webview_flutter_windows: ^1.1.1
  path: ^1.9.1
```

## Быстрый старт

```dart
import 'package:flutter/material.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';

class VtuberView extends StatefulWidget {
  @override
  State<VtuberView> createState() => _VtuberViewState();
}

class _VtuberViewState extends State<VtuberView> {
  final VrmController _controller = VrmController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: VrmView(
        controller: _controller,
        transparent: true,
        onCreated: (controller) {
          // Загрузка модели из assets
          controller.loadModel('assets/vrm/', 'avatar.vrm');
        },
      ),
    );
  }
}
```

### Основные методы VrmController

#### Загрузка и жизненный цикл
```dart
await controller.loadModel('assets/vrm/', 'avatar.vrm');
await controller.unloadModel();
controller.disposeModel();
```

#### Анимации (VRMA)
```dart
await controller.playAnimation('assets/vrma/', 'dance.vrma', loop: true, interrupt: true);
await controller.pauseAnimation();
await controller.resumeAnimation();
```

#### Эмоции и слои
```dart
controller.setExpression(VrmExpression.happy, layer: ExpressionLayer.eyes);
controller.setExpression(VrmExpression.sad, layer: ExpressionLayer.brows);
```

#### Синхронизация речи (Lip Sync)
```dart
// В реальном времени по громкости аудиопотока (0.0 - 1.0)
controller.setLipSyncAmplitude(0.8);

// Виземы ElevenLabs
controller.setViseme(VrmViseme.aa);
```

#### Камера
```dart
controller.setCameraPreset(VrmCameraPreset.faceCloseUp);
controller.setCameraPreset(VrmCameraPreset.fullBody);
```

## Лицензия

MIT License
