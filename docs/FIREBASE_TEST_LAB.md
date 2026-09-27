# Firebase Test Lab low-end Android gate

Этот workflow запускает `performance_soak_test.dart` на физическом Android в
Firebase Test Lab. Он дополняет локальный moto g55 baseline и не использует
эмулятор как доказательство реальной GPU/WebGL-производительности.

Официальные инструкции:

- [Flutter integration tests в Firebase Test Lab](https://docs.flutter.dev/testing/integration-tests#test-in-firebase-test-lab-android);
- [Firebase Test Lab CLI](https://firebase.google.com/docs/test-lab/android/command-line);
- [квоты и стоимость](https://firebase.google.com/docs/test-lab/usage-quotas-pricing).

## Что подготовлено в проекте

- `AndroidJUnitRunner` и AndroidX instrumentation dependencies;
- `MainActivityTest` на базе Flutter `FlutterTestRunner`;
- `tool/run_firebase_soak.ps1`, который:
  - собирает ARM64 app APK с entrypoint `performance_soak_test.dart`;
  - передаёт duration/load cycles через base64 `dart-defines`;
  - собирает отдельный instrumentation APK;
  - печатает размер и SHA-256 обоих артефактов;
  - проверяет, что выбранная модель физическая, поддерживает требуемую версию
    Android и ABI `arm64-v8a`;
  - запускает от одного до пяти последовательных Test Lab matrix runs.

Credentials не читаются из файлов проекта и не передаются WebView. Скрипт
использует уже активный аккаунт Google Cloud CLI.

## Первичная настройка

1. Установите [Google Cloud CLI](https://cloud.google.com/sdk/docs/install).
2. Создайте или выберите Firebase/Google Cloud project.
3. Включите Cloud Testing API и Cloud Tool Results API.
4. Авторизуйтесь локально:

```powershell
gcloud auth login
gcloud config set project <project-id>
gcloud services enable testing.googleapis.com toolresults.googleapis.com
```

Для CI используйте отдельный service account или Workload Identity Federation.
Не сохраняйте JSON key в репозитории. Скрипт намеренно не меняет активный
аккаунт и не устанавливает project глобально: `ProjectId` передаётся каждому
запуску явно.

## Выбор устройства

Получите актуальный каталог, поскольку доступные модели и версии меняются:

```powershell
gcloud firebase test android models list `
  --filter="form=PHYSICAL" `
  --format="table(id,name,manufacturer,supportedVersionIds,supportedAbis,tags)"

gcloud firebase test android models describe <model-id> --format=json
```

Для low-end gate выбирайте физический ARM64-телефон с 3–4 ГБ RAM, бюджетным или
старым SoC и Android API 29–33. Предпочтительна модель с доступной capacity и без
deprecated tag. RAM/SoC сверяйте по спецификации производителя: Test Lab catalog
не обязан содержать аппаратную память.

Не закрепляйте случайную модель в репозитории до проверки актуального каталога.
Запишите выбранные `model-id`, Android version, WebView version и дату в раздел
результатов ниже.

## Локальная проверка артефактов

Команда ничего не отправляет в Google Cloud:

```powershell
.\tool\run_firebase_soak.ps1 `
  -BuildOnly `
  -SoakSeconds 300 `
  -LoadCycles 10
```

Ожидаемые файлы:

- `example/build/app/outputs/apk/debug/app-debug.apk`;
- `example/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk`.

Оба каталога находятся внутри ignored `example/build` и не должны попадать в
Git.

25 сентября 2026 года этот instrumentation path дополнительно проверен локально
через `connectedDebugAndroidTest` на moto g55: `FlutterTestRunner` выполнил
`profiles Android rendering and keeps resources bounded`, результат — один test,
ноль failures и ноль errors.

## Облачный запуск

Рекомендуемый pre-release gate — три пятиминутных запуска одной сборки:

```powershell
.\tool\run_firebase_soak.ps1 `
  -ProjectId <project-id> `
  -DeviceModel <physical-model-id> `
  -OsVersion <version-id> `
  -SoakSeconds 300 `
  -LoadCycles 10 `
  -RepeatCount 3
```

Для сравнения нескольких устройств на строго одной сборке сначала подготовьте
артефакты через `-BuildOnly`, затем повторно используйте их через `-SkipBuild`:

```powershell
.\tool\run_firebase_soak.ps1 -BuildOnly -SoakSeconds 300 -LoadCycles 10
.\tool\run_firebase_soak.ps1 `
  -SkipBuild `
  -ProjectId <project-id> `
  -DeviceModel <physical-model-id> `
  -OsVersion <version-id> `
  -SoakSeconds 300 `
  -LoadCycles 10 `
  -ResultsDirectory <result-label>
```

При `-SkipBuild` значения `-SoakSeconds` и `-LoadCycles` должны совпадать со
значениями сборки: этот режим не может изменить уже встроенные Dart defines.
Сверьте напечатанные SHA-256 перед каждым запуском.

Собственный results bucket необязателен. Если он нужен:

```powershell
.\tool\run_firebase_soak.ps1 `
  -ProjectId <project-id> `
  -DeviceModel <physical-model-id> `
  -OsVersion <version-id> `
  -ResultsBucket gs://<bucket> `
  -ResultsDirectory flutter-three-vrm-low-end `
  -RepeatCount 3
```

Каждый repeat получает отдельный suffix `-runN`. Скрипт останавливается при
первом failed matrix, поэтому успешное завершение означает, что все запрошенные
прогоны прошли.

## Критерии приёмки

В рекомендуемом тройном pre-release gate каждый прогон должен удовлетворять
строгим инвариантам теста:

- `contextLossCount == 0`;
- нет runtime errors;
- renderer textures возвращаются к baseline после каждого unload;
- нет накопительного роста texture count или estimated texture memory;
- все загрузки завершаются;
- pixel ratio остаётся в заданном диапазоне;
- `frameTimeP50Ms <= frameTimeP95Ms`.

FPS, frame-time percentiles и model load time сохраняются как профиль, но не
сравниваются с универсальным минимальным порогом. Средний steady-state FPS при
этом не должен превышать настроенный cap более чем на 20%: это проверяет сам
frame limiter, а не производительность устройства. Для облачного железа важны
три согласованных запуска и отсутствие накопительного ухудшения, а не единичный
минимум FPS.

## Результат low-end gate

25 сентября 2026 года gate выполнен на физическом Samsung Galaxy A03s
(`a03su`, Firebase capacity `LOW`), Android 13/API 33, ARM64, 720×1600 и Android
System WebView 106.0.5249.126.

Сначала пройден infrastructure smoke: 30 секунд, два load/unload цикла,
`matrix-3a60i6kr97quj`, один test case passed. Затем пройден полный gate:

- matrix: `matrix-1mjgm2x82h693`;
- параметры: 300 секунд, 10 load/unload циклов, timeout 15 минут;
- execution: 403 секунды, один test case, failures/errors/skipped — 0/0/0;
- 173 telemetry samples, FPS 0.2–39.3, среднее 30.1;
- maximum observed frame p50/p95 window: 5555/5555 ms во время тяжёлого
  load/unload окна; устойчивый средний FPS остался 30.1;
- pixel ratio: 1.0–1.0;
- renderer textures: `28,28,28,28,28,28,28,28,28,28` после load и
  `0,0,0,0,0,0,0,0,0,0` после unload;
- estimated model texture memory: 96,818,517 bytes (92.3 MiB);
- model loads: 1246.5–2557.4 ms, финальная загрузка после циклов — 1279.1 ms;
- `contextLossCount == 0`, runtime errors и накопительный resource drift не
  обнаружены;
- итог Firebase Test Lab: `Passed` / `SUCCESS`.

Результат доступен в [Firebase Console](https://console.firebase.google.com/project/flutteria-ef3c7/testlab/histories/bh.8c1f5d4b709a96df/matrices/5410733905587373434).
Этим первичная low-end валидация Stage 28 выполнена. Три повторных запуска
сохраняются как рекомендуемый pre-release regression gate, а не как условие
достоверности уже полученного профиля.

## Результат сопоставимого Stage 31 gate

27 сентября 2026 года одна сборка была проверена на двух физических ARM64
телефонах с Android 13/API 33 и экраном 720×1600:

- Samsung Galaxy A03s (`a03su`), WebView 106.0.5249.126;
- Motorola moto g 5G (2022) (`austin`), WebView 108.0.5359.128.

Параметры сборки: 300 секунд steady-state, 10 load/unload циклов, timeout 15
минут. App APK: SHA-256
`CEDBDE4A07593C18DEF62DBB7DBA15CB31E826CC5E98D784ABF35EDD8A833A84`;
instrumentation APK:
`8CF7C828CEBA3D79DFE90D66E2BABCA53CE2453821892E20465BD8DC464E83BA`.

Galaxy A03s, matrix `matrix-2pp9cf20xuynu`, `Passed`:

- steady FPS 27.9–31.4, среднее 30.1 при cap 30;
- frame p50/p95 не выше 37.3/71.5 ms;
- 602 long frames из 3664, максимум 77.4 ms, source
  `externalScheduling`; update/render p95 не выше 12.7/21.5 ms;
- adaptive pixel ratio 0.85–1.0; textures стабильно 28/0;
- sampled current RSS до 239.6 MiB, один memory-pressure callback,
  `thermal=none`.

Motorola, matrix `matrix-3j5zg3s0r91pw`, `Passed`:

- steady FPS 29.8–30.5, среднее 30.1 при cap 30;
- frame p50/p95 не выше 33.8/42.0 ms, long frames 0/3725;
- adaptive pixel ratio 1.0; textures стабильно 28/0;
- sampled current RSS до 664.5 MiB, post-unload samples стабилизировались около
  482.6–532.7 MiB без монотонного роста, 6 memory-pressure callbacks,
  `thermal=none`.

Перед итоговым прогоном Motorola matrix `matrix-3g3ir8vtxt843` обнаружил дефект:
среднее 37.1 FPS превышало допустимые 36 FPS при cap 30. Причина была в переносе
временной базы limiter после раннего vsync на 90-Гц дисплее. После исправления
регрессионный unit test и оба физических gate прошли. Infinix SMART 8 matrix
`matrix-2p65h4d1xcvtw` завершился `Internal System Error 3` до запуска приложения
и не использовался как результат пакета.

Полные результаты: [Galaxy A03s](https://console.firebase.google.com/project/flutteria-ef3c7/testlab/histories/bh.8c1f5d4b709a96df/matrices/7175066308969411909),
[Motorola moto g 5G (2022)](https://console.firebase.google.com/project/flutteria-ef3c7/testlab/histories/bh.8c1f5d4b709a96df/matrices/6982582576624081497).

Первый Stage 32 smoke нового RSS-формата выполнен на Motorola той же модели:
`matrix-1wa37sfxsm6wy`, 20 секунд, 3 load/unload цикла, `Passed`. App APK SHA-256
`8B9295254831EEFCE34551C552C1DB8BCB3FDD225F7DCF9B96ADAA2FA3547132`.
Отчёт показал sampled peak 665.1 MiB, normalized max 673.0 MiB и отрицательные
post-warm-up slopes −50.37/−43.87 MiB за цикл для loaded/unloaded samples.
[Результат в Firebase Console](https://console.firebase.google.com/project/flutteria-ef3c7/testlab/histories/bh.8c1f5d4b709a96df/matrices/8384152883712981631).
