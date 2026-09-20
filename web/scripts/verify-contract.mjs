import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const webDirectory = resolve(scriptDirectory, "..");
const repositoryDirectory = resolve(webDirectory, "..");

const contract = JSON.parse(
  await readFile(
    resolve(repositoryDirectory, "tool/protocol_contract.json"),
    "utf8",
  ),
);
const dispatcherSource = await readFile(
  resolve(webDirectory, "src/command-dispatcher.ts"),
  "utf8",
);
const handledCommands = [
  ...dispatcherSource.matchAll(/case "([^"]+)":/g),
].map((match) => match[1]);

assertUnique(contract.commands, "contract command");
assertUnique(contract.events, "contract event");
assertUnique(handledCommands, "dispatcher command");
assertSameNames(contract.commands, handledCommands, "TypeScript command dispatcher");

console.log(
  `Verified protocol v${contract.protocolVersion}: ` +
    `${contract.commands.length} commands and ${contract.events.length} events.`,
);

function assertUnique(values, label) {
  const duplicates = values.filter(
    (value, index) => values.indexOf(value) !== index,
  );
  if (duplicates.length > 0) {
    throw new Error(`Duplicate ${label} names: ${[...new Set(duplicates)].join(", ")}.`);
  }
}

function assertSameNames(expected, actual, label) {
  const expectedSet = new Set(expected);
  const actualSet = new Set(actual);
  const missing = expected.filter((value) => !actualSet.has(value));
  const unexpected = actual.filter((value) => !expectedSet.has(value));
  if (missing.length > 0 || unexpected.length > 0) {
    throw new Error(
      `${label} differs from tool/protocol_contract.json. ` +
        `Missing: ${missing.join(", ") || "none"}. ` +
        `Unexpected: ${unexpected.join(", ") || "none"}.`,
    );
  }
}
