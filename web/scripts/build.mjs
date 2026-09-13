import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { build } from "esbuild";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const webDirectory = resolve(scriptDirectory, "..");
const repositoryDirectory = resolve(webDirectory, "..");
const packageJson = JSON.parse(
  await readFile(resolve(webDirectory, "package.json"), "utf8"),
);
const development = process.argv.includes("--development");
const outputDirectory = resolve(repositoryDirectory, "assets/web/dist");
const outputFile = resolve(outputDirectory, "vrm-engine.js");

await mkdir(outputDirectory, { recursive: true });
await build({
  entryPoints: [resolve(webDirectory, "src/main.ts")],
  outfile: outputFile,
  bundle: true,
  format: "iife",
  globalName: "FlutterThreeVrm",
  platform: "browser",
  target: ["chrome88"],
  minify: !development,
  sourcemap: development ? "inline" : false,
  legalComments: "eof",
  define: {
    __RUNTIME_VERSION__: JSON.stringify(packageJson.version),
    __THREE_VRM_VERSION__: JSON.stringify(
      packageJson.dependencies["@pixiv/three-vrm"],
    ),
  },
});

const bundle = await readFile(outputFile);
const manifest = {
  runtimeVersion: packageJson.version,
  protocolVersion: 1,
  sha256: createHash("sha256").update(bundle).digest("hex"),
  dependencies: packageJson.dependencies,
};

await writeFile(
  resolve(outputDirectory, "manifest.json"),
  `${JSON.stringify(manifest, null, 2)}\n`,
  "utf8",
);
