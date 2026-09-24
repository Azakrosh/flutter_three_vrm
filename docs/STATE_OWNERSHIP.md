# State ownership and runtime recovery

Этот документ фиксирует контракт восстановления между Flutter-приложением,
пакетом и WebView runtime. Он является рабочим артефактом Stage 27.

## Владельцы состояния

| Состояние | Desired state | Applied state | Поведение после WebView reload |
|---|---|---|---|
| Lifecycle и `renderingEnabled` | `VrmView` + `VrmRenderLifecycleCoordinator` | Web runtime | Повторно синхронизируется первым шагом |
| Graphics preset и adaptive quality | параметры `VrmView` | Web runtime | Повторно применяются пакетом |
| Базовый цвет/transparent background | параметры `VrmView` | Web runtime | Повторно применяются пакетом |
| Background, заданный напрямую через controller | приложение | Web runtime | Не сохраняется; приложение повторяет команду в `onCreated` |
| `initialModelFolder`/`initialModelFile` | `VrmView` | Web runtime | Повторно загружается пакетом |
| Авторизованная/серверная модель | приложение | Web runtime | Приложение получает свежий token и загружает модель в `onCreated` |
| Camera pan/zoom | последний user-initiated transform в controller | Web runtime | Snapshot восстанавливается после загрузки модели, если пользователь не успел изменить камеру |
| Speech session и direct lip-sync input | текущая runtime-сессия | Web runtime | Отменяются; сервер/аудиоплеер начинает следующее сообщение как новую сессию |
| Одиночная VRMA/glTF/Pose операция | текущая runtime-сессия | Web runtime | Не replay-ится; незавершённый Future завершается ошибкой потери runtime |
| `VrmAnimationQueue` | приложение/объект очереди | Web runtime | Очередь сохраняет позицию и запускает текущий элемент после нового `modelLoaded` |
| Expressions, mood, wind, physics, lights | приложение | Web runtime | Неявно не сохраняются; при необходимости приложение повторяет их в `onCreated` после загрузки модели |

## Порядок replay

Каждая новая WebView-сессия получает generation token. Старый replay прекращается
после текущего асинхронного шага и не переходит к следующему.

1. Синхронизация lifecycle/render pause.
2. Graphics preset и adaptive quality.
3. Базовый background из `VrmView`.
4. Опциональная package-owned initial model.
5. `VrmView.onCreated`: app-owned модель и model-dependent state.
6. Восстановление camera snapshot после доступности модели.

Ошибка шага останавливает оставшийся replay и публикуется через error stream.
Dispose и reload инвалидируют generation, pending bridge-команды и transient
model/speech state.

## Lifecycle pause

Lifecycle pause останавливает только frame loop. Он не уничтожает desired state и
не является WebView reload. На Windows состояние `inactive` по platform-default
не ставит renderer на паузу; `hidden`, `paused` и `detached` ставят.

## Правило для публичного API

- Declarative параметры `VrmView` принадлежат пакету и replay-ятся.
- Controller-команды по умолчанию принадлежат одной runtime-сессии.
- Состояние, зависящее от модели или authorization token, восстанавливает
  приложение в `onCreated`.
- После `VrmController.dispose` все mutating API завершаются ошибкой и replay не
  запускается.

До завершения Stage 27 эта матрица должна быть дополнена contract-тестами для
гонок model load, animation transition и streaming speech.
