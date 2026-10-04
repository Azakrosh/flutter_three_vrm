import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const consumerSource = `import 'package:flutter_three_vrm/flutter_three_vrm.dart';

VrmController? controller;
VrmView? view;
VrmPose? pose;
VrmTransform? transform;
VrmAnimationQueue? animationQueue;

void main() {
  final publicValues = <Object?>[
    controller,
    view,
    pose,
    transform,
    animationQueue,
  ];
  assert(publicValues.length == 5);
}
`;

const options = parseArguments(process.argv.slice(2));
const consumerDirectory = await mkdtemp(
  join(tmpdir(), 'flutter-three-vrm-consumer-'),
);

try {
  await mkdir(join(consumerDirectory, 'lib'));
  await writeFile(
    join(consumerDirectory, 'pubspec.yaml'),
    buildPubspec(options.repository, options.ref),
    'utf8',
  );
  await writeFile(
    join(consumerDirectory, 'lib', 'main.dart'),
    consumerSource,
    'utf8',
  );

  await runFlutter(['pub', 'get'], consumerDirectory);
  await runFlutter(
    ['analyze', '--fatal-infos', 'lib/main.dart'],
    consumerDirectory,
  );

  console.log(
    `Verified Git consumer for ${options.repository} at ${options.ref}.`,
  );
} finally {
  if (!options.keep) {
    await rm(consumerDirectory, { recursive: true, force: true });
  } else {
    console.log(`Consumer fixture retained at ${consumerDirectory}.`);
  }
}

function parseArguments(args) {
  const values = new Map();
  let keep = false;
  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === '--keep') {
      keep = true;
      continue;
    }
    if (argument !== '--repository' && argument !== '--ref') {
      throw new Error(`Unknown argument: ${argument}`);
    }
    const value = args[index + 1];
    if (value == null || value.length === 0) {
      throw new Error(`Missing value for ${argument}.`);
    }
    values.set(argument, value);
    index += 1;
  }

  const repository = values.get('--repository');
  const ref = values.get('--ref');
  if (repository == null || ref == null) {
    throw new Error(
      'Usage: node tool/verify_git_consumer.mjs --repository <url-or-path> --ref <commit> [--keep]',
    );
  }
  return { repository, ref, keep };
}

function buildPubspec(repository, ref) {
  return `name: flutter_three_vrm_consumer_probe
publish_to: none
environment:
  sdk: ">=3.12.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
  flutter_three_vrm:
    git:
      url: ${JSON.stringify(resolveRepository(repository))}
      ref: ${JSON.stringify(ref)}
`;
}

function resolveRepository(repository) {
  if (/^[a-z][a-z0-9+.-]*:\/\//iu.test(repository)) {
    return repository;
  }
  return resolve(repository);
}

function runFlutter(args, cwd) {
  if (process.platform === 'win32') {
    return run(
      process.env.ComSpec ?? 'cmd.exe',
      ['/d', '/c', `flutter ${args.join(' ')}`],
      cwd,
    );
  }
  return run('flutter', args, cwd);
}

function run(executable, args, cwd) {
  return new Promise((resolvePromise, rejectPromise) => {
    const child = spawn(executable, args, {
      cwd,
      stdio: 'inherit',
    });
    child.once('error', rejectPromise);
    child.once('exit', (code, signal) => {
      if (code === 0) {
        resolvePromise();
        return;
      }
      rejectPromise(
        new Error(
          `${executable} ${args.join(' ')} failed with code ${String(code)}${
            signal == null ? '' : ` and signal ${signal}`
          }.`,
        ),
      );
    });
  });
}
