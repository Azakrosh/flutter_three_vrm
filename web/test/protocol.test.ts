import { describe, expect, it } from "vitest";

import {
  ProtocolError,
  failure,
  parseCommand,
  protocolVersion,
  success,
} from "../src/protocol";

describe("bridge protocol", () => {
  it("parses a valid command", () => {
    expect(
      parseCommand(
        JSON.stringify({
          version: protocolVersion,
          id: "request-1",
          type: "command",
          action: "engine.getInfo",
          payload: null,
        }),
      ),
    ).toEqual({
      version: protocolVersion,
      id: "request-1",
      type: "command",
      action: "engine.getInfo",
      payload: null,
    });
  });

  it("rejects unknown protocol versions", () => {
    expect(() =>
      parseCommand(
        JSON.stringify({
          version: 999,
          id: "request-1",
          type: "command",
          action: "engine.getInfo",
        }),
      ),
    ).toThrowError(ProtocolError);
  });

  it("creates typed success and failure envelopes", () => {
    expect(success("1", { ready: true }).ok).toBe(true);
    expect(failure("2", "failed", "Failure").ok).toBe(false);
  });
});
