# State ownership and runtime recovery

Этот документ фиксирует контракт восстановления между Flutter-приложением,
пакетом и WebView runtime. Он создан в Stage 27 и актуализирован после изоляции
runtime-сессии в Stage 34 и декомпозиции controller responsibilities в Stage 35.

## Владельцы состояния

| Состояние | Desired state | Applied state | Поведение после WebView reload |
|---|---|---|---|
| Lifecycle и `renderingEnabled` | параметры `VrmView`, применяемые `VrmRuntimeSessionCoordinator` | Web runtime | Повторно синхронизируется первым шагом |
| Graphics preset и adaptive quality | параметры `VrmView` | Web runtime | Повторно применяются пакетом |
| Базовый цвет/transparent background | параметры `VrmView` | Web runtime | Повторно применяются пакетом |
| Background, заданный напрямую через controller | приложение | Web runtime | Не сохраняется; приложение повторяет команду в `onCreated` |
| `initialModelFolder`/`initialModelFile` | `VrmView` | Web runtime | Повторно загружается пакетом |
| Авторизованная/серверная модель | приложение | Web runtime | Приложение получает свежий token и загружает модель в `onCreated` |
| Camera pan/zoom | последний user-initiated transform в controller; snapshot хранит `VrmRuntimeSessionCoordinator` | Web runtime | Snapshot восстанавливается после загрузки модели, если пользователь не успел изменить камеру |
| Speech session и direct lip-sync input | текущая runtime-сессия | Web runtime | Отменяются; сервер/аудиоплеер начинает следующее сообщение как новую сессию |
| Одиночная VRMA/glTF/Pose операция | текущая runtime-сессия | Web runtime | Не replay-ится; незавершённый Future завершается ошибкой потери runtime |
| `VrmAnimationQueue` | приложение/объект очереди | Web runtime | `runtimeUnavailable` отменяет stale transition без ошибки; очередь сохраняет позицию и запускает текущий элемент после нового `modelLoaded` |
| Expressions, mood, wind, physics, lights | приложение | Web runtime | Неявно не сохраняются; при необходимости приложение повторяет их в `onCreated` после загрузки модели |

Transient model transfer state имеет одного внутреннего владельца:
`VrmModelDispatcher`. Он инкапсулирует `VrmModelSessionState`, generation-safe
completion, cancel и unload. Публичный `VrmController` остаётся facade и
координирует только связанные speech/camera side effects при unload.

Transient speech state также имеет одного владельца: `VrmSpeechDispatcher`.
Он инкапсулирует `VrmSpeechSessionState`, input revision, direct latest-value
channels и timeline commands. Публичный `VrmSpeechSession` хранит ссылку только
на dispatcher; replacement, runtime loss или dispose делают старый handle
неактивным без доступа к новому runtime.

Pose, face и gaze commands инкапсулированы в `VrmAvatarControlDispatcher`.
Компонент не хранит replay-состояние, но согласует захват mouth-layer с
`VrmSpeechDispatcher`: ручное mouth-expression инвалидирует активную speech
session и передаёт runtime следующую монотонную input revision. Mood остаётся
междоменной композицией публичного facade и не создаёт второго владельца state.

## Порядок replay

Каждая новая WebView-сессия получает generation token, которым владеет
`VrmRuntimeSessionCoordinator`. Старый replay прекращается после текущего
асинхронного шага и не переходит к следующему.

1. Синхронизация lifecycle/render pause.
2. Graphics preset и adaptive quality.
3. Базовый background из `VrmView`.
4. Опциональная package-owned initial model.
5. `VrmView.onCreated`: app-owned модель и model-dependent state.
6. Восстановление camera snapshot после доступности модели.

Ошибка шага останавливает оставшийся replay и публикуется через error stream.
Dispose и reload инвалидируют generation, pending bridge-команды и transient
model/speech state.

## Lifecycle pause

Lifecycle pause останавливает только frame loop. Он не уничтожает desired state и
не является WebView reload. На Windows состояние `inactive` по platform-default
не ставит renderer на паузу; `hidden`, `paused` и `detached` ставят.

## Правило для публичного API

- Declarative параметры `VrmView` принадлежат пакету и replay-ятся.
- Controller-команды по умолчанию принадлежат одной runtime-сессии.
- Состояние, зависящее от модели или authorization token, восстанавливает
  приложение в `onCreated`.
- После `VrmController.dispose` все mutating API завершаются ошибкой и replay не
  запускается.

## Матрица публичного mutating API

