# План рефакторинга и развития flutter_three_vrm

Статус: активный рабочий документ
Дата аудита: 2026-10-03
Проверенная база: `b89a894 fix: type expected runtime transition cancellation`
Целевые платформы: Android и Windows; приоритет — Android

## 1. Откуда восстановлен первоначальный план

Отдельного файла с первоначальным планом в репозитории не было. Первый
восстанавливаемый вариант находится в `README.md` коммита `07579bc Stage 1.`:

> До стабильного релиза запланированы: типизированный command/response bridge
> с timeout/cancel, authenticated resource client, GLB/glTF и
> Mixamo-retargeting, полный Pose API, adaptive quality tiers, диагностика
> WebGL и интеграционные тесты Android/Windows.

Последующие решения из рабочего обсуждения расширили этот план:

- полная переработка без обязательной совместимости с `0.1.x`;
- один активный аватар;
- загрузка защищённых моделей и анимаций выполняется Flutter-приложением с его
  авторизацией, а WebView получает временный локальный ресурс без credentials;
- VRM 0.x/1.0, VRMA, GLB/glTF, Mixamo-retargeting и Pose API;
- плавная смена любых источников движения: VRMA, glTF и Pose;
- Flutter воспроизводит звук, пакет получает realtime amplitude/viseme timeline;
- аудио нельзя ставить на паузу или перематывать: только проигрывание и полная
  остановка текущего сообщения;
- pan/zoom, ограничения, автоматическое кадрирование и восстановление камеры;
- ограничения сложности модели носят рекомендательный характер; жёстко
  блокируются только некорректные или заведомо опасные данные;
- публичный низкоуровневый API renderer не предоставляется;
- Windows не должен останавливать видимый аватар из-за простой потери фокуса,
  Android должен экономить ресурсы;
- публикация пакета отложена;
- текущие стабильные версии Three.js/three-vrm пока сохраняются.
- касания и клики не управляют головой, корпусом или взглядом аватара;
  `onTap` остаётся информационным событием, pan/zoom сохраняются.

Этот документ является каноническим продолжением плана. Если исторический
первичный текст будет найден вне Git, его нужно добавить в раздел источников,
не переписывая уже зафиксированные решения молча.

## 2. Выполненные этапы

| Этап | Результат | Статус |
| --- | --- | --- |
| 1 | Android/Windows adapters, pnpm/esbuild runtime, bridge, защищённый loopback host, authenticated handoff, удаление camera presets | Выполнено |
| 2 | Pose API, GLB/glTF и Mixamo-retargeting, resource bundles, мобильные FPS/pixel-ratio defaults | Выполнено |
| 3 | Graphics presets, adaptive resolution, telemetry, WebGL recovery, новый example | Выполнено |
| 4–5 | Race-safe загрузка, model report и рекомендательная оценка сложности | Выполнено |
| 6 | Сериализуемая очередь анимаций, recovery и typed error stream | Выполнено |
| 7 | Readiness, runtime health, manual reload и bounded recovery | Выполнено |
| 8–9 | Восстановление камеры, free/constrained controls и строгий `VrmTransform` | Выполнено |
| 10 | Backpressure для realtime amplitude/viseme/LookAt | Выполнено |
| 11–12 | Освобождение VRM/WebGL ресурсов и детерминированный teardown | Выполнено |
| 13 | Платформенная lifecycle-политика Android/Windows | Выполнено |
| 14 | Race-safe background API и освобождение Blob/loopback ресурсов | Выполнено |
| 15 | Лицензированные example-assets, checksums и third-party notices | Выполнено |
| 16 | Единый воспроизводимый runtime bundle и проверяемый manifest | Выполнено |
| 17–19 | В Git нет отдельных этапов с такими номерами | Не восстанавливать догадками |
| 20 | Общий mixer/crossfade для VRMA, glTF и Pose | Выполнено |
| 21–22 | Realtime speech timeline и типизированные speech sessions | Выполнено |
| 23–24 | Release-safe валидация команд и конфигурации | Выполнено |
| 25 | Playback identity и изоляция очереди от посторонних анимаций | Выполнено |
| 26 | Полный TypeScript runtime, строгие command/event codecs и protocol v3 | Выполнено |
| 27 | State ownership, ordered replay и recovery contract | Выполнено |
| 28 | Android performance telemetry и физический low-end Firebase gate | Выполнено |
| 29 | Изолированные integration gates и документация API semantics | Выполнено |
| 30 | Подготовка публикации | Отложено |
| 31 | Android performance observability и управление нагрузкой по фазам | Выполнено |
| 32 | Memory-pressure resilience и точность host diagnostics | Выполнено |
| 33 | Воспроизводимые Firebase performance gates и evidence artifacts | Выполнено |
| 34 | Изоляция runtime-сессии от Flutter-представления | Выполнено |
| 35 | Внутренняя декомпозиция `VrmController` | Выполнено |
| 36 | Terminal semantics и диагностика transport bridge | Выполнено |
| 37 | Детерминированный async teardown runtime-сессии | Выполнено |
| 38 | Сериализация declarative graphics/background configuration | Выполнено |
| 39 | Детерминированный lifecycle `VrmAnimationQueue` | Выполнено |
| 40 | Детерминированная очистка controller rebind | Выполнено |
| 41 | Terminal cleanup запущенных runtime binding callbacks | Выполнено |
| 42 | Сериализация initialization/teardown `VrmView` | Выполнено |
| 43 | Terminal settlement declarative-задач `VrmView` | Выполнено |
| 44 | Детерминированный teardown render lifecycle | Выполнено |
| 45 | Идемпотентный и error-safe teardown `VrmController` | Выполнено |
| 46 | Сериализация lifecycle Android thermal monitor | Выполнено |
| 47 | Детерминированный teardown loopback content host | Выполнено |
| 48 | Terminal settlement transport dispatch bridge | Выполнено |
| 49 | Унифицированный lifecycle платформенных WebView-адаптеров | Выполнено |
| 50 | Terminal settlement операций `VrmAnimationQueue` | Выполнено |
| 51 | Error-safe teardown subscriptions runtime binding | Выполнено |
| 52 | Наблюдаемый asynchronous teardown `VrmView` | Выполнено |
| 53 | Единая диагностика declarative-задач `VrmView` | Выполнено |

## 3. Состояние реализации

### Архитектура

```text
Flutter application
  └─ VrmView                         Flutter widget и привязка WebView
      ├─ latest configuration queues  graphics/background serialization
      ├─ VrmRuntimeSessionCoordinator lifecycle, replay, recovery, camera snapshot
      │   └─ VrmRuntimeControllerBinding subscriptions, transport, content-host lifetime
      │       └─ content host        session loopback, opaque resources
      ├─ VrmController               публичный высокоуровневый facade
      │   ├─ VrmBridge               protocol v3, terminal responses, timeout, events
      │   ├─ hosted resources        expose, dispatch, guaranteed release
      │   ├─ animation dispatcher    validation, playback identity, commands
      │   ├─ model dispatcher        transfer generation, cancel, unload
      │   ├─ speech dispatcher       session identity, revisions, timelines
      │   ├─ scene dispatcher        lighting, physics, wind, backgrounds
      │   ├─ graphics dispatcher     renderer settings, performance query
      │   └─ avatar dispatcher       pose, expressions, gaze, speech handoff
      └─ platform adapter
           ├─ Android WebView
           └─ Windows WebView2

WebView runtime
  └─ main.ts / protocol.ts
      └─ runner.ts           типизированный facade и порядок обновления кадра
          ├─ motion-transition.ts
          ├─ motion-controller.ts
          ├─ animation-loader.ts
          ├─ camera-controller.ts
          ├─ scene-controller.ts
          ├─ background-controller.ts
          ├─ graphics-controller.ts
          ├─ humanoid-animation.ts
          ├─ pose.ts
          ├─ speech-timeline.ts
          ├─ speech-controller.ts
          ├─ face-controller.ts
          ├─ gaze-controller.ts
          ├─ wind-physics-controller.ts
          ├─ pointer-controller.ts
          ├─ frame-scheduler.ts
          ├─ page-lifecycle.ts
          └─ performance.ts
```

### Что уже соответствует production-направлению

- публичный API остаётся высокоуровневым и не раскрывает Three.js;
- credentials не передаются в WebView;
- локальный host использует случайный порт, opaque IDs и проверку Host;
- command/response envelope имеет версию, correlation ID, ошибки и timeout;
- модель сохраняется до успешной подготовки её замены;
- загрузки, background transfer и runtime recovery защищены от stale completion;
- VRM-ресурсы, DOM listeners, animation frames и WebGL context освобождаются;
- camera, lifecycle и animation queue имеют определённую recovery-семантику;
- motion и speech операции получают собственную identity;
- Android и Windows проверены runtime smoke-тестом;
- runtime собирается из закреплённых зависимостей и проверяется checksum;
- модель не отклоняется по произвольному лимиту полигонов или текстур:
  диагностика и adaptive policy носят рекомендательный характер.

### Текущий размер и покрытие

- Flutter library: 51 файл, примерно 7370 строк;
- web source: 35 файлов, примерно 6860 строк;
- `runner.ts`: примерно 675 строк;
- `VrmController`: примерно 910 строк;
- Flutter unit tests: 149;
- web unit tests: 167;
- integration matrix разделена на runtime/scene, motion/speech,
  lifecycle/recovery, model-race, resource-loading и performance soak gates.

Числа нужны как ориентир концентрации ответственности, а не как целевые KPI.

## 4. Оставшиеся архитектурные риски

### Закрытые архитектурные риски

- весь web runtime входит в строгий `tsc --noEmit`;
- все command/event payload и query results имеют boundary codecs, а `unknown`
  остаётся только на входе недоверенного JSON и в error details;
- protocol v3, Dart serializers и TypeScript dispatcher сверяются contract
  tests;
- state ownership, replay order и recovery semantics зафиксированы в
  `docs/STATE_OWNERSHIP.md` и проверены recovery/race tests;
- integration matrix разделена на независимые gates и запускается общей
  командой для Android/Windows;
- физический low-end Android подтверждён Firebase Test Lab gate.

### Закрыто в Stage 31.1 — измерения разных фаз нагрузки

Исторический soak-профиль включал parsing, GPU upload и disposal модели в то же
окно, что steady-state rendering. Это давало полезный worst-case, но не позволяло
отличить длинный операционный stall от устойчивой деградации FPS и могло
ошибочно влиять на adaptive quality. Первый срез Stage 31 отделяет load/unload
окна, сбрасывает frame timing после model/animation operations и сохраняет
steady-state профиль отдельно. Физический gate на moto g55 подтвердил, что
многосекундный ложный percentile исчез, а устойчивый профиль сохранился.

