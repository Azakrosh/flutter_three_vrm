import { describe, expect, it } from "vitest";

import { protocolVersion } from "../src/protocol";
import { createRuntimeCommandResponse } from "../src/runtime-bridge";

describe("runtime bridge", () => {
  it("executes a validated command and returns its correlated response", async () => {
    const response = await createRuntimeCommandResponse(
      JSON.stringify({
        version: protocolVersion,
        id: "health-1",
        type: "command",
        action: "getRuntimeHealth",
        payload: {},
      }),
      (command) => ({
        action: command.action,
        payload: command.payload,
      }),
    );

    expect(response).toEqual({
      version: protocolVersion,
      id: "health-1",
      type: "response",
      ok: true,
      result: { action: "getRuntimeHealth", payload: {} },
    });
  });

  it("turns protocol and executor failures into stable envelopes", async () => {
    const invalid = await createRuntimeCommandResponse(
      JSON.stringify({
        version: protocolVersion,
        id: "invalid-1",
        type: "command",
        action: "unknownCommand",
        payload: {},
      }),
      () => null,
    );
    expect(invalid).toMatchObject({
      id: "invalid-command",
      ok: false,
      error: { code: "unknownAction" },
    });

    const failed = await createRuntimeCommandResponse(
      JSON.stringify({
        version: protocolVersion,
        id: "health-2",
        type: "command",
        action: "getRuntimeHealth",
        payload: {},
      }),
      () => {
        throw Object.assign(new Error("Renderer failed."), {
          code: "rendererFailed",
        });
      },
    );
    expect(failed).toMatchObject({
      id: "health-2",
      ok: false,
      error: { code: "rendererFailed", message: "Renderer failed." },
    });
  });
});
