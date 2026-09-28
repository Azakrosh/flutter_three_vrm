# План рефакторинга и развития flutter_three_vrm

Статус: активный рабочий документ
Дата аудита: 2026-09-27
Проверенная база: `0c25de8 test: validate Android memory pressure recovery`
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
| 33 | Воспроизводимые Firebase performance gates и evidence artifacts | В работе |

## 3. Состояние реализации

### Архитектура

```text
Flutter application
  └─ VrmView                 lifecycle, WebView, recovery, desired configuration
      └─ VrmController       публичный высокоуровневый API
          ├─ _VrmBridge      protocol v3, correlation IDs, timeout, events
          ├─ recovery state  replay generation, model/speech session ownership
          ├─ content host    session loopback, opaque resources
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

- Flutter library: 36 файлов, примерно 6340 строк;
- web source: 35 файлов, примерно 7090 строк;
- `runner.ts`: примерно 675 строк;
- `VrmController`: примерно 1430 строк;
- Flutter unit tests: 86;
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

### P2 — крупный публичный controller

Web runtime уже разделён на специализированные controllers, но
`VrmController` остаётся крупным публичным facade. Разделять его следует только
внутренне и только при изменении затронутой области, без расширения API ради
самого рефакторинга.

### P2 — публикационная готовность отложена

В `pubspec.yaml` установлен `publish_to: none`. Это соответствует принятому
решению. Проверки package metadata, generated API docs и release checklist не
являются текущим блокером и не должны отвлекать от стабилизации runtime.

## 5. Текущее направление

Ближайшее направление: **воспроизводимые Firebase performance gates и
машиночитаемые evidence artifacts без изменения runtime API**.

Сейчас не следует:

- обновлять Three.js/three-vrm без отдельной причины;
- добавлять новые эффекты или ещё один способ управления моделью;
- начинать публикацию;
- менять protocol v3 только ради рефакторинга;
- одновременно переделывать lifecycle, motion и speech semantics.

Stage 32 подтвердил bounded post-warm-up RSS и восстановление после
memory-pressure signal без автоматической выгрузки модели. Следующий шаг —
исключить человеческие ошибки между сборкой, повторным upload и анализом
Firebase-артефактов: каждый профиль должен быть связан с проверяемыми defines и
SHA APK, а результаты — собираться в сопоставимый отчёт.

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

Статус: в работе.

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
Следующий срез — агрегировать repeat evidence и сравнивать запуски одной сборки
по межпрогонным инвариантам без ложных device-independent FPS/RSS thresholds.

## 7. Правила обновления roadmap

- После этапа обновлять его статус и добавлять commit hash.
- Новая функция должна быть привязана к требованию или измеримой проблеме.
- Breaking wire change требует новой protocol version.
- Generated runtime не редактируется вручную.
- Изменения поведения проверяются минимум unit/contract тестом; lifecycle,
  loading, rendering и disposal — также smoke-тестом на затронутой платформе.
- Публикационные задачи остаются отложенными, пока это явно не изменено.
