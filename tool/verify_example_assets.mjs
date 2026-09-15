import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import { dirname, extname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const toolDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryDirectory = resolve(toolDirectory, '..');

const approvedAssets = new Map([
  [
    'example/assets/vrm/sample.vrm',
    {
      sha256: '12c2b97e95e700783a6a550dc0eee2d7880aeedccef9ae67bc4c5a2f0f2631a2',
      source:
        'https://github.com/pixiv/three-vrm/blob/1b4fc0cc7ef39a49d62bb7a66dcfeca8f65316f7/packages/three-vrm/examples/models/VRM1_Constraint_Twist_Sample.vrm',
      requireRedistributionPermission: true,
    },
  ],
  [
    'example/assets/vrma/sample.vrma',
    {
      sha256: '38d0fd12d61e896f1a970b5e358ebb41a96c8d5ee8e284496ea18f0ba1f04e7b',
      source:
        'https://github.com/pixiv/three-vrm/blob/1b4fc0cc7ef39a49d62bb7a66dcfeca8f65316f7/packages/three-vrm-animation/examples/models/test.vrma',
      requireRedistributionPermission: false,
    },
  ],
]);

const controlledExtensions = new Set(['.vrm', '.vrma', '.vroid']);

async function collectControlledAssets(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const assets = [];
  for (const entry of entries) {
    const absolutePath = resolve(directory, entry.name);
    if (entry.isDirectory()) {
      assets.push(...(await collectControlledAssets(absolutePath)));
    } else if (controlledExtensions.has(extname(entry.name).toLowerCase())) {
      assets.push(absolutePath);
    }
  }
  return assets;
}

function repositoryPath(absolutePath) {
  return absolutePath
    .slice(repositoryDirectory.length + 1)
    .replaceAll('\\', '/');
}

function readGlbJson(bytes, assetPath) {
  if (bytes.length < 20 || bytes.toString('ascii', 0, 4) !== 'glTF') {
    throw new Error(`${assetPath} is not a binary glTF document.`);
  }
  let offset = 12;
  while (offset + 8 <= bytes.length) {
    const length = bytes.readUInt32LE(offset);
    const type = bytes.toString('ascii', offset + 4, offset + 8);
    const end = offset + 8 + length;
    if (end > bytes.length) {
      throw new Error(`${assetPath} contains a truncated GLB chunk.`);
    }
    if (type === 'JSON') {
      return JSON.parse(bytes.toString('utf8', offset + 8, end).replace(/\0+$/, ''));
    }
    offset = end;
  }
  throw new Error(`${assetPath} does not contain a JSON chunk.`);
}

const discoveredAssets = await collectControlledAssets(
  resolve(repositoryDirectory, 'example/assets'),
);
const discoveredPaths = discoveredAssets.map(repositoryPath).sort();
const approvedPaths = [...approvedAssets.keys()].sort();
if (JSON.stringify(discoveredPaths) !== JSON.stringify(approvedPaths)) {
  throw new Error(
    `Example asset allowlist mismatch.\nDiscovered: ${discoveredPaths.join(', ')}\n` +
      `Approved: ${approvedPaths.join(', ')}`,
  );
}

for (const [assetPath, approval] of approvedAssets) {
  const bytes = await readFile(resolve(repositoryDirectory, assetPath));
  const actualSha256 = createHash('sha256').update(bytes).digest('hex');
  if (actualSha256 !== approval.sha256) {
    throw new Error(
      `${assetPath} checksum changed. Review its license and update the approval explicitly.`,
    );
  }

  if (approval.requireRedistributionPermission) {
    const json = readGlbJson(bytes, assetPath);
    const meta = json.extensions?.VRMC_vrm?.meta;
    if (meta?.allowRedistribution !== true) {
      throw new Error(`${assetPath} does not permit redistribution in VRM metadata.`);
    }
  }
  console.log(`Verified ${assetPath}\n  source: ${approval.source}`);
}
