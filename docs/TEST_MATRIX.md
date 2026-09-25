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
| `performance_soak_test.dart` | обязательно | не применяется | FPS/pixel ratio, resource baseline, context loss и длительный speech/motion soak |

Пример запуска одного сценария:

```powershell
cd example
flutter test integration_test/runtime_smoke_test.dart -d <device-id>
```

Параметры быстрого и пятиминутного performance gate описаны в
[`PERFORMANCE_TESTING.md`](PERFORMANCE_TESTING.md).

## Подтверждённая матрица

25 сентября 2026 года независимые runtime, motion/speech и recovery gates
прошли на:

- moto g55 5G, Android 16 (API 36), Android System WebView, WebGL 2;
- Windows 10 x64, WebView2, WebGL 2.

Android integration harness не передаёт синтетический `WidgetTester.tapAt` в
native PlatformView. Pointer path поэтому проверяется web unit-тестом и Windows
end-to-end gate; реальные Android gestures передаются WebView через
`EagerGestureRecognizer`.

## Локальные assets

Integration gates требуют `example/assets/vrm/sample.vrm` и
`example/assets/vrma/sample.vrma`. Перед коммитом или публикацией необходимо
проверить право на распространение каждого файла. Тестовая матрица не является
разрешением включать сторонний avatar в Git.

## Следующие gates Stage 29

- replacement/cancel/reload race на transport и model-session границах;
- authenticated model bytes без передачи credentials в WebView;
- glTF с явным external-resource bundle;
- повторяемая команда запуска всей platform matrix.
