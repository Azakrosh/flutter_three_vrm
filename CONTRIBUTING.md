# Участие в разработке

Спасибо за интерес к `flutter_three_vrm`. Пакет находится в prerelease-стадии и
ориентирован на один VRM-аватар в Flutter-приложениях для Android и Windows.

## Среда разработки

- Flutter `3.47.1` (stable) и Dart из этого SDK;
- Node.js `24`;
- pnpm `10.33.0` через Corepack;
- Microsoft Edge WebView2 Runtime для запуска Windows example;
- Android SDK и актуальный Android System WebView для Android.

Установите зависимости из корня репозитория:

```bash
flutter pub get
cd web
corepack pnpm install --frozen-lockfile
```

## Перед отправкой pull request

В корне репозитория выполните:

```bash
node tool/verify_example_assets.mjs
node tool/verify_public_docs.mjs
flutter analyze
flutter test
```

Для изменений web-runtime дополнительно выполните:

```bash
cd web
corepack pnpm typecheck
corepack pnpm test
corepack pnpm verify:contract
corepack pnpm build
corepack pnpm verify:build
cd ..
git diff --exit-code -- assets/web/dist
```

`assets/web/dist/vrm-runtime.js` и `manifest.json` генерируются из `web/src`.
Не редактируйте их вручную; после изменения runtime пересоберите bundle и
закоммитьте исходники и результат одной логической правкой.

Изменения lifecycle, загрузки ресурсов, rendering или disposal должны быть
проверены подходящим integration gate на затронутой платформе. Матрица и команды
описаны в [`docs/TEST_MATRIX.md`](docs/TEST_MATRIX.md).

## Правила pull request

- Один pull request должен решать одну воспроизводимую проблему или задачу.
- Для изменения поведения добавьте unit/contract test и обновите документацию.
- Breaking wire change требует новой версии bridge protocol.
- Не добавляйте токены, ключи, cookie или пользовательские VRM/VRMA.
- Новый example-asset допустим только при подтверждённом праве на
  перераспространение, указанной лицензии и зафиксированной контрольной сумме.
- Авторизационные данные должны оставаться на стороне Flutter; не передавайте их
  в JavaScript/WebView.

Сообщение об уязвимости отправляйте по правилам из [`SECURITY.md`](SECURITY.md),
а не через публичный issue.