### Закрыто в Stage 31 — host memory и thermal diagnostics

Публичный высокоуровневый snapshot теперь показывает current/max RSS,
количество Android memory-pressure callbacks и thermal status. Эти сигналы
дополняют renderer counters и расчётную память текстур, не меняют модель
автоматически и имеют безопасный fallback вне поддерживаемого Android API.

### Закрыто в Stage 31 — сопоставимый multi-device low-end профиль

Одна ARM64 сборка прошла полный Firebase gate на Galaxy A03s и Motorola moto g
5G (2022), оба Android 13 и 720×1600. Сравнение обнаружило и закрыло burst в
FPS limiter на 90-Гц cadence. Тройные повторения остаются pre-release gate, но
второй производитель и одинаковая сборка теперь проверены.

### Закрыто в Stage 35 — крупный публичный controller

`VrmController` сохранён единым публичным facade, но resource/model/animation,
speech, scene/graphics и avatar-control обязанности вынесены во внутренние
компоненты с явными границами владения. В controller осталась междоменная
координация, публичные события, runtime lifetime и camera recovery.

### Закрыто в Stage 36 — незавершённые malformed bridge responses

Любой response с известным correlation ID теперь является terminal: success,
runtime error и повреждённый envelope немедленно завершают соответствующий
Future. Timeout, detach, reload и dispatch failure сохраняют bounded-набор ID,
чтобы ожидаемый поздний response не создавал ложную диагностику. Некоррелируемый
malformed input публикуется в `onError`, а не теряется только в debug log.

### Закрыто в Stage 39 — недетерминированный lifecycle animation queue

`stop()`, естественное завершение и восстановление stopped snapshot больше не
запускают fire-and-forget отмену event subscriptions. Подписки принадлежат всему
lifetime очереди, поэтому быстрый `stop → start` не создаёт перекрывающиеся
listeners. Идемпотентный `Future<void> dispose()` сначала дожидается отмены всех
входящих подписок и только затем закрывает публичные event streams.

### Закрыто в Stage 40 — fire-and-forget очистка controller rebind

Старые controller subscriptions после `rebind` немедленно теряют право на
callbacks через identity guard, а их асинхронная отмена теперь сохраняется в
tracked cleanup Future. Session dispose дожидается всех retired и текущих
subscriptions. Ошибка retired cleanup публикуется через прежний endpoint;
`contentHost.close()` выполняется в `finally` даже при ошибке текущей отмены.

### Закрыто в Stage 41 — callback, переживающий binding teardown

Binding хранит набор только активных async callbacks и удаляет каждый
Future после terminal completion. `dispose()` захватывает текущий набор и ждёт
его вместе с retired/current subscriptions до закрытия content host. Callback
старого endpoint может корректно завершиться, но его поздняя ошибка подавляется
identity/disposed guard и не попадает новому controller.

### Закрыто в Stage 42 — конкурирующие initialization и WebView disposal

`VrmViewLifecycleCoordinator` владеет initialization Future и одним terminal
cleanup Future. Widget синхронно помечает session disposed, но native cleanup
начинается только после завершения уже запущенной initialization. Ветка
initialization больше не вызывает `WebView.dispose()` самостоятельно, поэтому
adapter освобождается ровно одним владельцем даже при раннем удалении widget.

### Закрыто в Stage 43 — declarative-задачи вне terminal teardown

После `close()` graphics/background dispatchers отклоняют queued и future work, а
их `idle` Futures входят в lifecycle settlement до native cleanup. Session
teardown синхронно отсоединяет transport и завершает активные bridge-команды,
после чего WebView освобождается только по достижении terminal state обеими
очередями. Cleanup всё равно выполняется при ошибке предыдущей lifecycle-фазы.

### Закрыто в Stage 44 — render lifecycle dispatch вне session teardown

`VrmRenderLifecycleCoordinator.dispose()` закрывает latest-value dispatcher и
возвращает один идемпотентный Future его `idle`. Runtime session включает этот
Future в общий cleanup barrier вместе с binding и recovery. Активная
pause/resume-команда теперь достигает terminal state до session и native WebView
cleanup, а её stale error после close не публикуется приложению.

### Закрыто в Stage 45 — преждевременный и частичный controller teardown

`VrmController.dispose()` синхронно запрещает новые операции и сохраняет один
terminal Future для всех повторных вызовов. Внутренний cleanup runner выполняет
thermal stop, отмену state subscription и bridge dispose независимо от ошибок
предыдущих фаз, после чего повторно выбрасывает первую ошибку с исходным stack
trace. Bridge cleanup больше не пропускается при ошибке platform/subscription.

### Закрыто в Stage 46 — конкурирующие thermal stop и restart

Android thermal monitor теперь хранит desired running state и сериализует
subscription transitions. `start()` во время незавершённого `stop()` не создаёт
параллельного listener: новая generation открывается после cancellation старой.
События старой generation игнорируются, поздний stop не сбрасывает новый status,
а controller dispose получает актуальный terminal Future monitor.

### Закрыто в Stage 47 — HTTP handlers вне terminal content-host teardown

`LocalAssetsServer.close()` теперь синхронно запрещает новую работу и возвращает
один cleanup Future. Listener отслеживает каждый принятый request handler;
закрытие listener принудительно завершает клиентские соединения, ожидает
terminal state обработчиков и только затем очищает opaque resources. Проверка
`Host` использует локальный порт уже принятого соединения и не зависит от
публичного started-state закрывающегося host.

### Закрыто в Stage 48 — native transport operations вне binding teardown

`VrmBridge` отдельно отслеживает protocol response и terminal Future вызова
native transport. `detachTransport()` немедленно запрещает новые команды owner,
но завершается только после уже начатых `runJavaScript` и runtime reload.
Binding агрегирует current и retired transport cleanup, поэтому native WebView
не уничтожается во время старой dispatch-операции после controller rebind.
Bridge dispose теперь идемпотентен и выполняет event-stream cleanup даже после
ошибки transport settlement.

### Закрыто в Stage 49 — различающийся lifecycle platform adapters

Android и Windows adapters используют общий `VrmWebViewAdapterLifecycle`.
Initialization, active load/script operations и dispose имеют единую terminal
границу; начало dispose синхронно запрещает новую работу. Cleanup ждёт
initialization и уже принятые операции, выполняет все platform-фазы и сохраняет
первую ошибку. Windows native controller освобождается ровно один раз, Android
закрывает оба event stream независимо от ошибки соседней фазы.

### Закрыто в Stage 50 — queue callbacks вне terminal dispose

`VrmAnimationQueue` теперь отслеживает terminal Futures уже принятых playback и
control operations. Dispose синхронно запрещает новые команды, инвалидирует
generation, запускает cancellation всех subscriptions и ожидает операции до
закрытия state/error streams. Cleanup выполняется по error-safe фазам и сохраняет
первую ошибку, не пропуская закрытие остальных ресурсов.

### Закрыто в Stage 51 — частичный teardown runtime binding

`VrmRuntimeControllerBinding` создаёт защищённый Future для cancellation каждой
controller/WebView subscription, поэтому синхронная ошибка не прерывает обход.
Current/retired transport cleanup, callback settlement и detachment объединены в
terminal settlement; content host закрывается отдельной error-safe фазой с
сохранением первой ошибки. Та же cancellation-гарантия действует при rebind.

### Закрыто в Stage 52 — необработанная ошибка teardown VrmView

Terminal Future, который запускает синхронный `State.dispose()`, теперь имеет
явный observer. Ошибка с исходным stack trace передаётся в
`FlutterError.reportError` с контекстом пакета и не дублируется как unhandled Zone
error. Session и native WebView cleanup выполняются error-safe; первая ошибка
поднимается только после попытки завершить обе фазы.

### Закрыто в Stage 53 — разная диагностика declarative-задач VrmView

Graphics и background configuration Futures теперь проходят через общий
`observeVrmViewConfigurationTask`. Policy проверяет актуальность controller в
момент ошибки, подавляет ожидаемый `VrmRuntimeException(code: 'canceled')`,
сохраняет stack trace и направляет активный сбой в bridge diagnostics. Только
ошибка graphics дополнительно становится user-visible session error.

### Закрыто в Stage 54 — ложная диагностика ожидаемого runtime transition

Reload/recovery теперь инвалидирует pending-команды общей типизированной причиной
`VrmRuntimeException(code: 'canceled')`. Awaited-команда возвращает эту ошибку
вызывающему коду, а центральный diagnostic sink bridge подавляет её для фоновых
и latest-value команд. Остальные runtime, transport, timeout и malformed-response
ошибки по-прежнему публикуются с исходным stack trace.

### P2 — публикационная готовность отложена

В `pubspec.yaml` установлен `publish_to: none`. Это соответствует принятому
решению. Проверки package metadata, generated API docs и release checklist не
являются текущим блокером и не должны отвлекать от стабилизации runtime.

## 5. Текущее направление

Stage 54 завершён и зафиксирован коммитом `b89a894`: runtime reload/recovery
завершает pending-команды типизированным `VrmRuntimeException(code: 'canceled')`,
а bridge централизованно исключает эту ожидаемую отмену из async diagnostics.
Проходят 169 Flutter-тестов и `flutter analyze`; Windows runtime-race,
runtime/recovery и runtime smoke gates прошли без ложного сообщения
`Asynchronous VRM command failed`.

Stage 55 завершён: ownership и terminal outcomes проверены на границах
`VrmView` → session coordinator → binding → bridge → adapter, а API, ownership
и test-matrix документы синхронизированы с реализацией. Новых воспроизводимых
архитектурных рисков не обнаружено. `flutter analyze`, все 169 Flutter-тестов и
полная Windows integration matrix из пяти gates прошли 2026-10-03.

Следующий этап не назначен. Архитектура считается стабилизированной; дальнейшая
работа должна начинаться с продуктового требования, измеримого performance-
сигнала или воспроизводимого дефекта. Публикация и обновление
Three.js/three-vrm по-прежнему отложены.

Сейчас не следует:

- обновлять Three.js/three-vrm без отдельной причины;
- добавлять новые эффекты или ещё один способ управления моделью;
- начинать публикацию;
- менять protocol v3 только ради рефакторинга;
- одновременно менять motion или speech semantics.

## 6. Следующие этапы

### Stage 26 — contract tests и TypeScript migration

Цель: сделать весь выполняемый web runtime частью строгой типизации, сохранив
protocol v3. Исключение в поведении по решению пользователя: клик больше не
поворачивает аватар и не меняет взгляд.

