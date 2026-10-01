# Public API semantics

Этот документ фиксирует поведение публичного API `0.2.x`. Практические детали
replay и полный список владельцев состояния находятся в
[`STATE_OWNERSHIP.md`](STATE_OWNERSHIP.md), а release gates — в
[`TEST_MATRIX.md`](TEST_MATRIX.md).

## Runtime и владение

- Один `VrmController` управляет одним активным `VrmView` и одним аватаром.
- Команды разрешены после `VrmView.onCreated` или `waitUntilReady()`.
- `onCreated` вызывается при каждой новой runtime-сессии, в том числе после
  recovery/reload. Здесь приложение повторно загружает авторизованную модель и
  принадлежащее ему model-dependent состояние.
- `VrmView` владеет WebView surface. Внутренний runtime-session owner владеет
  transport, controller/WebView subscriptions и loopback content host. Приложение
  владеет controller, своими subscriptions, animation queue и speech handles.
- После `VrmController.dispose()` новые mutating-команды завершаются
  `StateError`. Каждый `VrmAnimationQueue` тоже необходимо `dispose()`.
- Быстрые изменения `VrmView.graphicsPreset`, adaptive policy и базового
  background сериализуются по каналам: промежуточное ожидающее состояние может
  быть пропущено, но последним применяется самое новое значение.

## Команды и ошибки

| Тип вызова | Завершение | Ошибка |
|---|---|---|
| `Future`-команда | После подтверждения runtime | Ошибка возвращается через Future |
| Realtime setter (`setViseme`, `setLipSyncAmplitude`, `setLookAtTarget`) | Fire-and-forget с latest-value backpressure | Валидация бросает ошибку синхронно; transport/runtime error публикуется в `onError` |
| Событие controller | Broadcast stream | Подпиской владеет приложение |

Некорректные аргументы отклоняются во Flutter до отправки в WebView. Обычно это
`ArgumentError`; повреждённый ответ runtime даёт `FormatException`. Отсутствие
готового/прикреплённого runtime, reload или dispose дают `StateError`. Команда,
не ответившая за transport timeout, завершается `TimeoutException`.

Получение response с известным correlation ID всегда является terminal:
повреждённый envelope немедленно завершает ожидающий Future с
`FormatException`, а не ждёт повторного timeout. Ожидаемый поздний response
после timeout, detach/reload или ошибки dispatch игнорируется. Malformed
сообщение без известной pending-команды публикуется в `onError`.

Ошибка, возвращённая самим web runtime, представлена `VrmRuntimeException`.
Для управления потоком приложение может стабильно распознавать
`code == 'canceled'`: так завершаются заменённые или явно отменённые загрузки.
Остальные коды и `message` следует логировать, но не использовать как бизнес-
состояние. `onError` не заменяет обработку Future: он предназначен прежде всего
для фоновых fire-and-forget операций.

```dart
try {
  await controller.loadModelFromFile(file);
} on VrmRuntimeException catch (error) {
  if (error.code != 'canceled') rethrow;
}
```

## Загрузка ресурсов

Повторный `loadModel*()` отменяет незавершённую предыдущую загрузку. Побеждает
последний запрос; уже отображаемый аватар остаётся в сцене до успешного parse и
атомарной замены. `cancelModelLoad()` отменяет transfer/parse, а Future исходной
загрузки завершается с `canceled`.

Authorization headers и токены остаются во Flutter. Для защищённого API Flutter
клиент скачивает файл и передаёт его через `loadModelFromFile()` или
`loadModelFromBytes()`. `loadModelFromUrl()` предназначен для URL, доступного
самому WebView. Для больших моделей предпочтителен файл, чтобы не удерживать
полную копию в Dart heap.

```dart
onCreated: (controller) async {
  final file = await avatarApi.downloadToCache();
  await controller.loadModelFromFile(file);
},
```

External-resource glTF передаётся только явным bundle. Все относительные URI из
entrypoint должны присутствовать в map; весь bundle освобождается после parse.

```dart
await controller.playAnimationFromBytesBundle(
  {
    'talk.gltf': gltfBytes,
    'buffers/talk.bin': motionBytes,
  },
  entryFileName: 'talk.gltf',
  clipName: 'Talking',
);
```

## Motion

VRMA, ретаргетированный GLB/glTF и `VrmPose` используют один motion mixer.
Любая смена источника выполняет crossfade с заданным `fadeDuration`: VRMA →
Pose, Pose → Pose, Pose → VRMA, `resetPose()` и `stopAnimation()`. Значение `0`
означает намеренный мгновенный переход.

```dart
final playback = await controller.playAnimation(
  'assets/vrma/',
  'idle.vrma',
  fadeDuration: 0.35,
);
await controller.setPose(pose, fadeDuration: 0.5);
```

`VrmAnimationPlayback.id` связывает команду с `onAnimationStarted` и
`onAnimationFinished`. Одиночный playback принадлежит текущей runtime-сессии и
не replay-ится после reload. `VrmAnimationQueue` сохраняет позицию и повторно
запускает текущий элемент после следующего `onModelLoaded`.

## Realtime speech

Пакет не воспроизводит аудио. Flutter-плеер и `beginSpeech()` запускаются
одновременно; timeline привязана к реальному времени. Пауза и seek намеренно не
поддерживаются. Допустима только полная остановка `cancelSpeech()` до следующего
аудиосообщения.

