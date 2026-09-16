import { describe, expect, it } from "vitest";

import contract from "../../tool/protocol_contract.json";
import {
  runtimeCommandNames,
  runtimeEventNames,
} from "../src/protocol-contract";
import { protocolVersion } from "../src/protocol";

describe("runtime protocol contract", () => {
  it("matches the checked-in command and event manifest", () => {
    expect(protocolVersion).toBe(contract.protocolVersion);
    expect(runtimeCommandNames).toEqual(contract.commands);
    expect(runtimeEventNames).toEqual(contract.events);
  });

  it("does not contain duplicate names", () => {
    expect(new Set(runtimeCommandNames).size).toBe(runtimeCommandNames.length);
    expect(new Set(runtimeEventNames).size).toBe(runtimeEventNames.length);
  });
});