Статус: завершён. Добавлен общий manifest protocol v3, Dart bridge принимает
только enum-команды, TypeScript проверяет command/event имена и обязательные
поля payload, а CI сверяет manifest с TypeScript dispatcher. Browser transport,
глобальные callbacks, response/error envelopes и platform message sinks уже
вынесены из runner в строгий TypeScript. Все 49 command routes также вынесены
в исчерпывающий TypeScript dispatcher с коррелированными action/payload union.
Общая потоковая загрузка ресурсов для model, animation и background вынесена
в типизированный модуль. Model loading, cancellation races, invalid-container
cleanup и model report также вынесены в TypeScript. Ownership активной
VRM-сессии, mixer, motion transitions, spring bones и scene disposal перенесён
в отдельный TypeScript-модуль. Camera modes, automatic framing, constrained
pan, animated reset, serialized transform и восстановление OrbitControls после
пересоздания renderer перенесены в типизированный camera controller. Scene,
renderer, OrbitControls, lighting, shadows, WebGL context listeners и
детерминированный disposal теперь принадлежат отдельному TypeScript scene
controller; renderer recreation сохраняет применённое состояние и откатывается
без разрушения текущего renderer при ошибке. FPS cap, graphics presets,
physics switch, adaptive quality и performance telemetry теперь принадлежат
типизированному graphics controller; первый кадр после смены FPS cap или resume
не обходит ограничение частоты. Speech timeline, session begin/append/finish/
cancel, viseme presentation, amplitude smoothing и завершение речевого
сообщения теперь принадлежат типизированному speech controller. Слои мимики,
crossfade выражений, direct viseme, custom blend shapes и моргание вынесены
в типизированный face controller с unit-тестами. Оркестрация VRMA/glTF-клипов,
Pose, rest transition, pause/resume и fallback события завершения теперь
принадлежит типизированному motion controller. Загрузка VRMA/glTF, отмена
устаревших запросов и очистка разобранной сцены вынесены в типизированный
animation loader; замена модели отменяет незавершённую загрузку анимации.
Передача фонового ресурса, CSS-представление и жизненный цикл Blob URL теперь
принадлежат типизированному background controller. Программный взгляд и
автоматические саккады вынесены в типизированный gaze controller. Удалены
поворот головы и корпуса по клику, связанные raycast и восстановление костей
каждый кадр; pan/zoom и `onTap` остаются. Регрессия проверена Windows/Android
smoke-тестом сравнением позы головы и груди. Множители spring-bone и
покадровое моделирование ветра вынесены в типизированный wind/physics
controller; настройка физических параметров больше не теряется при временно
выключенной симуляции. Обработка primary pointer, tap/drag/cancel и привязка
listeners к заменяемому canvas вынесены в типизированный pointer controller.
Поведение проверено Windows/Android smoke-тестом, включая renderer recreation.
Планирование кадров, пауза/возобновление и сброс времени после WebGL recovery
теперь принадлежат типизированному frame scheduler; поздние callbacks после
pause/dispose игнорируются.
Подписки на page resize/pagehide и последовательность cleanup теперь принадлежат
типизированному page lifecycle controller; повторный dispose безопасен, а ошибка
одного cleanup-шага не блокирует последующие. В Stage 26.20 оставшийся facade
перенесён из `runner.js` в `runner.ts`, явно реализует `RuntimeCommandHost`
и входит в строгую TypeScript-проверку. Следующий срез — точные codecs для
оставшихся `RuntimeRecord`/`unknown` payload и result. В Stage 26.21
streaming speech получил точные типы mode/viseme/amplitude frames и отдельный
boundary codec: вложенные frames, диапазоны, timestamps, revision и optional
поля отклоняются до dispatcher; небезопасные casts между facade и speech
controller удалены. В Stage 26.22 Pose, camera transform и
graphics/adaptive settings переведены
на точные command payload и query-result типы. Их доменные parsers теперь
повторно используются на protocol boundary, поэтому неизвестные кости, неверные
quaternion/transform, режимы камеры и renderer-настройки отклоняются до
dispatcher. Dart codecs также запрещают нечисловые Pose-компоненты, нулевой
quaternion и дробные целочисленные поля performance telemetry. В Stage 26.23
animation options и lighting получили точные payload-типы и
общие domain/boundary parsers. Команды с полностью optional payload больше не
обходят вложенные codecs из-за раннего возврата общего валидатора. Runtime
health и model report добавлены в typed query-result map; Dart строго проверяет
целочисленные capability/diagnostic поля, обязательные строки и диапазоны.
В Stage 26.24 expression/gaze/physics/wind/background получили точные
payload-типы и единый boundary codec с проверкой enum-значений, диапазонов и
условно обязательных полей. Имя runtime-события теперь связано с payload через
generic event map на всём пути runner -> protocol -> platform transport;
model-report и performance events проверяются на полноту перед отправкой.
Дополнительно `sil` в speech timeline закрывает рот как пауза, не создавая
несуществующую VRM expression. В Stage 26.25 все 11 команд без аргументов
получили точный empty-object контракт и отклоняют неожиданные поля на runtime
boundary. Результат dispatcher теперь вычисляется из имени команды: query
возвращают свои доменные типы, а mutation-команды — только `null`; success и
response envelope больше не хранят `unknown`. В Stage 26.26 все event payload
получили доменную проверку диапазонов, enum-состояний и empty-object событий на
web boundary. Dart bridge использует отдельный тестируемый decoder для всех 14
событий и больше не подменяет отсутствующие name/progress/camera/tap/expression
значения fallback-данными. Оставшийся `unknown` ограничен недоверенным JSON,
error details и функциями безопасного сужения типов. Все критерии Stage 26
закрыты; дальнейшая работа переходит к Stage 27 — state ownership и recovery.

Работы:

1. Зафиксировать каталог всех command/event, payload и result.
2. Добавить contract tests для Dart serializers/parsers и web dispatcher.
3. Перевести `runner.js` в TypeScript без функциональных изменений. Выполнено
   в Stage 26.20.
4. Заменить произвольные строки команд внутренними constants/discriminated
   unions и типизированными codecs.
5. Разделить runner минимум на model loading, scene/camera, motion,
   face/speech, performance и resource lifecycle.
6. Оставить один facade, который принимает protocol-команды и координирует
   модули.
7. Сохранить CI triggers для `main` и `master` до окончательного выбора
   основной ветки.

Критерии готовности:

- весь исходный web runtime входит в `tsc --noEmit`;
- command/event payload проверяются на runtime boundary;
- неизвестные или некорректные payload дают стабильный protocol error;
- generated bundle и protocol version не меняются без необходимости;
- Flutter/web unit tests и Windows/Android smoke проходят;
- поведение example не меняется, кроме явно согласованного удаления поворота
  аватара и взгляда по клику.

### Stage 27 — единая модель state ownership и recovery — завершён

Цель: формально определить, какое состояние сохраняет пакет, runtime или
приложение.

Работы:

- составить таблицу desired/applied state и порядок replay;
- централизовать восстановление graphics, background, camera, lifecycle и
  model-dependent state;
- явно отменять speech/motion operations, которые нельзя корректно продолжить;
- сохранить app-owned reload модели для обновления authorization token;
- добавить тесты recovery во время model load, animation transition и speech.

Критерий готовности: для каждого публичного mutating API документировано и
проверено поведение после WebView reload, lifecycle pause и dispose.

Текущий прогресс: добавлен `docs/STATE_OWNERSHIP.md`; generation и строгий порядок
replay lifecycle → graphics → background → package model → app state → camera
принадлежат `VrmRuntimeReplayCoordinator`. Camera snapshot также перенесён в
координатор, а потеря runtime теперь явно инвалидирует незавершённую загрузку
модели и speech/direct-input состояние. `VrmAnimationQueue` получает отдельный
package-side `runtimeUnavailable`, отменяет stale transition без ложной ошибки и
возобновляет сохранённую позицию после нового `modelLoaded`. Следующий срез —
полная mutating API matrix. Model load state вынесен в `VrmModelSessionState`:
replacement/cancel/runtime-loss защищены generation token и отдельными
race-тестами. Speech identity, finishing и revision принадлежат
`VrmSpeechSessionState`; runtime-loss делает старые session handles и realtime
input revision недействительными. Полная mutating API matrix зафиксирована в
`docs/STATE_OWNERSHIP.md`; dispose-контракт проверяет все controller mutations,
а replay coordinator отклоняет нарушенный порядок или повторение фаз. Windows
и physical Android 16 прошли полный recovery smoke. Synthetic pointer Android
PlatformView не поддерживается `WidgetTester`, поэтому этот путь разделён на web
unit coverage и Windows end-to-end; реальные Android gestures явно передаются
WebView через `EagerGestureRecognizer`. Все критерии Stage 27 закрыты;
дальнейшая работа переходит к Stage 28.

### Stage 28 — Android performance и длительная стабильность

Статус: выполнено.

Цель: предсказуемая нагрузка на смартфон без произвольного запрета тяжёлых
моделей.

Работы:

- добавить frame-time percentiles и причины изменения adaptive quality;
- проверить FPS cap, pixel ratio и recovery на слабом физическом Android;
- провести циклы load/unload/reload и длительный speech/motion soak;
- фиксировать context loss, память текстур и время загрузки в diagnostics;
- оставить model complexity policy рекомендательной и настраиваемой.

Текущий прогресс: telemetry snapshot получил frame-time p50/p95 из фиксированного
буфера без покадровых аллокаций. Причина события и изменения adaptive pixel ratio
типизирована единым enum на TypeScript/Dart boundary. Embedded runtime пересобран
и contract остаётся на protocol v3. Runtime health дополнен текущим количеством
renderer-текстур, расчётной памятью текстур модели, временем последней успешной
загрузки и накопительным context-loss counter за жизнь WebView. Добавлен
конфигурируемый `performance_soak_test.dart`: на физическом moto g55 5G быстрый
профиль держит renderer textures на 28/0 во всех load/unload циклах, pixel ratio
1.0 и не теряет WebGL context во время streaming speech и VRMA/Pose-переходов.
Процедура и первый профиль зафиксированы в `docs/PERFORMANCE_TESTING.md`.
Пятиминутный gate с десятью циклами также пройден: 158 telemetry samples,
средние 29.6 FPS при cap 30, p95 не выше 60.0 ms, texture baseline 28/0 и ноль
context loss. Второй gate пройден 25 сентября 2026 года в Firebase Test Lab на
физическом low-end Samsung Galaxy A03s (`a03su`), Android 13/API 33 и Android
System WebView 106.0.5249.126. Полный прогон длительностью 300 секунд с десятью
load/unload циклами завершился со средними 30.1 FPS, стабильными textures 28/0,
pixel ratio 1.0, нулём context loss и без накопительного роста ресурсов.
Matrix `matrix-1mjgm2x82h693` и подробная телеметрия зафиксированы в
`docs/FIREBASE_TEST_LAB.md`. Повторные облачные прогоны остаются pre-release
regression gate, а первичная low-end валидация Stage 28 выполнена.