```dart
final speechFuture = controller.beginSpeech(mode: VrmSpeechMode.viseme);
final audioFuture = audioPlayer.play(source);
final speech = await speechFuture;
await audioFuture;

await speech.appendVisemes(frames);
await speech.finish(audioDuration);

// Единственная операция остановки текущего сообщения.
await Future.wait([audioPlayer.stop(), controller.cancelSpeech()]);
```

Одна session принимает либо viseme, либо amplitude frames. Новая session
заменяет старую. Методы stale handle возвращают `false`, поэтому callbacks
предыдущего сообщения не могут изменить текущую речь. Reload инвалидирует
session; следующее сообщение начинает новую.

## Камера и interaction

`constrained` предоставляет avatar-safe pan/zoom, `free` — orbit/pan/zoom.
`getTransform()`/`setTransform()` сохраняют pan и zoom. Последний
user-initiated или явно заданный transform восстанавливается после reload, если
пользователь не успел изменить камеру в новой runtime-сессии.

```dart
await controller.setCameraMode(VrmCameraMode.constrained);
final saved = await controller.getTransform();
await controller.setTransform(saved);
await controller.resetCamera();
```

В режиме `free` orbit pivot вычисляется по humanoid-костям туловища
(`hips` и `upperChest/chest`). Pan хранится отдельно как смещение кадра,
поэтому после перемещения камеры вращение продолжает выполняться вокруг
туловища, а не вокруг руки или предыдущей точки pan.

Клик/касание публикует `onTap`, но не поворачивает голову, корпус или глаза.
Pan/zoom жесты управляют камерой. Явный `setLookAtTarget()` относится только к
направлению глаз и использует latest-value backpressure.

## Scene, face и performance

```dart
controller
  ..setMood(VrmMood.happy)
  ..setLighting(ambientIntensity: 1.1, directionalIntensity: 1.1)
  ..setWind(type: VrmWindType.light);

await controller.setBackgroundFromBytes(
  imageBytes,
  fileName: 'room.webp',
  color: const Color(0xFF171823),
);
await controller.setGraphicsPreset(VrmGraphicsPreset.performance);
```

Mood/expressions, lighting, physics, wind и direct background принадлежат
текущей runtime-сессии. Если они нужны после reload, приложение повторяет их в
`onCreated`. Declarative параметры `VrmView`, graphics/adaptive configuration,
initial asset model и camera snapshot replay-ятся пакетом.

`onPerformance`, `onModelAssessment`, `getModelReport()` и
`getRuntimeHealth()` являются высокоуровневой диагностикой. Они не открывают
renderer и не вводят жёсткие лимиты на полигоны, текстуры или размер файла.

`VrmPerformanceSnapshot` объясняет steady-state нагрузку, а не только сообщает
FPS. `longFrameCount`, `longestFrameMs` и `longFrameThresholdMs` описывают
длинные интервалы текущего окна. `updateTimeP95Ms` измеряет CPU-обновление
аватара, `renderTimeP95Ms` — синхронную часть вызова renderer. Поле
`longFrameSource` принимает `runtimeUpdate`, `renderSubmission` или
`externalScheduling`. Последнее объединяет задержки браузерного scheduler,
compositor, GPU и ОС: runtime не выдаёт эту категорию за точный GPU-профиль.

`adaptiveDecision` вместе с target FPS, slow/fast counters и оставшимся cooldown
объясняет, почему pixel ratio был изменён или оставлен прежним. Operational
model/animation operations сбрасывают окно и в эти счётчики не попадают.

### Ресурсы процесса хоста

`captureHostResourceSnapshot()` синхронно возвращает RSS Flutter-процесса,
его high-water mark, число полученных low-memory сигналов и доступный thermal
status. RSS не является памятью только VRM и может не включать отдельный Android
WebView renderer process и GPU allocations. Его точный состав зависит от
операционной системы, поэтому метрика предназначена для сравнения одинаковых
soak-прогонов, а не для жёсткого ограничения модели.

`onHostMemoryPressure` публикуется после системного callback Flutter. Событие
само по себе не выгружает модель, не останавливает анимацию и не меняет graphics
preset. Приложение может журналировать его и самостоятельно выбрать продуктовую
реакцию. На Android API 29+ thermal status поступает из `PowerManager`; Windows и
более старый Android возвращают `VrmThermalStatus.unavailable`. Это означает
отсутствие достоверного сигнала, а не нормальную температуру.

## Lifecycle и recovery

Lifecycle pause останавливает WebGL frame loop, но не Flutter-аудио, AI API или
чат. `platformDefault` приостанавливает Android при потере фокуса; видимый
Windows WebView2 продолжает работать в `inactive`. `hidden`, `paused` и
`detached` приостанавливают обе платформы.

`reloadRuntime()` сразу завершает pending session-команды ошибкой, создаёт новую
generation и выполняет ordered replay. Приложение может слушать
`onRuntimeUnavailable`, но новую работу начинает только после следующего
`onCreated`/`waitUntilReady()`.

```dart
await controller.reloadRuntime();
await controller.waitUntilReady();
final health = await controller.getRuntimeHealth();
```
