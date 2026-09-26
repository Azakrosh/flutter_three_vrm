# Android performance и soak-тестирование

`example/integration_test/performance_soak_test.dart` — повторяемый физический
тест нагрузки, а не синтетический benchmark. Он одновременно проверяет:

- циклы загрузки и выгрузки одной VRM-модели;
- освобождение renderer-текстур после `unloadModel()`;
- стабильность расчётной памяти текстур модели;
- отсутствие WebGL context loss;
- FPS cap, adaptive pixel ratio и frame-time p50/p95;
- непрерывный amplitude timeline вместе с плавными VRMA/Pose-переходами;
- отсутствие runtime-ошибок на всём интервале.

Начиная со Stage 31 тест разделяет две фазы:

- `runtime_soak_load` — model load/unload, parsing, GPU upload и disposal;
- `runtime_soak_steady` — устойчивый rendering со speech и VRMA/Pose-переходами.
- `runtime_soak_host` — RSS Flutter-процесса в начале и конце, RSS high-water
  mark, число memory-pressure событий и доступность thermal status.

Runtime сбрасывает frame timing после тяжёлых model/animation operations, поэтому
операционная пауза больше не считается одним длинным steady-state кадром и не
должна сама по себе понижать adaptive quality.

RSS охватывает Flutter-процесс и имеет платформозависимую семантику; отдельный
Android WebView renderer process и GPU allocations могут в него не входить.
Сравнивайте только прогоны одной сборки, модели, устройства и длительности.
Отрицательная `rssDeltaMiB` допустима после освобождения памяти. Пакет намеренно
не вводит pass/fail порог RSS и не реагирует автоматически на memory pressure.
На Android API 29+ `thermal` приходит из `PowerManager`; на Windows и более
старом Android он равен `unavailable`. Это явный fallback, а не показание
нормальной температуры.

## Запуск

Быстрый gate использует 20 секунд и три load/unload цикла:

```powershell
cd example
flutter test integration_test/performance_soak_test.dart -d <android-device>
```

Перед release используйте расширенный профиль, например пять минут и десять
циклов:

```powershell
flutter test integration_test/performance_soak_test.dart -d <android-device> `
  --dart-define=VRM_SOAK_SECONDS=300 `
  --dart-define=VRM_SOAK_LOAD_CYCLES=10
```

Тест требует локальные `assets/vrm/sample.vrm` и `assets/vrma/sample.vrma`.
Используйте только модели и анимации, которые разрешено хранить и запускать в
вашем окружении.

Подготовка instrumentation APK, выбор физического low-end устройства и запуск
через Firebase Test Lab описаны в
[`FIREBASE_TEST_LAB.md`](FIREBASE_TEST_LAB.md).

## Критерии

Тест не вводит лимиты на размер файла, полигоны или текстуры. Он падает, если:

- `contextLossCount` становится ненулевым;
- число renderer-текстур растёт более чем на одну между одинаковыми загрузками;
- после выгрузок texture baseline растёт более чем на одну;
- одинаковая модель даёт разные оценки texture memory;
- устойчивое среднее FPS в `runtime_soak_steady` превышает cap больше чем на
  20% (отдельное короткое telemetry-окно может кратковременно выйти выше cap);
- pixel ratio выходит за настроенный диапазон;
- нарушается `p50 <= p95` или runtime сообщает ошибку.

Абсолютные FPS и frame time печатаются как профиль устройства, но не являются
универсальным pass/fail порогом: тяжёлую модель пакет оценивает рекомендательно,
а нагрузкой управляют graphics preset и adaptive quality.

## Референсный Android-прогон

24 сентября 2026 года быстрый gate прошёл на moto g55 5G, Android 16 (API 36),
WebGL 2, debug integration build, preset `performance`:

| Метрика | Результат |
|---|---:|
| Длительность / load cycles | 20 s / 3 |
| Telemetry samples | 14 |
| FPS min–max / average | 26.4–32.8 / 29.5 |
| Max frame-time p50 / p95 | 34.1 ms / 114.2 ms |
| Pixel ratio | 1.00 |
| Renderer textures, loaded | 28 / 28 / 28 |
| Renderer textures, unloaded | 0 / 0 / 0 |
| Estimated model texture memory | 92.3 MiB |
| WebGL context losses | 0 |
| Model load time | 457.9 / 374.7 / 341.9 ms |

Минимальный FPS и высокий p95 включают стартовые загрузки VRMA и переключения
Pose, поэтому важнее отсутствие накопительного ухудшения и стабильный texture
baseline. Для сравнения устройств сохраняйте строки `runtime_soak_load` и
`runtime_soak_steady` и используйте одну и ту же модель, длительность и build
mode.

На том же устройстве расширенный gate `300 s / 10 load cycles` также прошёл:

| Метрика | Результат |
|---|---:|
| Telemetry samples | 158 |
| FPS min–max / average | 28.2–36.6 / 29.6 |
| Max frame-time p50 / p95 | 34.3 ms / 60.0 ms |
| Pixel ratio | 1.00 |
| Renderer textures, loaded / unloaded | 28 / 0 во всех 10 циклах |
| Estimated model texture memory | 92.3 MiB |
| WebGL context losses | 0 |
| Model load time min–max / average | 301.5–450.6 / 374.5 ms |

За пять минут выполнено около 600 streaming amplitude batches и 120 плановых
VRMA/Pose-переключений. Накопительного роста renderer resources не обнаружено.

## Stage 31: проверка фазовой телеметрии

26 сентября 2026 года короткий gate `20 s / 3 load cycles` повторён на том же
moto g55 5G после разделения operational и steady-state timing windows:

| Фаза | Samples | FPS average | Max p50 | Max p95 |
|---|---:|---:|---:|---:|
| Load/unload | 3 | профильная метрика не применяется | 34.0 ms | 69.3 ms |
| Steady rendering | 9 | 29.3 | 34.1 ms | 39.8 ms |

Steady FPS находился в диапазоне 28.6–29.4 при cap 30, pixel ratio оставался
1.0, renderer textures — 28/0 во всех трёх циклах. Model load занял
501.6/388.1/332.1 ms, финальная загрузка — 351.0 ms. Разрыв timing window после
model/animation operations устранил многосекундный percentile, наблюдавшийся в
старом смешанном Firebase-профиле, не скрывая реальные load durations.