Критерий готовности: документированный профиль нагрузки и отсутствие
неограниченного роста ресурсов в длительных сценариях.

### Stage 29 — тестовая матрица и документация API

Статус: выполнено.

Цель: превратить существующие гарантии в повторяемые release gates.

Работы:

- разбить монолитный smoke-тест на независимые сценарии;
- добавить race tests для replacement/cancel/reload;
- добавить authenticated bytes и external-resource glTF integration cases;
- документировать ошибки, ownership, transition и speech semantics;
- добавить минимальные примеры для каждого высокоуровневого блока API.

Текущий прогресс: монолитный `runtime_smoke_test.dart` разделён на независимые
runtime/scene, motion/speech и lifecycle/recovery gates с общим harness. Добавлен
четвёртый gate для replacement/cancel/reload races. Он обнаружил и закрыл гонку
transport boundary: быстрый error-response мог завершить внутренний Completer до
возврата Future вызывающему коду. Все четыре сценария отдельно прошли на
physical Android 16 и Windows WebView2. Web model-loader дополнительно проверяет
правило newest-request-wins, даже когда старый fetch игнорирует AbortSignal.
`resource_loading_test.dart` на обеих платформах проверяет authenticated VRM
bytes и генерируемый external-resource glTF byte bundle без нового стороннего
asset. В `tool/run_integration_matrix.ps1` добавлена единая команда для всех
platform gates и Android soak. Каноническая матрица находится в
`docs/TEST_MATRIX.md`. Семантика ошибок, ownership, motion transitions и
realtime speech, а также минимальные рецепты всех высокоуровневых блоков
зафиксированы в `docs/API_SEMANTICS.md`. Release-gate срез зафиксирован коммитом
`b8f4d8b`.

### Stage 30 — подготовка публикации

Статус: отложено до отдельного решения.

Включает GitHub metadata, package metadata, API docs, versioning policy,
release checklist, clean-clone verification и окончательный аудит лицензий.

### Stage 31 — Android performance observability и управление нагрузкой

Статус: выполнено.

Цель: получать объяснимый профиль нагрузки на Android и не принимать решения
adaptive quality по паузам загрузки/выгрузки модели.

Работы:

1. Разделить load/unload и steady-state render telemetry без изменения
   protocol v3 и публичного API.
2. Сбрасывать frame timing после model/animation parsing, GPU upload и disposal,
   чтобы операционный stall не считался устойчивой частотой кадров.
3. Добавить фазовые строки soak-отчёта и применять FPS assertions только к
   steady-state samples.
4. Исследовать Android memory-pressure и thermal signals, определить безопасный
   высокоуровневый diagnostics contract.
5. Добавить причины длинных кадров и adaptive-quality transitions в диагностике.
6. Повторить полный gate на Galaxy A03s и втором low-end устройстве другого
   производителя; сохранить сопоставимые профили одной сборки.

Текущий прогресс: runtime начинает новое timing window после успешной загрузки
модели, выгрузки модели и загрузки/ретаргетинга анимации. Soak harness отдельно
собирает `runtime_soak_load` и `runtime_soak_steady`; средний FPS и frame-time
steady-state больше не загрязняются десятью подготовительными load/unload
циклами. Protocol v3 не изменён. Регрессия покрыта web unit
test; 167 web tests, TypeScript typecheck, Flutter analyze и 86 Flutter tests
проходят. Короткий physical gate на moto g55 5G также пройден: load-фаза дала
p50/p95 не выше 34.0/69.3 ms, steady-фаза — средние 29.3 FPS и p50/p95 не выше
34.1/39.8 ms при cap 30; многосекундный ложный frame-time исчез, textures
остались стабильны 28/0. Первый срез подтверждён. Второй срез добавил независимый
от protocol v3 host-diagnostics контракт: `captureHostResourceSnapshot()`
измеряет current/max RSS процесса, `onHostMemoryPressure` считает системные
low-memory callbacks, а soak-отчёт печатает строку `runtime_soak_host`. Событие
является наблюдаемым и не выгружает модель автоматически. Третий срез добавил
нативный Android `PowerManager` bridge: API 29+ публикует текущий status и его
изменения, Windows/старый Android используют `unavailable`, listener снимается
при detach от `VrmView` и Flutter engine. Финальный короткий physical soak на
moto g55 подтвердил `thermal=none`, `memoryPressure=0`, loaded host RSS
465.5/469.9/467.3/466.2 MiB, unloaded RSS 442.2/458.3/454.4/460.8 MiB, max RSS
481.4 MiB и прежние стабильные renderer textures 28/0. Flutter suite: 93 теста;
Android и Windows debug builds собираются. Четвёртый срез добавляет причины
длинных кадров и adaptive-quality transitions напрямую в
`VrmPerformanceSnapshot`: long-frame threshold/count/max, p95 CPU update и
render submission, осторожную классификацию `externalScheduling`, а также
adaptive target, slow/fast counters, cooldown и решение политики. Operational
reset по-прежнему очищает все эти окна. Physical soak на moto g55 обнаружил 2
long frames из 267 (максимум 63.7 ms): update p95 6.0 ms и render submission p95
8.5 ms не объясняют задержку, поэтому source корректно классифицирован как
`externalScheduling`. Adaptive decisions были `stable/collectingFast`, pixel
ratio остался 1.0. Финальный срез выполнен 27 сентября 2026 года на одной ARM64
сборке в Firebase Test Lab: Galaxy A03s и Motorola moto g 5G (2022), Android 13,
720×1600. Первый Motorola gate обнаружил ошибку limiter: ранний кадр в
tolerance-окне сохранял старую временную базу и разрешал следующий vsync,
из-за чего среднее достигало 37.1 FPS при cap 30. После исправления и отдельного
90-Гц regression test оба полных gate прошли; среднее — 30.1 FPS на обоих
устройствах, textures стабильно возвращаются 28/0, context loss и runtime errors
отсутствуют. A03s адаптивно менял pixel ratio 0.85–1.0 и получил 602 long frames
из 3664 с source `externalScheduling`; Motorola сохранил ratio 1.0 и не
зарегистрировал long frames. Motorola показал bounded, но высокий host-memory
plateau: sampled RSS до 664.5 MiB и 6 memory-pressure callbacks без монотонного
роста между десятью циклами. Подробные matrix IDs, SHA и фазовые строки сохранены
в `docs/FIREBASE_TEST_LAB.md`. 171 web test, TypeScript typecheck,
protocol/build verification, Flutter analyze и 93 Flutter test проходят. Все
критерии Stage 31 закрыты.

Критерии готовности:

- load/unload pauses не влияют на steady-state FPS и adaptive-quality windows;
- отчёт отдельно показывает operational stalls и устойчивый rendering profile;
- причины adaptive transitions и длинных кадров диагностируемы;
- memory/thermal policy основана на доступных Android signals и имеет
  platform-safe fallback;
- повторные low-end gates не показывают накопительного роста ресурсов.

### Stage 32 — memory-pressure resilience и точность host diagnostics

Статус: выполнено.

Цель: отличать нормальный прогрев Android/WebView от утечки и безопасно
переживать системное давление памяти без произвольных лимитов модели.

Работы:

1. Проверить семантику `ProcessInfo.maxRss` на разных Android-производителях:
   A03s вернул значение ниже ранее измеренного current RSS, поэтому этот сигнал
   нельзя считать межплатформенным peak без дополнительной нормализации.
2. Добавить в soak отчёт sampled current-RSS peak и slope после warm-up,
   отделив первый load от последующих циклов.
3. Повторить Motorola gate несколько раз одной сборкой и проверить, что
   pressure callbacks не сопровождаются context loss, OOM или растущим
   post-unload plateau.
4. Проверить recovery после Android memory pressure; оставить автоматическую
   выгрузку модели только opt-in политикой, если измерения докажут её пользу.

Текущий прогресс: первый срез нормализует ненадёжный platform max RSS внутри
`VrmHostResourceMonitor`: `maxRssBytes` монотонно хранит максимум platform peak и
всех current RSS, наблюдавшихся данным controller. Soak-отчёт дополнен
`rssSampledPeakMiB`, а также linear slopes loaded/unloaded RSS после исключения
первого warm-up sample. Значения остаются диагностическими и не вводят hard
limit или автоматическую выгрузку модели. Контракт покрыт regression test для
падающего platform max RSS; Flutter analyze и 94 Flutter-теста проходят.
Короткий gate на Motorola moto g 5G (2022) пройден: sampled peak 665.1 MiB,
normalized max 673.0 MiB, loaded/unloaded slopes после warm-up
−50.37/−43.87 MiB за цикл, 4 memory-pressure события, `thermal=none`, context
loss и runtime errors отсутствуют. Matrix `matrix-1wa37sfxsm6wy`.

Два полных последовательных gate одной сборки `300 s / 10 cycles` также прошли:
`matrix-3l6i0j1vllm6n` и `matrix-2xv8kftf8kx2u`. Sampled peak составил
645.8/632.8 MiB, normalized max — 655.5/644.2 MiB, loaded slopes —
−5.62/−2.62 MiB за цикл, unloaded slopes — −4.11/−0.91 MiB за цикл. При 2/1
memory-pressure callbacks не было OOM, context loss, runtime errors или
растущего post-unload plateau; renderer textures возвращались 28/0 во всех
циклах. Положительный start/end delta 139.4/198.3 MiB относится к начальному
прогреву Flutter/WebView и не продолжился линейным ростом после первого цикла.

Финальный recovery gate `matrix-36hq9syottrov` детерминированно отправил Flutter
memory-pressure signal в середине steady-фазы. После него успешно выполнены 15
health checks, 30 amplitude batches и 6 Pose/VRMA-переходов; модель осталась
загруженной, context loss равен нулю. Всего тест наблюдал 4 pressure-события и
завершился `Passed`. Автоматическая выгрузка модели не добавлена: текущие
измерения не доказывают её пользу и показывают корректное продолжение работы без
разрушительного вмешательства. Все критерии Stage 32 закрыты.

### Stage 33 — воспроизводимые Firebase gates и evidence artifacts

Статус: выполнено.

Цель: исключить неверную маркировку APK и ручные ошибки при повторных физических
performance-прогонах, не добавляя Firebase-зависимости в публичный пакет.

