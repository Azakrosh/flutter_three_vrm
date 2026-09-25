# План рефакторинга и развития flutter_three_vrm

Статус: активный рабочий документ
Дата аудита: 2026-09-24
Проверенная база: `f2aa0cf feat: define transient runtime session ownership`
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

- Flutter library: 35 файлов, примерно 6200 строк;
- web source: 34 файла, примерно 6900 строк;
- `runner.ts`: примерно 675 строк;
- `VrmController`: примерно 1430 строк;
- Flutter unit tests: 86;
- web unit tests: 162;
- один сквозной runtime smoke-сценарий, примерно 435 строк.

Числа нужны как ориентир концентрации ответственности, а не как целевые KPI.

## 4. Оставшиеся архитектурные риски

### Закрыто в Stage 26.20 — весь runtime проверяется TypeScript

`web/tsconfig.json` включает `src/**/*.ts` и `test/**/*.ts`, в том числе
`web/src/runner.ts`. Facade явно реализует `RuntimeCommandHost`, а координация
модели, кадра, lifecycle и protocol events проходит строгий `tsc --noEmit`.

### P0 — wire contract ещё не полностью типизирован

Protocol v3 имеет общий каталог 49 command и 14 event, типизированный
TypeScript dispatcher и enum-команды в Dart. Однако часть payload/result
остаётся `RuntimeRecord`/`unknown` в TypeScript и `Map<String, dynamic>` в
Dart. Для них ещё нужны точные codecs и contract tests.

Это незавершённая часть самого первого roadmap-пункта про типизированный bridge.

### P1 — два крупных центра ответственности

`runner.ts` всё ещё объединяет protocol facade, управление активной моделью
и содержимое кадра, хотя теперь целиком входит в строгую проверку TypeScript.
`VrmController` одновременно валидирует
данные, управляет hosted resources, сериализует protocol payload и предоставляет
публичный API. Любое изменение затрагивает слишком большой контекст.

### P1 — recovery state распределён между несколькими владельцами

Камера и конфигурация восстанавливаются через `VrmView`/`VrmController`,
очередь — самостоятельно, а защищённая модель — через повторный
`VrmView.onCreated` в приложении. Эта семантика разумна, но пока не описана как
единая таблица ownership/replay order и потому уязвима при добавлении новых
состояний.

### P1 — интеграционные проверки недостаточно изолированы

Smoke-тест покрывает много важных сценариев, но является одним большим тестом.
Сбой позднего шага затрудняет локализацию. Физический Android не запускается в
GitHub Actions; Windows smoke запускается. Нужны отдельные contract/race/soak
сценарии, при этом физический Android остаётся release gate.

### P2 — публикационная готовность отложена

В `pubspec.yaml` установлен `publish_to: none`. Это соответствует принятому
решению. Проверки package metadata, generated API docs и release checklist не
являются текущим блокером и не должны отвлекать от стабилизации runtime.

## 5. Текущее направление

Ближайшее направление: **типизированное и модульное ядро runtime без расширения
публичного API**.

Сейчас не следует:

- обновлять Three.js/three-vrm без отдельной причины;
- добавлять новые эффекты или ещё один способ управления моделью;
- начинать публикацию;
- менять protocol v3 только ради рефакторинга;
- одновременно переделывать lifecycle, motion и speech semantics.

Сначала нужно уменьшить риск уже реализованного функционала.

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
context loss. Следующий gate — повтор на втором низкопроизводительном
Android-устройстве.

Критерий готовности: документированный профиль нагрузки и отсутствие
неограниченного роста ресурсов в длительных сценариях.

### Stage 29 — тестовая матрица и документация API

Цель: превратить существующие гарантии в повторяемые release gates.

Работы:

- разбить монолитный smoke-тест на независимые сценарии;
- добавить race tests для replacement/cancel/reload;
- добавить authenticated bytes и external-resource glTF integration cases;
- документировать ошибки, ownership, transition и speech semantics;
- добавить минимальные примеры для каждого высокоуровневого блока API.

Текущий прогресс: монолитный `runtime_smoke_test.dart` разделён на независимые
runtime/scene, motion/speech и lifecycle/recovery gates с общим harness. Все три
сценария отдельно прошли на physical Android 16 и Windows WebView2. Каноническая
матрица добавлена в `docs/TEST_MATRIX.md`. Следующий срез — replacement/cancel/
reload race tests на model-session и transport границах.

### Stage 30 — подготовка публикации

Статус: отложено до отдельного решения.

Включает GitHub metadata, package metadata, API docs, versioning policy,
release checklist, clean-clone verification и окончательный аудит лицензий.

## 7. Правила обновления roadmap

- После этапа обновлять его статус и добавлять commit hash.
- Новая функция должна быть привязана к требованию или измеримой проблеме.
- Breaking wire change требует новой protocol version.
- Generated runtime не редактируется вручную.
- Изменения поведения проверяются минимум unit/contract тестом; lifecycle,
  loading, rendering и disposal — также smoke-тестом на затронутой платформе.
- Публикационные задачи остаются отложенными, пока это явно не изменено.
