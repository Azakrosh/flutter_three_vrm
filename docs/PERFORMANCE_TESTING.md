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
- `runtime_soak_host` — RSS Flutter-процесса в начале и конце, sampled peak,
  нормализованный high-water mark, linear slope после первого warm-up цикла,
  число memory-pressure событий и доступность thermal status.

Runtime сбрасывает frame timing после тяжёлых model/animation operations, поэтому
операционная пауза больше не считается одним длинным steady-state кадром и не
должна сама по себе понижать adaptive quality.

Steady-строка также содержит количество и максимальную длительность long frames,
их наблюдаемый source, p95 CPU update/render submission и набор решений adaptive
quality. `externalScheduling` означает, что измеренные CPU-фазы не объясняют
интервал; сюда могут входить browser scheduler, compositor, GPU и ОС. Это не
утверждение о конкретном GPU bottleneck.

RSS охватывает Flutter-процесс и имеет платформозависимую семантику; отдельный
Android WebView renderer process и GPU allocations могут в него не входить.
Сравнивайте только прогоны одной сборки, модели, устройства и длительности.
Отрицательная `rssDeltaMiB` допустима после освобождения памяти. Пакет намеренно
не вводит pass/fail порог RSS и не реагирует автоматически на memory pressure.
`maxRssMiB` является монотонным максимумом platform max RSS и всех current RSS,
наблюдавшихся данным controller. `rssLoadedSlopeMiBPerCycle` и
`rssUnloadedSlopeMiBPerCycle` вычисляются методом наименьших квадратов после
исключения первого warm-up sample; это диагностический тренд, а не leak verdict.
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

После добавления source diagnostics тот же короткий профиль показал 2 long
frames из 267 steady samples, максимум 63.7 ms. CPU update p95 не превышал
6.0 ms, render submission p95 — 8.5 ms, поэтому source определён как
`externalScheduling`. Adaptive policy находилась в состояниях
`stable/collectingFast`, сохранив pixel ratio 1.0. Это профиль наблюдаемости, а
не универсальный порог для других устройств.

## Stage 32: нормализация host-memory тренда

27 сентября 2026 года новый формат `runtime_soak_host` проверен коротким
Firebase Test Lab gate `20 s / 3 load cycles` на Motorola moto g 5G (2022),
Android 13. Matrix `matrix-1wa37sfxsm6wy` завершился `Passed`:

- sampled current-RSS peak: 665.1 MiB;
- normalized max RSS: 673.0 MiB;
- loaded slope после warm-up: −50.37 MiB/cycle;
- unloaded slope после warm-up: −43.87 MiB/cycle;
- post-unload RSS: 518.2, 537.2, 513.4, 449.4 MiB;
- memory pressure: 4 события; thermal status: `none`;
- context loss и runtime errors отсутствуют.

Положительный общий start/end delta 149.2 MiB сам по себе не означает утечку:
он включает запуск Flutter/WebView и первую загрузку модели. Отрицательные slopes
после warm-up показывают, что на этом коротком прогоне sampled plateau снижался.
Leak-вывод требует нескольких полных прогонов одной сборки.

Два последовательных полных gate той же модели на Motorola moto g 5G (2022),
Android 13, выполнены одной сборкой `300 s / 10 load cycles`:

| Метрика | Run 1 | Run 2 |
|---|---:|---:|
| Matrix | `matrix-3l6i0j1vllm6n` | `matrix-2xv8kftf8kx2u` |
| Sampled RSS peak | 645.8 MiB | 632.8 MiB |
| Normalized max RSS | 655.5 MiB | 644.2 MiB |
| Loaded slope после warm-up | −5.62 MiB/cycle | −2.62 MiB/cycle |
| Unloaded slope после warm-up | −4.11 MiB/cycle | −0.91 MiB/cycle |
| Start/end RSS delta | +139.4 MiB | +198.3 MiB |
| Memory-pressure callbacks | 2 | 1 |
| Steady FPS average | 30.6 | 30.0 |

Оба прогона завершились без OOM, context loss и runtime errors; texture baseline
оставался 28/0 во всех десяти циклах. Положительный start/end delta отражает
начальный прогрев, тогда как отрицательные post-warm-up slopes и немонотонные
unloaded samples не показывают продолжающегося накопления RSS.

Для детерминированной проверки реакции на callback скрипт поддерживает
`-InjectMemoryPressure`. Флаг встраивает `VRM_SOAK_INJECT_MEMORY_PRESSURE=true` и
вызывает Flutter memory-pressure dispatch в середине steady-фазы. Тест требует,
чтобы после сигнала продолжились health polling, amplitude stream и
Pose/VRMA-переходы, модель осталась загруженной, а context loss — нулевым.

Physical recovery gate `matrix-36hq9syottrov` (`30 s / 3 cycles`) прошёл:
после инъекции выполнены 15 health checks, 30 amplitude batches и 6 motion
transitions; `modelLoadedAfterPressure=true`, `contextLossAfterPressure=0`.
Автоматическая выгрузка модели не нужна по текущим измерениям и не выполняется.