Работы:

1. Записывать рядом с Firebase APK атомарный build manifest: schema, встроенные
   soak defines, test entrypoint/ABI, размеры и SHA-256 app/test APK.
2. При `-SkipBuild` строго проверять manifest, requested profile и текущие APK до
   авторизации или upload; предоставить локальный `-ValidateArtifactsOnly`.
3. Сохранять структурированный run record с matrix ID, устройством, outcome и
   GCS/Console references для каждого repeat.
4. Автоматически извлекать JUnit и `runtime_soak_*` строки в единый JSON/Markdown
   evidence report и сравнивать повторные прогоны по инвариантам.

Текущий прогресс: первый срез выполнен. `run_firebase_soak.ps1` удаляет stale
manifest перед сборкой, после успешной targeted build атомарно записывает schema
v1 и блокирует reuse при несовпадающих duration/cycles/injection, размерах или
SHA-256. Режим `-ValidateArtifactsOnly` проверяет комплект без cloud upload.
Реальный recovery APK `30 s / 3 cycles` прошёл matching-проверку; запрос
`300 s / 10 cycles` к тому же бинарнику ожидаемо отклонён до обращения к
Firebase. Windows CI дополнительно парсит PowerShell-скрипты. Второй срез
перевёл cloud launch на machine-readable `testMatrixId` и официальный Testing
API polling. Для каждого repeat атомарно сохраняется schema-v1 run record с
state/outcome, requested/actual device, GCS/Console references и точной копией
APK manifest. Нормализация проверена на завершённом physical SUCCESS matrix
`matrix-36hq9syottrov`; новый `matrix-3rw2r033adao9` был отклонён Firebase до
execution из-за исчерпанной test quota и сохранён как
`INVALID/TEST_QUOTA_EXCEEDED`. Failure-path не маскируется и остаётся nonzero.
Offline regression test покрывает exact/fallback/ambiguous matrix IDs, terminal
states, нормализацию execution/artifact metadata и атомарную JSON-запись; он
выполняется в Windows CI вместе с parser-check. Третий срез автоматически
скачивает JUnit/logcat успешной matrix, строго разбирает четыре
`runtime_soak_*` фазы и создаёт schema-v1 `evidence.json` и читаемый
`evidence.md`. Gate проверяет matrix/JUnit, duration/cycles, texture baseline и
post-pressure recovery; RSS peak/slopes сохраняются как сравнительный профиль,
но не превращены в универсальный порог. Offline-тесты покрывают валидный отчёт,
texture drift и отсутствие обязательной фазы. End-to-end экспорт проверен на
реальных GCS artifacts `matrix-36hq9syottrov`: все пять evidence checks прошли.
Финальный срез создаёт JSON/Markdown comparison для `RepeatCount > 1` и требует
полный набор уникальных repeat indices, одинаковые APK/profile/device, model
texture footprint и texture baseline. FPS, frame p95 и RSS metrics сохраняются
с min/max/average/spread, но не используются как device-independent threshold.
Offline coverage проверяет успешное сравнение, запись artifacts и отклонение
подменённого APK hash. Все четыре пункта Stage 33 реализованы; новый тройной
physical run остаётся операционным pre-release gate и будет выполнен после
восстановления Firebase-квоты, а не незакрытой задачей архитектуры.
Реализация Stage 33 зафиксирована коммитами `f187ef8` и `3e222b2`.

### Stage 34 — изоляция runtime-сессии от Flutter-представления

Статус: выполнено.

Цель: убрать из `VrmView` владение состоянием runtime-документа, сохранив
публичный `VrmController`, protocol v3 и наблюдаемое поведение Android/Windows.

Работы:

1. Вынести поколения runtime, ordered replay, lifecycle-синхронизацию, bounded
   recovery и camera snapshot в `VrmRuntimeSessionCoordinator`.
2. Оставить `VrmView` владельцем Flutter lifecycle observer, WebView surface и
   визуального состояния; вынести controller subscriptions, transport binding и
   content-host lifetime в единый runtime-session owner.
3. Покрыть coordinator unit-тестами порядка replay, superseded generation,
   bounded retry и однократного восстановления камеры.
4. После завершения переноса повторить Flutter suite и ручной runtime smoke на
   Windows; Android lifecycle/recovery оставить обязательным release gate.

Текущий прогресс: этап завершён. Coordinator не зависит от `State` или
`BuildContext`, объединяет lifecycle/replay/recovery state и владеет
`VrmRuntimeControllerBinding`. Binding инкапсулирует controller/WebView
subscriptions, transport, content-host lifetime и безопасный rebind; endpoint wiring
скрыт внутри `VrmController`. В `VrmView` не осталось собственного
generation/retry/replay state, resource binding или доступа к bridge/model/host
internals. Публичный API, protocol v3 и platform policy не изменены. Все 102
Flutter-теста, `flutter analyze` и Windows debug build проходят. Полная Windows
integration matrix из пяти gates и финальный lifecycle/recovery rerun успешно
выполнены 2026-09-29. Android lifecycle/recovery сохраняется обязательным
physical release gate.

Критерии готовности:

- в `VrmView` нет собственного состояния generation/retry/replay;
- смена controller, reload и disposal имеют одного владельца runtime-сессии;
- устаревший replay не применяет состояние к новому документу;
- recovery остаётся bounded и не создаёт параллельных reload;
- поведение камеры и Windows/Android lifecycle не изменилось;
- полный Flutter test suite и platform smoke проходят.

### Stage 35 — внутренняя декомпозиция VrmController

Статус: выполнено.

Цель: сохранить единый публичный `VrmController`, но вынести его внутренние
resource/model/motion/speech/scene responsibilities в небольшие тестируемые
компоненты без изменения публичного API и protocol v3.

Работы:

1. Вынести общий pipeline временной публикации, отправки и освобождения
   hosted resources.
2. Разделять model/resource transfer, motion, speech и scene/graphics только
   там, где граница владения и race/disposal-семантика остаются явными.
3. Сохранить `VrmController` публичным facade и единым источником событий и
   lifetime-семантики.
4. После каждого среза повторять unit/analyze и релевантные Windows integration
   gates; Android physical release gates не ослаблять.

Текущий прогресс: первый срез завершён. `VrmHostedResourceDispatcher` владеет
attach/detach content host, проверкой активного host, выдачей временного URL,
отправкой команды и гарантированным release в `finally`. Загрузка модели,
анимации и фона делегирует этот pipeline без изменения команд protocol v3.

Второй срез завершён. `VrmAnimationDispatcher` владеет validation, генерацией
playback identity, формированием hosted/public URL payload и командами
pause/resume/cancel/stop/speed. Публичные методы `VrmController` остались
facade, а его размер уменьшился примерно с 1430 до 1300 строк. Три новых
unit-теста фиксируют identity, options, release и отсутствие payload у
pause/cancel; всего проходят 109 Flutter-тестов и `flutter analyze`. Полная
Windows integration matrix прошла после первого среза, затронутый
motion/speech gate повторно прошёл после второго среза 2026-09-29.

Третий срез завершён. `VrmModelDispatcher` стал единственным владельцем
`VrmModelSessionState`, generation-safe completion, hosted/public URL transfer,
cancel и unload-команд. `VrmController` сохранил только междоменный сброс speech
и camera state. Четыре новых unit-теста фиксируют hosted release, stale
replacement после runtime loss, cancel ordering и unload completion. Всего
проходят 113 Flutter-тестов, `flutter analyze` и полная Windows integration
matrix из пяти gates; controller уменьшился примерно до 1260 строк. Проверено
2026-09-30.

Четвёртый срез завершён. `VrmSpeechDispatcher` стал единственным владельцем
`VrmSpeechSessionState`, input revision, direct latest-value каналов, timeline
validation и begin/append/finish/cancel команд. Публичный `VrmSpeechSession`
сохранил API, но теперь удерживает только dispatcher, а не весь controller.
Четыре новых unit-теста фиксируют monotonic revision, stale handles, finishing,
frame ordering и replacement при ошибке старой команды. Всего проходят 117
Flutter-тестов и `flutter analyze`; Windows motion/speech и runtime/recovery
gates повторно прошли 2026-09-30. Controller уменьшился примерно до 1030 строк.

Пятый срез завершён. `VrmSceneDispatcher` отделяет fire-and-forget lighting,
physics и wind от подтверждаемых background operations и владеет hosted/public
background payload. `VrmGraphicsDispatcher` владеет renderer validation,
preset/adaptive/settings commands и strict performance query decoding. Четыре
новых unit-теста фиксируют scene payload, background release, graphics settings
и query boundary. Всего проходят 121 Flutter-тест и `flutter analyze`; Windows
runtime/scene и resource-loading gates повторно прошли 2026-09-30. Controller
уменьшился примерно до 960 строк.

Шестой срез завершён. `VrmAvatarControlDispatcher` инкапсулирует Pose API,
expression layers, custom blendshapes, auto-blink/saccades и latest-value gaze.
Передача mouth-layer согласована с `VrmSpeechDispatcher` через монотонную
speech revision, поэтому ручное выражение не может оставить активной устаревшую
speech-сессию. `VrmController` сохраняет mood как высокоуровневую композицию
avatar и scene команд. Четыре новых unit-теста фиксируют pose serialization,
mouth ownership, validation и gaze transport. Всего проходят 125 Flutter-тестов
и `flutter analyze`; Windows motion/speech и runtime smoke gates повторно
прошли 2026-09-30. Controller уменьшился примерно до 910 строк.

Stage 35 завершён: внутренние владельцы отделены там, где существуют явные
state/race/resource границы; дальнейшее дробление facade без измеримой причины
не требуется. Публичный API и protocol v3 не изменены.

Критерии готовности:

- hosted resources освобождаются одним общим pipeline;
- model и speech transient state имеют единственных владельцев;
- animation identity, scene/graphics и avatar commands тестируются отдельно;
- `VrmController` остаётся единым публичным facade и источником событий;
- unit/analyze и затронутые Windows integration gates проходят.

Реализация Stage 34–35 зафиксирована коммитом `ef57a75`.

### Stage 36 — terminal semantics и диагностика transport bridge

Статус: выполнено.

Цель: гарантировать, что каждая отправленная protocol-команда имеет ровно один
terminal outcome и не остаётся pending до общего timeout после получения
повреждённого ответа.

Работы:

1. Выделить `VrmBridge` из library-part в самостоятельный внутренний компонент,
   не экспортируя низкоуровневый API пользователю пакета.
2. Сделать success, runtime error и malformed response с известным correlation
   ID terminal для соответствующего Future.
