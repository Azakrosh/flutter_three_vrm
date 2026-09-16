import { describe, expect, it } from "vitest";

import {
  ProtocolError,
  event,
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
          action: "getRuntimeHealth",
          payload: {},
        }),
      ),
    ).toEqual({
      version: protocolVersion,
      id: "request-1",
      type: "command",
      action: "getRuntimeHealth",
      payload: {},
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

  it("rejects unknown actions before they reach the runtime", () => {
    expect(() =>
      parseCommand(
        JSON.stringify({
          version: protocolVersion,
          id: "request-2",
          type: "command",
          action: "notARealCommand",
          payload: {},
        }),
      ),
    ).toThrowError(
      expect.objectContaining({
        code: "unknownAction",
        message: "Unknown VRM command: notARealCommand.",
      }),
    );
  });

  it("rejects non-object command payloads", () => {
    expect(() =>
      parseCommand(
        JSON.stringify({
          version: protocolVersion,
          id: "request-3",
          type: "command",
          action: "getRuntimeHealth",
          payload: null,
        }),
      ),
    ).toThrowError(
      expect.objectContaining({
        code: "invalidPayload",
        message: "Command payload must be an object.",
      }),
    );
  });

  it("rejects missing or mistyped required payload fields", () => {
    expect(() =>
      parseCommand(
        JSON.stringify({
          version: protocolVersion,
          id: "request-4",
          type: "command",
          action: "loadModelFromUrl",
          payload: { url: 42 },
        }),
      ),
    ).toThrowError(
      expect.objectContaining({
        code: "invalidPayload",
        message: "Command payload loadModelFromUrl.url must be a string.",
      }),
    );

    expect(() =>
      parseCommand(
        JSON.stringify({
          version: protocolVersion,
          id: "request-5",
          type: "command",
          action: "appendSpeechVisemes",
          payload: { sessionId: "speech-1", frames: {} },
        }),
      ),
    ).toThrowError(
      expect.objectContaining({
        code: "invalidPayload",
        message: "Command payload appendSpeechVisemes.frames must be an array.",
      }),
    );
  });

  it("creates typed success and failure envelopes", () => {
    expect(success("1", { ready: true }).ok).toBe(true);
    expect(failure("2", "failed", "Failure").ok).toBe(false);
    expect(event("onStateChanged", { state: "ready" })).toEqual({
      version: protocolVersion,
      type: "event",
      event: "onStateChanged",
      payload: { state: "ready" },
    });
  });

  it("rejects invalid event payloads before transport", () => {
    expect(() => event("onAnimationFinished", { name: "Wave" })).toThrowError(
      expect.objectContaining({
        code: "invalidEventPayload",
        message:
          "Event payload onAnimationFinished.playbackId must be a string.",
      }),
    );
    expect(() => event("onTap", null)).toThrowError(
      expect.objectContaining({
        code: "invalidEventPayload",
        message: "Event payload must be an object.",
      }),
    );
  });
});