`Session` в таблице означает состояние только текущего WebView runtime. `App`
означает, что приложение повторяет команду из `onCreated`, когда модель нового
runtime уже загружена.

| API | Owner | WebView reload | Lifecycle pause | После dispose |
|---|---|---|---|---|
| `loadModel*`, `cancelModelLoad`, `unloadModel` | Session/App | Активная загрузка отменяется; initial asset replay-ит `VrmView`, авторизованную модель повторно загружает App | Загрузка не отменяется | `StateError` |
| `reloadRuntime` | Package | Запускает новый generation и полный ordered replay | Разрешён | `StateError` |
| `playAnimation*`, `pauseAnimation`, `resumeAnimation`, `cancelAnimationLoad`, `stopAnimation`, `setAnimationSpeed` | Session | Pending transition отменяется, direct playback не replay-ится | Состояние сохраняется, время animation mixer не продвигается до resume renderer | `StateError` |
| `setPose`, `resetPose` | Session/App | Не replay-ится | Pose сохраняется; crossfade продолжится после resume renderer | `StateError` |
| `setMood`, `clearMood`, `setExpression`, `clearExpressionLayer`, `clearAllExpressions`, `setCustomBlendShape` | Session/App | Не replay-ится | Target state сохраняется | `StateError` |
| `setLipSyncAmplitude`, `setViseme`, `enqueueSpeech*`, `beginSpeech`, `cancelSpeech` | Session | Session/realtime revision инвалидируются; следующее аудио начинает новую session | Timeline не отменяется; presentation возобновляется по real-time timestamp | `StateError` |
| `VrmSpeechSession.append*`, `finish`, `cancel` | Session handle | Старый handle становится неактивным и возвращает `false` | Остаётся активным | После controller dispose возвращает `false` |
| `setAutoSaccades`, `setAutoBlink`, `setLookAtTarget`, `setLookAtConfig` | Session/App | Не replay-ится | Конфигурация сохраняется | `StateError` |
| `setCameraMode` | Session/App | Не replay-ится | Сохраняется | `StateError` |
| `setTransform`, `resetCamera` и user pan/zoom | Package | Последний transform восстанавливается после model load, если revision не изменился | Сохраняется | `StateError` |
| `setLighting`, `setEnvironmentColor`, `setShadows`, `setPhysics`, `setWind`, `stopWind` | Session/App | Не replay-ится | Сохраняется | `StateError` |
| `setBackground*` | Session/App | Direct background не replay-ится; параметры `VrmView` replay-ятся | Сохраняется | `StateError` |
| `setRenderQuality`, `setGraphicsPreset`, `setAdaptiveQuality`, `setGraphicsSettings` | Session/App | Direct настройки не replay-ятся; declarative параметры `VrmView` replay-ятся | Сохраняются | `StateError` |
| `VrmAnimationQueue.start/pause/resume/stop/interrupt` | App object | Stale transition отменяется; active position запускается после `modelLoaded` | Queue state сохраняется | После `queue.dispose` синхронный `StateError` |

Проверки контракта распределены между:

- `vrm_runtime_replay_coordinator_test.dart` — строгий порядок, stale generation,
  camera revision и dispose;
- `vrm_model_session_state_test.dart` — replace/cancel/runtime-loss model load;
- `vrm_model_dispatcher_test.dart` — transfer payload, hosted release,
  stale replacement, cancel и unload completion;
- `vrm_speech_session_state_test.dart` — replacement, finishing и stale handles;
- `vrm_speech_dispatcher_test.dart` — direct revisions, frame ordering,
  stale handle, finishing, cancel и replacement command failure;
- `vrm_avatar_control_dispatcher_test.dart` — pose serialization, mouth
  ownership/revisions, face validation и latest-value gaze transport;
- `vrm_animation_queue_snapshot_test.dart` — transition race и resume после model;
- `vrm_runtime_session_coordinator_test.dart` — generation, ordered replay, bounded recovery и camera snapshot;
- `vrm_runtime_controller_binding_test.dart` — rebind, transport/content-host ownership и teardown;
- `vrm_render_lifecycle_coordinator_test.dart` — Android/Windows pause policy;
- `vrm_controller_dispose_test.dart` — все публичные controller mutations.

Android `integration_test` не пересылает synthetic `WidgetTester` pointer в
native WebView PlatformView. Поэтому pointer semantics проверяются web unit-тестом
и Windows end-to-end smoke, а Android smoke покрывает lifecycle, motion, speech,
renderer recreation, reload и camera replay. Сам Android adapter передаёт
реальные жесты WebView через явный `EagerGestureRecognizer`.
