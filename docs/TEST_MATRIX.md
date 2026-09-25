# Test matrix

Матрица разделяет быстрые unit/contract проверки и физические WebView gates.
Каждый integration-сценарий запускается отдельно, поэтому ошибка lifecycle не
скрывает результат motion/speech или базовой загрузки модели.

## Автоматические проверки

| Область | Команда | Назначение |
|---|---|---|
| Dart API | `flutter test` | Валидация моделей, controller state, replay, queue и ownership |
| Dart analyzer | `flutter analyze` | Публичный пакет и production Dart-код |
| Example analyzer | `flutter analyze example` | Example и integration entrypoints |
| Web runtime | `corepack pnpm test` | Runtime controllers, codecs, loaders и protocol behavior |
| TypeScript | `corepack pnpm typecheck` | Строгий runtime contract |
| Protocol | `corepack pnpm verify:contract` | Совпадение команд и событий protocol v3 |
| Embedded bundle | `corepack pnpm build && corepack pnpm verify:build` | Воспроизводимый bundle и checksum manifest |

Команды `pnpm` выполняются из каталога `web`.

## Integration gates

| Сценарий | Android | Windows | Покрытие |
|---|---:|---:|---|
| `runtime_smoke_test.dart` | обязательно | обязательно | Runtime health, model report, background, renderer recreation, camera, wind/physics и pointer contract |
| `motion_speech_test.dart` | обязательно | обязательно | VRMA → Pose, Pose → Pose, Pose → VRMA, reset, finite playback, viseme/amplitude speech и stale session |
| `runtime_recovery_test.dart` | обязательно | обязательно | Platform lifecycle, reload во время inactive/hidden, model replay и camera restoration |
| `runtime_race_test.dart` | обязательно | обязательно | Model replacement, explicit cancel и reload с незавершённой загрузкой |
| `resource_loading_test.dart` | обязательно | обязательно | Authenticated VRM bytes и external-resource glTF byte bundle |
| `performance_soak_test.dart` | обязательно | не применяется | FPS/pixel ratio, resource baseline, context loss и длительный speech/motion soak |

Пример запуска одного сценария:

```powershell
cd example
flutter test integration_test/runtime_smoke_test.dart -d <device-id>
```

Полная cross-platform matrix запускается одной командой из корня пакета:

```powershell
.\tool\run_integration_matrix.ps1 -AndroidDeviceId <device-id>
```

Для локального Windows-only прогона используйте `-SkipAndroid`; быстрый Android
прогон без двадцатисекундного soak — `-SkipPerformance -SkipWindows`.

Параметры быстрого и пятиминутного performance gate описаны в
[`PERFORMANCE_TESTING.md`](PERFORMANCE_TESTING.md).
Подготовленный physical low-end pre-release gate для Firebase Test Lab описан в
[`FIREBASE_TEST_LAB.md`](FIREBASE_TEST_LAB.md).

## Подтверждённая матрица

25 сентября 2026 года независимые runtime, motion/speech, recovery, model-race
и resource-loading gates прошли на:

- moto g55 5G, Android 16 (API 36), Android System WebView, WebGL 2;
- Windows 10 x64, WebView2, WebGL 2.

Android integration harness не передаёт синтетический `WidgetTester.tapAt` в
native PlatformView. Pointer path поэтому проверяется web unit-тестом и Windows
end-to-end gate; реальные Android gestures передаются WebView через
`EagerGestureRecognizer`.

Model-race gate проверяет, что при конкурентной замене побеждает последняя
загрузка, explicit cancel завершает активный запрос с `canceled`, а reload
инвалидирует старый запрос и восстанавливает модель. Gate также защищает от
быстрого error-response до подписки вызывающего кода на Future команды.

Resource-loading gate читает локальный VRM как результат Flutter API-клиента и
передаёт его через `loadModelFromBytes()`. Затем он создаёт детерминированный
glTF JSON + отдельный `buffers/motion.bin`, проверяя bundle routing, parsing,
humanoid retargeting и finite playback без стороннего animation asset в Git.

## Локальные assets

Integration gates требуют `example/assets/vrm/sample.vrm` и
`example/assets/vrma/sample.vrma`. Перед коммитом или публикацией необходимо
проверить право на распространение каждого файла. Тестовая матрица не является
разрешением включать сторонний avatar в Git.

## Статус Stage 29

Все запланированные gates реализованы. Error, ownership, transition и speech
semantics вместе с минимальными API-рецептами зафиксированы в
[`API_SEMANTICS.md`](API_SEMANTICS.md).