3. Поглощать ожидаемые поздние responses после timeout, dispatch failure,
   transport detach/reload и dispose с bounded-памятью ID.
4. Публиковать некоррелируемые malformed сообщения через `onError` и покрыть
   success/error/timeout/detach/dispatch failure regression-тестами.
5. Повторить полный Flutter suite и Windows runtime/recovery/smoke gates.

Этап завершён. Пять новых unit-тестов фиксируют success/runtime error,
немедленное завершение malformed correlated response, timeout, detach,
dispatch failure и отсутствие ложной ошибки от позднего ответа. Всего проходят
130 Flutter-тестов и `flutter analyze`. Windows runtime/recovery и runtime smoke
gates повторно прошли 2026-09-30. Публичный API и protocol v3 не изменены.
Реализация зафиксирована коммитом `4ff4bb7`.

Критерии готовности:

- известный response ID никогда не остаётся pending после получения envelope;
- каждая pending-команда завершается не более одного раза;
- ожидаемые late responses не создают ложный `onError`;
- malformed input без известной команды наблюдаем через `onError`;
- timeout остаётся bounded и тестируется без двухминутного ожидания;
- unit/analyze и Windows runtime gates проходят.

### Stage 37 — детерминированный async teardown runtime-сессии

Статус: выполнено.

Цель: исключить гонку между закрытием controller binding/content host и
уничтожением native WebView, а также не оставлять recovery backoff активным
после dispose.

Работы:

1. Сделать `VrmRuntimeSessionCoordinator.dispose()` асинхронным и идемпотентным,
   синхронно блокируя новые callbacks и возвращая единый cleanup Future.
2. Сделать recovery delay отменяемой при dispose, успешной activation и
   отключении recovery policy.
3. Дождаться отмены controller/WebView subscriptions и закрытия content host до
   окончательного `VrmWebViewAdapter.dispose()`.
4. Гарантировать освобождение WebView даже при ошибке session/content-host
   teardown, не создавая необработанный async exception после widget dispose.
5. Покрыть delayed recovery и delayed content-host close regression-тестами и
   повторить Windows recovery/resource-loading gates.

Этап завершён. Coordinator немедленно отменяет даже минутный recovery delay и
возвращает один Future для повторных dispose-вызовов. Binding test подтверждает,
что cleanup Future не завершается до асинхронного `contentHost.close()`, а
`VrmView` освобождает native WebView после session cleanup. Всего проходят 131
Flutter-тест и `flutter analyze`; Windows runtime/recovery и resource-loading
gates повторно прошли 2026-09-30. Публичный API и protocol v3 не изменены.
Реализация зафиксирована коммитом `9453052`.

Критерии готовности:

- dispose немедленно запрещает новые session callbacks;
- повторные dispose-вызовы разделяют один cleanup Future;
- recovery delay не переживает teardown и не задерживает его до backoff timeout;
- content host и subscriptions закрываются до окончательного WebView disposal;
- ошибка одного teardown-шага не оставляет native WebView неосвобождённым;
- unit/analyze и Windows recovery/resource-loading gates проходят.

### Stage 38 — сериализация declarative graphics/background configuration

Статус: выполнено.

Цель: исключить out-of-order применение `VrmView` graphics/background state при
быстрых rebuild, controller rebind и одновременном initial/recovery replay.

Работы:

1. Добавить внутренний `VrmLatestTaskDispatcher<T>` с одним in-flight task и
   только последним ещё не начатым значением.
2. Предоставить terminal Future каждому submit; superseded pending-вызовы
   разделяют outcome последнего реально отправленного значения.
3. Провести initial replay, model-assessment updates и `didUpdateWidget` через
   одни и те же сериализованные graphics/background каналы.
4. При controller rebind обязательно поставить актуальные snapshots в очередь,
   чтобы операция старого controller не могла стать конечным состоянием.
5. Закрывать queues до runtime-session teardown и покрыть serialization,
   supersession, error и close semantics unit-тестами.

Этап завершён. Graphics preset вместе с рассчитанной adaptive policy и базовый
background захватываются в immutable snapshots. Для каждого канала выполняется
одна команда за раз; серия rebuild сохраняет только последний pending snapshot.
Три новых unit-теста фиксируют порядок `[first, latest]`, общий error outcome
superseded waiters и закрытие очереди при активной операции. Всего проходят 134
Flutter-теста и `flutter analyze`; Windows runtime/recovery и runtime smoke gates
повторно прошли 2026-10-01. Публичный API и protocol v3 не изменены.
Реализация зафиксирована коммитом `36d4678`.

Критерии готовности:

- replay и rebuild не отправляют параллельные конфигурации одного канала;
- промежуточные pending snapshots не применяются;
- последний desired snapshot становится конечным applied state;
- controller rebind не оставляет конфигурацию предыдущего controller последней;
- dispose отклоняет queued/future submit и позволяет in-flight cleanup;
- unit/analyze и Windows recovery/smoke gates проходят.

### Stage 39 — детерминированный lifecycle animation queue

Статус: выполнено.

Цель: устранить race между fire-and-forget отменой event subscriptions и
повторным запуском либо уничтожением `VrmAnimationQueue`.

Работы:

1. Сделать subscriptions ресурсом всего lifetime очереди; `stop()`, завершение
   non-loop очереди и restore stopped snapshot меняют playback state, но не
   пересоздают listeners.
2. Заменить синхронный `dispose()` на идемпотентный `Future<void> dispose()`.
3. При dispose сначала запретить новые операции, затем дождаться отмены входящих
   subscriptions и только после этого закрыть `onStateChanged`/`onError`.
4. Обновить публичную документацию и все тестовые владельцы очереди на
   `await queue.dispose()`.
5. Зафиксировать unit-тестами единственную lifetime-подписку и terminal cleanup
   Future с асинхронной отменой.

Этап завершён. Быстрый `stop → start` использует существующие listeners, а
повторные dispose-вызовы возвращают один cleanup Future. Если отмена подписки
асинхронна, dispose не завершается преждевременно; публичные event streams
закрываются после входящих источников. Всего проходят 136 Flutter-тестов и
`flutter analyze`; Windows motion/speech и runtime/recovery gates повторно
прошли 2026-10-01. Protocol v3 не изменён; публичный dispose-контракт усилен до
ожидаемого `Future<void>`. Реализация зафиксирована коммитом `f51e9ac`.

Критерии готовности:

- `stop → start` не создаёт дополнительную подписку;
- stopped state не означает преждевременное освобождение event infrastructure;
- повторные dispose-вызовы разделяют один cleanup Future;
- dispose ожидает отмену subscriptions и закрытие event streams;
- после начала dispose новые queue-команды синхронно отклоняются;
- unit/analyze и Windows motion/speech/recovery gates проходят.

### Stage 40 — детерминированная очистка controller rebind

Статус: выполнено.

Цель: исключить незавершённые fire-and-forget отмены controller subscriptions
при замене `VrmController` в существующем `VrmView`.

Работы:

1. Сохранить синхронную передачу endpoint/transport/content-host ownership, чтобы
   `didUpdateWidget` не блокировался на отмене старых listeners.
2. Объединять отмену всех retired controller subscriptions в tracked cleanup
   Future.
3. При session dispose ждать retired cleanup вместе с текущими controller и
   WebView subscriptions.
4. Публиковать ошибки retired cancellation через соответствующий старый endpoint,
   не превращая их в необработанные async errors.
5. Закрывать content host через `finally`, даже если отмена текущей subscription
   завершилась ошибкой.

Этап завершён. Identity guard немедленно запрещает старому endpoint влиять на
сессию, а resource cleanup получает строгую terminal-границу. Три новых
regression-теста проверяют ожидание rebind cancellation, диагностику retired
ошибки и закрытие content host при ошибке текущей отмены. Всего проходят 139
Flutter-тестов и `flutter analyze`; Windows runtime/recovery, resource-loading и
runtime smoke gates повторно прошли 2026-10-01. Публичный API и protocol v3 не
изменены. Реализация зафиксирована коммитом `0cbbf6d`.

Критерии готовности:

- старый endpoint синхронно теряет callback ownership при rebind;
- dispose ждёт отмену subscriptions всех предыдущих endpoint;
- ошибка retired cancellation диагностируется и не становится unhandled;
- content host закрывается при успешной и ошибочной отмене subscriptions;
- повторный dispose сохраняет один terminal Future;
- unit/analyze и Windows recovery/resource/smoke gates проходят.

### Stage 41 — terminal cleanup запущенных runtime binding callbacks

Статус: выполнено.

Цель: включить callbacks, уже запущенные controller event-ом до rebind/dispose,
в детерминированную границу teardown.

Работы:

1. Хранить только активные callback Futures во внутреннем наборе binding.
2. Удалять завершённые задачи без необработанных error Futures.
3. При dispose ждать snapshot активных callbacks вместе с subscription cleanup.
4. Сохранять identity guard: ошибка callback старого endpoint после rebind не
   публикуется новому controller.
5. Не закрывать content host, пока уже начатый callback не завершён.

Этап завершён. Rebind остаётся синхронным и не блокирует Flutter rebuild, но
последующий dispose имеет terminal Future для всей уже начатой callback-работы.
Новый regression-тест запускает model callback, выполняет rebind и dispose,
проверяет удержание content host до callback completion и подавление stale
ошибки. Всего проходят 140 Flutter-тестов и `flutter analyze`; Windows
runtime/recovery и runtime smoke gates повторно прошли 2026-10-01. Публичный API
и protocol v3 не изменены. Реализация зафиксирована коммитом `5713400`.

Критерии готовности:

- callback добавляется в tracking до возможного teardown;
- завершённый callback удаляется и не накапливается в binding;
- dispose ждёт callbacks, начатые до rebind или dispose;
- stale callback error не публикуется replacement controller;
- content host закрывается после callback/subscription cleanup;
- unit/analyze и Windows recovery/smoke gates проходят.

### Stage 42 — сериализация initialization/teardown VrmView

Статус: выполнено.

Цель: исключить параллельный native WebView disposal во время незавершённой
initialization и запуска локального content host.

Работы:

1. Добавить внутренний `VrmViewLifecycleCoordinator`, который немедленно запускает
   initialization и сохраняет её Future.
2. Возвращать один идемпотентный terminal Future для повторных dispose-вызовов.
3. Всегда выполнять cleanup после settlement initialization, включая error path.
4. Удалить `WebView.dispose()` из initialization-ветви после раннего widget
   disposal; оставить native adapter одному cleanup owner.
5. Сохранить синхронную блокировку session callbacks в `State.dispose()`.

