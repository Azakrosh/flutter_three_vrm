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
- устойчивое среднее FPS превышает cap больше чем на допустимую погрешность
  telemetry (отдельное окно может кратковременно выйти выше cap);
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
baseline. Для сравнения устройств сохраняйте всю строку `runtime_soak` и
используйте одну и ту же модель, длительность и build mode.

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
