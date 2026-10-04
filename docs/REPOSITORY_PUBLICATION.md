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
- Полный локальный clean-clone gate прошёл 2026-10-03 на Windows; Flutter и web
  suites завершились успешно, а повторная генерация не изменила worktree.

## Решения владельца до первого push

Решения приняты 2026-10-04: репозиторий —
`https://github.com/Azakrosh/flutter_three_vrm`, основная ветка — `main`, все
локальные author/committer identities переписываются на GitHub noreply
`33670184+Azakrosh@users.noreply.github.com`.

## Первый push

Публичный GitHub-репозиторий был заранее создан с одним Initial commit. Его
история получена как `origin/main` и сохранена вторым родителем локального merge,
поэтому первый push будет fast-forward и не потребует `--force`:

```bash
git push -u origin main
```

Remote настроен на `https://github.com/Azakrosh/flutter_three_vrm.git`. Первый
fast-forward push выполнен 2026-10-04: локальная и удалённая `main` совпали на
`bc38ffa`. GitHub Actions run `37183478503` завершился успешно для `quality` и
`windows` jobs.

## Настройки GitHub после push

- дождаться успешных Ubuntu и Windows jobs в GitHub Actions;
- назначить основную ветку и включить branch protection/ruleset с обязательным
  CI и pull request review;
- включить Private vulnerability reporting, secret scanning и push protection,
  если они доступны для репозитория;
- включить Dependabot alerts и security updates;
- проверить описание, topics и ссылку на лицензию на главной странице;
- не включать GitHub Pages: пакет не требует публичного web-hosting.

## Фактическая конфигурация GitHub

Проверено 2026-10-04 через GitHub API:

- `main` требует успешные checks `quality` и `windows`, актуальность относительно
  base branch и разрешение review conversations;
- force-push и удаление `main` запрещены; admin bypass сохранён для аварийного
  обслуживания единственного владельца;
- разрешён только squash merge, включены auto-merge и удаление merged branches;
- Actions используют read-only token и не могут подтверждать pull requests;
- включены Dependabot alerts/security updates, standard secret scanning, push
  protection и Private vulnerability reporting;
- расширенные non-provider patterns и validity checks остались недоступны;
- wiki и projects отключены, issues оставлены включёнными;
- `.github/CODEOWNERS` назначает `@Azakrosh`, а `.github/dependabot.yml` еженедельно
  проверяет root Flutter package, example, web-runtime и GitHub Actions.
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