Этап завершён. Runtime session начинает teardown сразу, а native cleanup ожидает
завершения initialization и выполняется единожды. Два unit-теста фиксируют
порядок initialization → cleanup, idempotence и cleanup после initialization
error. Всего проходят 142 Flutter-теста и `flutter analyze`; Windows runtime-race,
runtime/recovery и runtime smoke gates повторно прошли 2026-10-01. Публичный API
и protocol v3 не изменены. Реализация зафиксирована коммитом `9c211e8`.

Критерии готовности:

- ранний dispose не освобождает adapter во время его initialize;
- initialization-ветвь не владеет native disposal;
- cleanup выполняется один раз после success/error initialization;
- повторные dispose-вызовы разделяют один terminal Future;
- session callbacks блокируются синхронно в `State.dispose()`;
- unit/analyze и Windows race/recovery/smoke gates проходят.

### Stage 43 — terminal settlement declarative-задач VrmView

Статус: выполнено.

Цель: не уничтожать native WebView, пока активная graphics или background
configuration ещё выполняется через bridge.

Работы:

1. После закрытия обоих `VrmLatestTaskDispatcher` захватить их актуальные `idle`
   Futures одним settlement barrier.
2. Добавить lifecycle-фазу `settleBeforeCleanup` между initialization и native
   cleanup.
3. Выполнять все lifecycle-фазы даже после ошибки и повторно выбрасывать первую
   ошибку с исходным stack trace после cleanup.
4. Сохранить немедленное начало session teardown, чтобы transport detach быстро
   завершал активные bridge-команды вместо ожидания command timeout.
5. Покрыть порядок фаз, идемпотентность и error path unit-тестами.

Этап завершён. Terminal порядок теперь имеет вид initialization → declarative
settlement → runtime/native cleanup. Queued и future configurations отклоняются,
а уже активные операции достигают terminal state до освобождения WebView. Всего
проходят 144 Flutter-теста и `flutter analyze`; Windows runtime-race,
runtime/recovery и runtime smoke gates повторно прошли 2026-10-01. Публичный API
и protocol v3 не изменены. Реализация зафиксирована коммитом `26dfc26`.

Критерии готовности:

- active graphics/background operations входят в terminal Future view;
- queued и future dispatcher work отклоняются после close;
- native cleanup начинается после initialization и declarative settlement;
- cleanup выполняется при ошибке любой предыдущей lifecycle-фазы;
- повторный dispose сохраняет один terminal Future;
- unit/analyze и Windows race/recovery/smoke gates проходят.

### Stage 44 — детерминированный teardown render lifecycle

Статус: выполнено.

Цель: включить уже выполняющуюся pause/resume-команду render loop в terminal
границу runtime-сессии.

Работы:

1. Сделать `VrmRenderLifecycleCoordinator.dispose()` асинхронным и
   идемпотентным.
2. Синхронно закрыть dispatcher и вернуть Future его актуального `idle`.
3. Включить lifecycle disposal в `VrmRuntimeSessionCoordinator.dispose()` рядом
   с binding cleanup и recovery task.
4. Сохранить подавление stale lifecycle errors после close.
5. Проверить coordinator- и session-уровни отдельными regression-тестами.

Этап завершён. Активный render lifecycle dispatch удерживает session terminal
Future до своего завершения, повторный dispose разделяет тот же Future, а queued
состояние после close не запускается. Всего проходят 146 Flutter-тестов и
`flutter analyze`; Windows runtime-race, runtime/recovery и runtime smoke gates
повторно прошли 2026-10-01. Публичный API и protocol v3 не изменены. Реализация
зафиксирована коммитом `3e6b793`.

Критерии готовности:

- lifecycle dispose синхронно запрещает новую синхронизацию;
- активная pause/resume-команда входит в terminal Future;
- повторные dispose-вызовы возвращают один Future;
- runtime session ожидает lifecycle, binding и recovery cleanup;
- stale lifecycle error после close не публикуется;
- unit/analyze и Windows race/recovery/smoke gates проходят.

### Stage 45 — идемпотентный и error-safe teardown VrmController

Статус: выполнено.

Цель: исключить преждевременное завершение повторного `dispose()` и гарантировать
освобождение bridge после ошибки любого более раннего cleanup-шагa.

Работы:

1. Сохранять один `_disposeFuture` и возвращать его всем повторным вызовам.
2. Синхронно помечать controller disposed до первого асинхронного ожидания.
3. Выполнять thermal monitor stop, state subscription cancellation и bridge
   dispose через общий последовательный cleanup runner.
4. Не прекращать teardown после ошибки фазы; после всех фаз повторно выбрасывать
   первую ошибку с исходным stack trace.
5. Покрыть idempotence и multi-error cleanup regression-тестами.

Этап завершён. Все повторные dispose-вызовы разделяют один terminal Future,
новые mutating-команды блокируются сразу, а каждая cleanup-фаза выполняется
ровно один раз даже после предыдущей ошибки. Всего проходят 148 Flutter-тестов и
`flutter analyze`; Windows runtime-race, runtime/recovery и runtime smoke gates
повторно прошли 2026-10-02. Публичные сигнатуры и protocol v3 не изменены.
Реализация зафиксирована коммитом `8fe0273`.

Критерии готовности:

- первый dispose синхронно блокирует новые controller operations;
- повторные dispose-вызовы возвращают идентичный Future;
- ошибка thermal stop не пропускает subscription и bridge cleanup;
- ошибка subscription cancellation не пропускает bridge cleanup;
- после всех фаз повторно выбрасывается первая ошибка;
- unit/analyze и Windows race/recovery/smoke gates проходят.

### Stage 46 — сериализация lifecycle Android thermal monitor

Статус: выполнено.

Цель: исключить перекрытие старой и новой thermal subscriptions при быстром
controller detach/rebind и включить текущий transition в controller teardown.

Работы:

1. Хранить desired running state независимо от текущей subscription.
2. Сериализовать cancellation и последующий restart через один reconciliation
   Future.
3. Маркировать subscription generation и игнорировать события stale listener.
4. Не сбрасывать status поздним stop, если во время cancellation уже запрошен
   restart.
5. Публиковать ошибки fire-and-forget detach stop через controller error stream.
6. Добавить race-тест с управляемым незавершённым cancellation.

Этап завершён. Быстрый detach → rebind больше не создаёт перекрывающиеся
listeners, stale event не меняет snapshot, а stop Future завершается только после
достижения последнего desired state. Всего проходят 149 Flutter-тестов и
`flutter analyze`; Windows runtime-race, runtime/recovery и runtime smoke gates
повторно прошли 2026-10-02. Публичный API и protocol v3 не изменены. Реализация
зафиксирована коммитом `331d000`.

Критерии готовности:

- stop и restart одной monitor instance не выполняются параллельно;
- stale subscription events игнорируются generation guard;
- поздний stop не сбрасывает status новой subscription;
- controller dispose ожидает текущий monitor transition;
- detach cancellation error не становится необработанным Future;
- unit/analyze и Windows race/recovery/smoke gates проходят.

### Stage 47 — детерминированный teardown loopback content host

Статус: выполнено.

Цель: не завершать `LocalAssetsServer.close()`, пока принятый HTTP handler ещё
читает package/file/memory resource или закрывает response.

Работы:

1. Отслеживать terminal Future каждого принятого request handler.
2. Синхронно блокировать новые операции и возвращать один `_closeFuture`.
3. Сначала закрывать listener/соединения, затем ожидать handlers и только после
   этого очищать registry opaque resources.
4. Выполнять все cleanup-фазы даже после ошибки и повторно выбрасывать первую.
5. Не обращаться к public started-state host из уже принятого handler.
6. Добавить управляемый race-тест незавершённого запроса и повторного close.

Этап завершён. `close()` идемпотентен, принятые handlers входят в terminal
barrier, а resource registry живёт до их завершения. Всего проходят 150
Flutter-тестов и `flutter analyze`; Windows runtime-race, runtime/recovery и
runtime smoke gates повторно прошли 2026-10-02. Публичный API и protocol v3 не
изменены. Реализация зафиксирована коммитом `4e48af5`.

Критерии готовности:

- первый close синхронно запрещает новую работу;
- повторные close-вызовы возвращают идентичный Future;
- listener больше не принимает соединения после начала close;
- terminal Future ждёт уже принятые request handlers;
- resources очищаются после settlement handlers даже при ошибке ранней фазы;
- unit/analyze и Windows race/recovery/smoke gates проходят.

### Stage 48 — terminal settlement transport dispatch VrmBridge

Статус: выполнено.

Цель: не освобождать native WebView, пока уже вызванный `runJavaScript` ещё не
достиг terminal state, даже если response Future команды уже завершён detach,
timeout или runtime reload.

Работы:

1. Отслеживать Futures всех transport dispatch операций отдельно от protocol
   response Futures.
2. Привязать dispatch к transport owner/generation и исключить влияние stale
   completion на новый binding.
3. Возвращать terminal detach Future через внутренний endpoint contract и
   включить retired/current transport settlement в binding cleanup.
4. Сделать bridge dispose идемпотентным и error-safe относительно active
   dispatch, latest-value channels и event stream.
5. Покрыть delayed dispatch, reload, detach/rebind и dispose race-тестами.

Этап завершён. Bridge отслеживает native command dispatch и runtime reload по
identity transport owner. Detach немедленно завершает pending protocol responses,
но его Future ждёт transport terminal state; binding включает current и retired
cleanup в общий barrier. Всего проходят 154 Flutter-теста и `flutter analyze`;
Windows runtime-race, runtime/recovery и runtime smoke gates повторно прошли
2026-10-02. Публичный API и protocol v3 не изменены. Реализация зафиксирована
коммитом `90ce974`.

Критерии готовности:

- protocol response и transport dispatch имеют независимые terminal состояния;
- detach немедленно запрещает новые команды старому owner;
- native WebView cleanup ждёт active transport dispatch;
- stale dispatch error не публикуется новому endpoint;
- повторный bridge dispose возвращает один Future;
- unit/analyze и Windows race/recovery/smoke gates проходят.

### Stage 49 — унифицированный lifecycle платформенных WebView-адаптеров

Статус: выполнено.

Цель: дать Android и Windows adapters одинаковую terminal-семантику и исключить
повторный native dispose либо новую platform operation после начала cleanup.

Работы:

1. Вынести внутреннюю lifecycle-state machine adapters без расширения публичного
   API пакета.
2. Разделять один initialization Future и один dispose Future между повторными
   вызовами.
3. Синхронно запрещать `load`/`runJavaScript` после начала dispose.
4. Дождаться initialization и выполнить все доступные stream/native cleanup-фазы
   error-safe, сохраняя первую ошибку.
