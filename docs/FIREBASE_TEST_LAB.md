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

Каждый из трёх прогонов должен удовлетворять строгим инвариантам теста:

- `contextLossCount == 0`;
- нет runtime errors;
- renderer textures возвращаются к baseline после каждого unload;
- нет накопительного роста texture count или estimated texture memory;
- все загрузки завершаются;
- pixel ratio остаётся в заданном диапазоне;
- `frameTimeP50Ms <= frameTimeP95Ms`.

FPS, frame-time percentiles и model load time сохраняются как профиль, но не
сравниваются с универсальным абсолютным порогом. Для облачного железа важны три
согласованных запуска и отсутствие накопительного ухудшения, а не единичный
минимум FPS.

## Результат low-end gate

После выполнения добавьте сюда:

- дату;
- Firebase `model-id`, устройство, Android/API и WebView;
- параметры duration/load cycles и количество повторов;
- три строки `runtime_soak`;
- ссылки или matrix IDs;
- итог pass/fail и найденные отклонения.

До этого момента Stage 28 считается подтверждённым на основном moto g55 и
готовым к внешнему low-end pre-release gate, но не заявляет пройденную low-end
валидацию.
