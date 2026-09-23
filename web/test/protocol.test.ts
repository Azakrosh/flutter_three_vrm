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

  it("decodes valid streaming speech payloads", () => {
    expect(
      speechCommand("enqueueSpeechVisemes", {
        sessionId: "speech-1",
        mode: "viseme",
        timelineOriginEpochMs: 1_000,
        speechRevision: 2,
        frames: [{
          viseme: "aa",
          weight: 0.8,
          timestampMs: 0,
          durationMs: 80,
        }],
        audioDurationMs: 80,
      }).payload,
    ).toEqual(expect.objectContaining({
      sessionId: "speech-1",
      mode: "viseme",
    }));

    expect(
      speechCommand("appendSpeechAmplitudes", {
        sessionId: "speech-2",
        frames: [{
          amplitude: 0.5,
          timestampMs: 20,
          durationMs: 50,
        }],
      }).payload,
    ).toEqual(expect.objectContaining({ sessionId: "speech-2" }));
  });

  it.each([
    [
      "beginSpeech",
      {
        sessionId: "speech-1",
        mode: "phoneme",
        timelineOriginEpochMs: 1_000,
        speechRevision: 1,
      },
      'Command payload beginSpeech.mode must be "viseme" or "amplitude".',
    ],
    [
      "beginSpeech",
      {
        sessionId: "speech-1",
        mode: "viseme",
        timelineOriginEpochMs: 1_000,
        speechRevision: 1.5,
      },
      "Command payload beginSpeech.speechRevision must be a non-negative safe integer.",
    ],
    [
      "enqueueSpeechVisemes",
      {
        sessionId: "speech-1",
        mode: "amplitude",
        timelineOriginEpochMs: 1_000,
        speechRevision: 1,
        frames: [],
      },
      'Command payload enqueueSpeechVisemes.mode must be "viseme".',
    ],
    [
      "appendSpeechVisemes",
      {
        sessionId: "speech-1",
        frames: [{
          viseme: "unknown",
          timestampMs: 0,
          durationMs: 80,
        }],
      },
      "Command payload appendSpeechVisemes.frames[0].viseme must be a supported viseme.",
    ],
    [
      "appendSpeechVisemes",
      {
        sessionId: "speech-1",
        frames: [{
          viseme: "aa",
          weight: 1.1,
          timestampMs: 0,
          durationMs: 80,
        }],
      },
      "Command payload appendSpeechVisemes.frames[0].weight must be a finite number from 0 to 1.",
    ],
    [
      "appendSpeechAmplitudes",
      {
        sessionId: "speech-1",
        frames: [{
          amplitude: -0.1,
          timestampMs: 0,
          durationMs: 50,
        }],
      },
      "Command payload appendSpeechAmplitudes.frames[0].amplitude must be a finite number from 0 to 1.",
    ],
    [
      "appendSpeechAmplitudes",
      {
        sessionId: "speech-1",
        frames: [{
          amplitude: 0.5,
          timestampMs: -1,
          durationMs: 50,
        }],
      },
      "Command payload appendSpeechAmplitudes.frames[0].timestampMs must be a non-negative finite number.",
    ],
    [
      "finishSpeech",
      { sessionId: "speech-1", audioDurationMs: -1 },
      "Command payload finishSpeech.audioDurationMs must be a non-negative finite number.",
    ],
    [
      "cancelSpeech",
      { speechRevision: 1, sessionId: "" },
      "Command payload cancelSpeech.sessionId must be a non-empty string.",
    ],
  ])(
    "rejects malformed nested speech payload for %s",
    (action, payload, message) => {
      expect(() => speechCommand(action, payload)).toThrowError(
        expect.objectContaining({
          code: "invalidPayload",
          message,
        }),
      );
    },
  );

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

function speechCommand(action: string, payload: Record<string, unknown>) {
  return parseCommand(
    JSON.stringify({
      version: protocolVersion,
      id: `speech-${action}`,
      type: "command",
      action,
      payload,
    }),
  );
}
