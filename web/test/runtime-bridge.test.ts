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
      () => ({
        runtimeVersion: "test",
        threeRevision: "180",
        threeVrmVersion: "3.5.5",
        protocolVersion: 3,
        webGlVersion: 2,
        maxTextureSize: 4096,
        maxTextures: 16,
        maxVertexTextures: 16,
        rendererTextureCount: 2,
        estimatedTextureMemoryBytes: 4096,
        lastModelLoadDurationMs: 250.5,
        modelLoaded: false,
        animationActive: false,
        animationPaused: false,
        renderingPaused: false,
        contextLost: false,
        contextLossCount: 0,
      }),
    );

    expect(response).toEqual({
      version: protocolVersion,
      id: "health-1",
      type: "response",
      ok: true,
      result: expect.objectContaining({ protocolVersion: 3 }),
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