5. Покрыть initialize/dispose, repeated dispose и post-dispose operation races
   платформенно-независимыми unit-тестами и Windows gates.

Этап завершён. Общий lifecycle coordinator разделяет initialization/dispose
Futures, отслеживает active platform operations и выполняет cleanup-фазы через
error-safe runner. Всего проходят 157 Flutter-тестов и `flutter analyze`;
Windows runtime-race, runtime/recovery и runtime smoke gates повторно прошли
2026-10-02. Публичный API и protocol v3 не изменены. Реализация зафиксирована
коммитом `888065b`.

Критерии готовности:

- обе платформы используют одинаковый lifecycle contract;
- native controller освобождается ровно один раз;
- повторный dispose возвращает один terminal Future;
- initialization и disposal не выполняются параллельно;
- после начала dispose новые platform operations дают `StateError`;
- unit/analyze и Windows race/recovery/smoke gates проходят.

### Stage 50 — terminal settlement операций VrmAnimationQueue

Статус: выполнено.

Цель: не завершать `VrmAnimationQueue.dispose()`, пока уже запущенный playback
или control callback ещё выполняется через controller.

Работы:

1. Отслеживать terminal Futures `_runPlaybackOperation` и `_runOperation`.
2. Синхронно инвалидировать generation и запрещать новые queue-команды.
3. Дождаться active operations вместе с cancellation всех subscriptions.
4. Закрывать state/error streams даже после ошибки operation или cancellation и
   повторно выбрасывать первую ошибку.
5. Добавить delayed playback/control и multi-error cleanup regression-тесты.

Критерии готовности:

- queue dispose ждёт active playback и control callbacks;
- позднее завершение не меняет state и не публикует ошибку после dispose;
- все subscriptions и streams освобождаются после settlement операций;
- повторный dispose возвращает один Future;
- ошибка одной cleanup-фазы не пропускает остальные;
- unit/analyze и Windows race/recovery/smoke gates проходят.

Этап завершён. Active playback/control operations входят в terminal boundary
очереди, все subscription cancellation запускаются до ожидания, а state/error
streams закрываются независимо от ошибки предыдущей cleanup-фазы. Добавлены
регрессии для delayed operations и cancellation failure. Всего проходят 159
Flutter-тестов и `flutter analyze`; Windows runtime-race, runtime/recovery и
runtime smoke gates повторно прошли 2026-10-02. Реализация зафиксирована коммитом
`51b8264`.

### Stage 51 — error-safe teardown subscriptions runtime binding

Статус: выполнено.

Цель: исключить частично выполненный teardown `VrmRuntimeControllerBinding`, если
один из `StreamSubscription.cancel()` синхронно выбрасывает исключение.

Работы:

1. Сначала создать защищённые terminal Futures для cancellation всех controller и
   WebView subscriptions, не прерывая обход коллекции синхронной ошибкой.
2. Выполнить transport, retired cleanup, active callback settlement и закрытие
   content host как error-safe фазы с сохранением первой ошибки.
3. Применить ту же гарантию к retired controller subscriptions при rebind.
4. Добавить регрессии для synchronous cancellation failure, нескольких ошибок и
   обязательного закрытия content host.

Критерии готовности:

- попытка cancellation выполняется для каждой subscription;
- content host закрывается даже после ошибки cancellation/transport/callback;
- первая ошибка сохраняется, остальные cleanup-фазы не пропускаются;
- повторный dispose возвращает один terminal Future;
- unit/analyze и Windows race/recovery/smoke gates проходят.

Этап завершён. Каждая cancellation обёрнута в отдельный `Future.sync`, все
операции входят в общий settlement, а content host закрывается следующей
error-safe фазой. Регрессия одновременно проверяет синхронную cancellation
failure, попытку отмены остальных subscriptions, ошибку close и сохранение первой
ошибки. Всего проходят 160 Flutter-тестов и `flutter analyze`; Windows gates
повторно прошли 2026-10-02. Реализация зафиксирована коммитом `1dd3f45`.

### Stage 52 — наблюдаемый asynchronous teardown VrmView

Статус: выполнено.

Цель: исключить необработанную async-ошибку из fire-and-forget lifecycle Future,
который запускается синхронным Flutter `State.dispose()`.

Работы:

1. Добавить внутренний terminal error handler к Future
   `VrmViewLifecycleCoordinator.dispose()` в widget teardown.
2. Передавать ошибку и исходный stack trace через стандартный
   `FlutterError.reportError` с контекстом cleanup `VrmView`.
3. Не менять порядок settlement declarative tasks, session, runtime и native
   WebView и не расширять публичный API.
4. Добавить widget/unit-регрессию для cleanup failure и отсутствия unhandled
   asynchronous error.

Критерии готовности:

- каждая ошибка terminal teardown наблюдаема через Flutter diagnostics;
- исходные error и stack trace не теряются;
- native/session cleanup по-прежнему выполняется один раз;
- успешный dispose не создаёт диагностик;
- unit/analyze и Windows race/recovery/smoke gates проходят.

Этап завершён. Lifecycle observer передаёт исходные error/stack trace в
`FlutterError.reportError`, успешный teardown не создаёт диагностик, а
session/WebView cleanup использует общий error-safe runner. Всего проходят 162
Flutter-теста и `flutter analyze`; Windows gates повторно прошли 2026-10-03.
Реализация зафиксирована коммитами `cfce87d` и `2a3a4df`.

### Stage 53 — единая диагностика declarative-задач VrmView

Статус: выполнено.

Цель: дать graphics/background configuration failures единый наблюдаемый
внутренний contract без изменения публичного API и recovery semantics.

Работы:

1. Вынести внутреннюю policy маршрутизации ошибок declarative-задач.
2. Сохранять подавление stale controller results и ожидаемого runtime
   cancellation.
3. Активные graphics failures направлять в runtime diagnostics и user-visible
   session error; background failures — в runtime diagnostics без лишнего UI.
4. Всегда сохранять исходный stack trace и добавить unit-регрессии для active,
   stale и canceled случаев.

Критерии готовности:

- одинаковые ошибки используют один внутренний routing contract;
- stale/canceled результаты не создают ложных диагностик;
- активный graphics failure остаётся видимым пользователю;
- fire-and-forget Futures не дают unhandled Zone error;
- unit/analyze и Windows race/recovery/smoke gates проходят.

Этап завершён. Общий observer немедленно устанавливает terminal error handler,
подавляет stale и ожидаемые canceled results, сохраняет исходный stack trace и
разделяет user-visible graphics error от diagnostic-only background error.
Добавлены регрессии active/stale/canceled/success и Zone handling. Всего проходят
166 Flutter-тестов и `flutter analyze`; Windows gates повторно прошли 2026-10-03.
Реализация зафиксирована коммитом `d56c5a4`.

### Stage 54 — типизированная отмена runtime transition

Статус: выполнено.

Цель: не публиковать ложную async-диагностику, когда pending-команда ожидаемо
отменяется из-за reload/recovery, сохранив ошибки реальных runtime failures.

Работы:

1. Представить ожидаемый reload/recovery transition типизированной причиной с
   кодом `canceled`, не меняя protocol v3.
2. Передавать эту причину всем pending command Futures при invalidation runtime.
3. Подавлять её только в fire-and-forget/latest-value diagnostic paths; публичный
   awaited Future должен завершаться типизированной ошибкой.
4. Не подавлять transport, malformed response, timeout и WebView resource errors.
5. Добавить unit-регрессии и убедиться, что Windows race gate проходит без
   ложного `Asynchronous VRM command failed`.

Критерии готовности:

- ожидаемый reload не создаёт `VrmErrorEvent` и debug stack для фоновой команды;
- awaiting caller получает `VrmRuntimeException(code: 'canceled')`;
- реальные runtime/transport failures продолжают публиковаться;
- recovery/race semantics и protocol v3 не меняются;
- unit/analyze и Windows race/recovery/smoke gates проходят.

Этап завершён. Одна причина `vrmRuntimeTransitionCancellation` используется при
invalidation bridge и session coordinator. Центральный `reportAsyncError`
подавляет только ожидаемый `canceled`, поэтому все владельцы fire-and-forget
операций получают одинаковую семантику без локальных фильтров. Awaited Future
сохраняет типизированную ошибку. Добавлены unit-регрессии для обоих путей и для
реального runtime failure. Всего проходят 169 Flutter-тестов и `flutter analyze`;
Windows race/recovery/smoke gates повторно прошли 2026-10-03. Реализация
зафиксирована коммитом `b89a894`.

### Stage 55 — контрольная ревизия контрактов после hardening

Статус: выполнено.

Цель: завершить серию архитектурных hardening-изменений проверкой согласованности
кода, публичной семантики, ownership-документов и канонических test gates.

Работы:

1. Проверить владельцев lifecycle, pending-команд, teardown и diagnostic state на
   всех границах `VrmView` → session coordinator → binding → bridge → adapter.
2. Синхронизировать `API_SEMANTICS.md`, `STATE_OWNERSHIP.md` и `TEST_MATRIX.md` с
   типизированной отменой runtime transition.
3. Запустить analyzer, полный Flutter unit/widget suite и канонические Windows
   integration gates.
4. Зафиксировать только воспроизводимые остаточные риски; не создавать новый
   этап декомпозиции без измеримой проблемы.

Критерии готовности:

- документация не противоречит runtime/error semantics реализации;
- у каждого async и lifecycle transition есть явный owner и terminal outcome;
- канонические локальные gates проходят;
- список дальнейших работ основан на продуктовой задаче, измерении или баге;
- при отсутствии таких задач архитектура считается стабилизированной.

Этап завершён. Read-only аудит подтвердил явных владельцев pending-команд,
lifecycle transitions, callbacks, transport operations и terminal cleanup.
Документы `API_SEMANTICS.md`, `STATE_OWNERSHIP.md` и `TEST_MATRIX.md` приведены
к типизированной reload/recovery cancellation. `flutter analyze` и все 169
Flutter-тестов прошли; Windows matrix подтвердила `runtime_smoke`,
`motion_speech`, `runtime_recovery`, `runtime_race` и `resource_loading`.
Новых воспроизводимых рисков и оснований для Stage 56 не обнаружено.

## 7. Правила обновления roadmap

- После этапа обновлять его статус и добавлять commit hash.
- Новая функция должна быть привязана к требованию или измеримой проблеме.
- Breaking wire change требует новой protocol version.
- Generated runtime не редактируется вручную.
- Изменения поведения проверяются минимум unit/contract тестом; lifecycle,
  loading, rendering и disposal — также smoke-тестом на затронутой платформе.
- Публикационные задачи остаются отложенными, пока это явно не изменено.
