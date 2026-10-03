# Публикация GitHub-репозитория

Этот документ относится к публикации исходного репозитория. Публикация пакета на
pub.dev пока не выполняется: в `pubspec.yaml` сохраняется `publish_to: none`.

## Уже проверено

- В достижимой Git-истории не найдено секретов или закрытых VRM/VRMA.
- Единственные модели в истории — лицензированные example-assets, перечисленные
  в `THIRD_PARTY_NOTICES.md` и проверяемые по checksum в CI.
- Максимальный достижимый blob меньше ограничения GitHub в 100 MiB; Git LFS для
  текущего содержимого не требуется.
- `LICENSE`, `THIRD_PARTY_NOTICES.md`, CI, contribution policy, security policy и
  GitHub templates находятся в репозитории.
- Локальные dangling objects не передаются обычным `git push`; очистка object
  database не является условием публикации.

## Решения владельца до первого push

1. Выбрать GitHub owner и окончательное имя репозитория.
2. Решить, допустима ли публикация email авторов из существующих commit metadata.
   Переписывание авторов меняет SHA всей затронутой истории и выполняется только
   до первого публичного push.
3. Заменить `github.com/OWNER/flutter_three_vrm.git` в README на окончательный URL.
4. Решить, переименовывать ли локальную ветку `master` в `main`.

## Первый push

Создайте пустой GitHub-репозиторий без автоматически добавленных README,
`.gitignore` и LICENSE. Затем из локального репозитория:

```bash
git remote add origin <repository-url>
git push -u origin <branch>
```

Не добавляйте remote и не выполняйте push, пока URL и политика email не
подтверждены.

## Настройки GitHub после push

- дождаться успешных Ubuntu и Windows jobs в GitHub Actions;
- назначить основную ветку и включить branch protection/ruleset с обязательным
  CI и pull request review;
- включить Private vulnerability reporting, secret scanning и push protection,
  если они доступны для репозитория;
- включить Dependabot alerts и security updates;
- проверить описание, topics и ссылку на лицензию на главной странице;
- не включать GitHub Pages: пакет не требует публичного web-hosting.

## Проверка чистого клона

До тега клонируйте репозиторий в новый каталог и выполните:

```bash
flutter pub get
node tool/verify_example_assets.mjs
node tool/verify_public_docs.mjs
flutter analyze
flutter test
cd web
corepack pnpm install --frozen-lockfile
corepack pnpm typecheck
corepack pnpm test
corepack pnpm verify:contract
corepack pnpm build
corepack pnpm verify:build
```

После сборки `git status --short` должен быть пустым, а
`git diff --exit-code -- assets/web/dist` — завершиться успешно.

## Первый prerelease

Тег `v0.2.0-dev.1` создаётся только после успешного CI публичного commit и
clean-clone verification. GitHub Release следует отметить как pre-release и
кратко перечислить поддерживаемые платформы и известную несовместимость с
`0.1.x`. Создание тега не означает публикацию на pub.dev.
