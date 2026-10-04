import { access, readdir, readFile } from 'node:fs/promises';
import { dirname, extname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const toolDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryDirectory = resolve(toolDirectory, '..');
const tick = String.fromCharCode(96);

const normalizeText = (content) =>
  content.split(String.fromCharCode(13)).join('');
const readRepositoryFile = async (path) =>
  normalizeText(await readFile(resolve(repositoryDirectory, path), 'utf8'));

const [pubspec, readme, publicLibrary, controller, workflow, webPackageSource] =
  await Promise.all([
    readRepositoryFile('pubspec.yaml'),
    readRepositoryFile('README.md'),
    readRepositoryFile('lib/flutter_three_vrm.dart'),
    readRepositoryFile('lib/src/vrm_controller.dart'),
    readRepositoryFile('.github/workflows/ci.yml'),
    readRepositoryFile('web/package.json'),
  ]);

const packageVersion = requireMatch(
  pubspec,
  /^version:\s*(\S+)\s*$/m,
  'pubspec package version',
);
const webPackage = JSON.parse(webPackageSource);
const repositoryUrl = 'https://github.com/Azakrosh/flutter_three_vrm';

assertContains(
  pubspec,
  'repository: ' + repositoryUrl,
  'pubspec repository URL',
);
assertContains(
  pubspec,
  'issue_tracker: ' + repositoryUrl + '/issues',
  'pubspec issue tracker URL',
);
assertContains(
  readme,
  'url: ' + repositoryUrl + '.git',
  'README Git dependency URL',
);
assertAbsent(readme, /github\.com\/OWNER\//, 'placeholder GitHub owner');

assertEqual(
  webPackage.version,
  packageVersion,
  'Flutter and web-runtime package versions',
);
assertContains(
  readme,
  'Версия ' + tick + packageVersion + tick,
  'README package version',
);

for (const dependency of [
  'three',
  '@pixiv/three-vrm',
  '@pixiv/three-vrm-animation',
]) {
  const version = webPackage.dependencies?.[dependency];
  if (typeof version !== 'string' || version.length === 0) {
    throw new Error('Missing pinned web dependency: ' + dependency + '.');
  }
  assertContains(
    readme,
    tick + dependency + ' ' + version + tick,
    'README dependency version for ' + dependency,
  );
}

const publicSources = await collectDartSources(
  resolve(repositoryDirectory, 'lib'),
);
const joinedPublicSources = publicSources.join('\n');
assertAbsent(
  joinedPublicSources,
  /\b(?:class|enum|typedef)\s+VrmCameraPreset\b/,
  'removed VrmCameraPreset declaration',
);
assertAbsent(
  joinedPublicSources,
  /\bsetCameraPreset\s*\(/,
  'removed setCameraPreset method',
);
assertContains(
  readme,
  tick +
    'VrmCameraPreset' +
    tick +
    ' и ' +
    tick +
    'setCameraPreset()' +
    tick +
    ' не являются частью API.',
  'README removed camera-preset contract',
);
assertContains(
  readme,
  tick + "VrmRuntimeException(code: 'canceled')" + tick,
  'README typed reload cancellation',
);
assertContains(
  readme,
  'ожидаемая отмена\nфоновой latest-value команды не публикуется в ' +
    tick +
    'onError' +
    tick,
  'README background cancellation diagnostics',
);

for (const documentPath of [
  '.github/CODEOWNERS',
  '.github/dependabot.yml',
  'CONTRIBUTING.md',
  'SECURITY.md',
  'docs/REPOSITORY_PUBLICATION.md',
  'docs/ROADMAP.md',
  'docs/API_SEMANTICS.md',
  'docs/STATE_OWNERSHIP.md',
  'docs/TEST_MATRIX.md',
]) {
  await access(resolve(repositoryDirectory, documentPath));
}
for (const link of [
  '[`CONTRIBUTING.md`](CONTRIBUTING.md)',
  '[`SECURITY.md`](SECURITY.md)',
  '[`docs/REPOSITORY_PUBLICATION.md`](docs/REPOSITORY_PUBLICATION.md)',
  '[`docs/ROADMAP.md`](docs/ROADMAP.md)',
  '[`docs/API_SEMANTICS.md`](docs/API_SEMANTICS.md)',
  '[`docs/TEST_MATRIX.md`](docs/TEST_MATRIX.md)',
]) {
  assertContains(readme, link, 'README documentation link');
}

assertContains(
  publicLibrary,
  'High-level Flutter API for displaying and controlling one VRM avatar',
  'public library overview',
);
assertContains(
  readme,
  'actions/workflows/ci.yml/badge.svg?branch=main',
  'README CI badge',
);
assertContains(
  workflow,
  'node tool/verify_public_docs.mjs',
  'CI public-documentation verifier',
);
assertContains(
  workflow,
  'dart doc --dry-run .',
  'CI dartdoc gate',
);
assertContains(
  workflow,
  'node tool/verify_git_consumer.mjs',
  'CI Git consumer boundary gate',
);
assertContains(
  workflow,
  'flutter build appbundle --release',
  'CI Android release build gate',
);
assertContains(
  workflow,
  'flutter build windows --release',
  'CI Windows release build gate',
);
await access(resolve(repositoryDirectory, 'tool/verify_git_consumer.mjs'));
assertContains(
  controller,
  'VrmRuntimeException(code: ' + "'canceled'" + ')',
  'controller typed cancellation documentation',
);

console.log(
  'Verified public documentation contract for flutter_three_vrm ' +
    packageVersion +
    ' and pinned Three.js dependencies.',
);

async function collectDartSources(directory) {
  const sources = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const absolutePath = resolve(directory, entry.name);
    if (entry.isDirectory()) {
      sources.push(...(await collectDartSources(absolutePath)));
    } else if (entry.isFile() && extname(entry.name) === '.dart') {
      sources.push(normalizeText(await readFile(absolutePath, 'utf8')));
    }
  }
  return sources;
}

function requireMatch(content, pattern, label) {
  const match = content.match(pattern);
  if (match == null) {
    throw new Error('Missing ' + label + '.');
  }
  return match[1];
}

function assertContains(content, expected, label) {
  if (!content.includes(expected)) {
    throw new Error('Missing or stale ' + label + ': ' + expected);
  }
}

function assertAbsent(content, pattern, label) {
  if (pattern.test(content)) {
    throw new Error('Unexpected ' + label + '.');
  }
}

function assertEqual(actual, expected, label) {
  if (actual !== expected) {
    throw new Error(
      label + ' differ. Expected ' + expected + ', received ' + actual + '.',
    );
  }
}