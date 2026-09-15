import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const webDirectory = resolve(scriptDirectory, "..");
const repositoryDirectory = resolve(webDirectory, "..");
const outputDirectory = resolve(repositoryDirectory, "assets/web/dist");
const packageJson = JSON.parse(
  await readFile(resolve(webDirectory, "package.json"), "utf8"),
);
const manifest = JSON.parse(
  await readFile(resolve(outputDirectory, "manifest.json"), "utf8"),
);

assert.equal(manifest.schemaVersion, 1, "Unexpected manifest schema version");
assert.equal(manifest.runtimeVersion, packageJson.version);
assert.equal(manifest.protocolVersion, 1);
assert.equal(manifest.entrypoint, "vrm-runtime.js");
assert.deepEqual(manifest.dependencies, packageJson.dependencies);

const bundle = await readFile(resolve(outputDirectory, manifest.entrypoint));
assert.equal(manifest.bytes, bundle.byteLength, "Runtime byte size mismatch");
assert.equal(
  manifest.sha256,
  createHash("sha256").update(bundle).digest("hex"),
  "Runtime SHA-256 mismatch",
);

const generatedFiles = (await readdir(outputDirectory)).sort();
assert.deepEqual(
  generatedFiles,
  ["manifest.json", "vrm-runtime.js"],
  "Unexpected generated runtime artifacts",
);

const indexHtml = await readFile(
  resolve(repositoryDirectory, "assets/web/index.html"),
  "utf8",
);
const scripts = [...indexHtml.matchAll(/<script\s+src="([^"]+)"/g)].map(
  (match) => match[1],
);
assert.deepEqual(
  scripts,
  [`dist/${manifest.entrypoint}`],
  "index.html must load exactly the checksummed runtime bundle",
);

console.log(
  `Verified ${manifest.entrypoint} (${manifest.bytes} bytes, ${manifest.sha256}).`,
);
