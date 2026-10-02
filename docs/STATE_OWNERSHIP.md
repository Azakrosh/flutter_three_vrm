# State ownership and runtime recovery

Этот документ фиксирует контракт восстановления между Flutter-приложением,
пакетом и WebView runtime. Он создан в Stage 27 и актуализирован после изоляции
runtime-сессии в Stage 34, декомпозиции controller responsibilities в Stage 35,
детерминированного teardown в Stage 37, declarative serialization в Stage 38,
lifecycle очереди в Stage 39, rebind cleanup в Stage 40, callback cleanup
в Stage 41, view lifecycle serialization в Stage 42 и declarative task
settlement в Stage 43, render lifecycle teardown в Stage 44 и controller
teardown в Stage 45, thermal lifecycle serialization в Stage 46 и terminal
content-host teardown в Stage 47 и transport settlement в Stage 48.

## Владельцы состояния

| Состояние | Desired state | Applied state | Поведение после WebView reload |
|---|---|---|---|
| Lifecycle и `renderingEnabled` | параметры `VrmView`, применяемые `VrmRuntimeSessionCoordinator` | Web runtime | Повторно синхронизируется первым шагом |
| Graphics preset и adaptive quality | последний snapshot параметров `VrmView` | Web runtime | Сериализованно применяется при rebuild и replay |
| Базовый цвет/transparent background | последний snapshot параметров `VrmView` | Web runtime | Сериализованно применяется при rebuild и replay |
| Background, заданный напрямую через controller | приложение | Web runtime | Не сохраняется; приложение повторяет команду в `onCreated` |
| `initialModelFolder`/`initialModelFile` | `VrmView` | Web runtime | Повторно загружается пакетом |
| Авторизованная/серверная модель | приложение | Web runtime | Приложение получает свежий token и загружает модель в `onCreated` |
| Camera pan/zoom | последний user-initiated transform в controller; snapshot хранит `VrmRuntimeSessionCoordinator` | Web runtime | Snapshot восстанавливается после загрузки модели, если пользователь не успел изменить камеру |
| Speech session и direct lip-sync input | текущая runtime-сессия | Web runtime | Отменяются; сервер/аудиоплеер начинает следующее сообщение как новую сессию |
| Одиночная VRMA/glTF/Pose операция | текущая runtime-сессия | Web runtime | Не replay-ится; незавершённый Future завершается ошибкой потери runtime |
| `VrmAnimationQueue` | приложение/объект очереди; subscriptions живут до async dispose | Web runtime | `runtimeUnavailable` отменяет stale transition без ошибки; очередь сохраняет позицию и запускает текущий элемент после нового `modelLoaded` |
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

Declarative graphics/background state сериализует
`VrmLatestTaskDispatcher`. Initial/recovery replay, model assessment и
`didUpdateWidget` используют одинаковые каналы. Один task выполняется, хранится
только последний pending snapshot; superseded waiters получают его outcome.
При controller rebind актуальные snapshots ставятся повторно.

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

Dispose runtime-сессии синхронно запрещает новые callbacks и возвращает
идемпотентный cleanup Future. Recovery delay отменяется без ожидания backoff;
затем session ожидает terminal state активной render lifecycle команды, а
binding дожидается отмены retired rebind, текущих controller/WebView
subscriptions, terminal completion уже запущенных callbacks и
`contentHost.close()`. Ошибка retired cancellation публикуется через
соответствующий endpoint, stale callback error подавляется identity guard, а
content host закрывается в `finally`. Его terminal close Future сначала
останавливает listener, затем ждёт все уже принятые HTTP handlers и только после
этого очищает registry временных ресурсов. Bridge detach отдельно завершает
pending protocol responses и ждёт terminal state уже начатых `runJavaScript` и
runtime reload. Binding агрегирует current и retired transport cleanup после
rebind. `VrmViewLifecycleCoordinator` сначала ждёт уже запущенную initialization,
затем terminal state активных
graphics/background задач, session cleanup и освобождает native
WebView ровно одной ветвью, включая initialization/teardown error paths.

`VrmController.dispose()` синхронно блокирует новые операции и возвращает один
terminal Future. Thermal monitor, controller state subscription и bridge
закрываются последовательно и error-safe: ошибка одной фазы не пропускает
следующие, а первая ошибка возвращается после полного cleanup.

## Lifecycle pause

Lifecycle pause останавливает только frame loop. Он не уничтожает desired state и
не является WebView reload. На Windows состояние `inactive` по platform-default
не ставит renderer на паузу; `hidden`, `paused` и `detached` ставят.
Dispose закрывает очередь lifecycle-команд и ожидает активный dispatch в общем
session cleanup Future.

Android thermal monitor хранит desired running state. Detach/rebind сериализует
subscription cancellation и restart; generation guard запрещает старому listener
менять snapshot, а текущий transition входит в controller terminal cleanup.

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
| `VrmAnimationQueue.start/pause/resume/stop/interrupt` | App object | Stale transition отменяется; active position запускается после `modelLoaded` | Queue state сохраняется | `await queue.dispose()` закрывает subscriptions/streams; новые команды дают синхронный `StateError` |

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
- `vrm_animation_queue_snapshot_test.dart` — transition race, resume после model,
  lifetime subscriptions и async dispose;
- `vrm_runtime_session_coordinator_test.dart` — generation, ordered replay, bounded
  recovery, cancelable teardown и camera snapshot;
- `vrm_runtime_controller_binding_test.dart` — rebind, tracked retired cleanup,
  in-flight callbacks, transport/content-host ownership и teardown error paths;
- `vrm_render_lifecycle_coordinator_test.dart` — Android/Windows pause policy и
  async teardown;
- `vrm_platform_thermal_monitor_test.dart` — status mapping, deduplication и
  stop/restart race;
- `vrm_controller_dispose_test.dart` — idempotent/error-safe teardown и все
  публичные controller mutations;
- `vrm_view_lifecycle_coordinator_test.dart` — initialization/cleanup ordering,
  idempotence, active task settlement и error paths.

Android `integration_test` не пересылает synthetic `WidgetTester` pointer в
native WebView PlatformView. Поэтому pointer semantics проверяются web unit-тестом
и Windows end-to-end smoke, а Android smoke покрывает lifecycle, motion, speech,
renderer recreation, reload и camera replay. Сам Android adapter передаёт
реальные жесты WebView через явный `EagerGestureRecognizer`.
