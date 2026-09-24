import { describe, expect, it } from "vitest";

import {
  ProtocolError,
  event,
  failure,
  parseCommand,
  protocolVersion,
  success,
} from "../src/protocol";
import { runtimeEmptyPayloadCommandNames } from "../src/protocol-contract";

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

  it.each(runtimeEmptyPayloadCommandNames)(
    "accepts only an empty payload for %s",
    (action) => {
      expect(structuredCommand(action, {}).payload).toEqual({});
      expect(() => structuredCommand(action, { unexpected: true }))
        .toThrowError(expect.objectContaining({
          code: "invalidPayload",
          message: `Command payload ${action} must be empty.`,
        }));
    },
  );

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

  it("decodes valid animation and lighting payloads", () => {
    expect(
      structuredCommand("playAnimationFromUrl", {
        url: "https://example.test/wave.vrma",
        options: {
          playbackId: "animation-1",
          clipName: "Wave",
          rootMotion: "inPlace",
          loop: false,
          speed: 1.25,
          fadeDuration: 0.2,
        },
      }).payload,
    ).toEqual(expect.objectContaining({
      options: expect.objectContaining({ playbackId: "animation-1" }),
    }));
    expect(
      structuredCommand("setLighting", {
        ambientColor: "#ffffff",
        ambientIntensity: 0.8,
        directionalColor: "#ffeecc",
        directionalIntensity: 1.2,
      }).payload,
    ).toEqual(expect.objectContaining({ ambientIntensity: 0.8 }));
  });

  it("decodes valid expression, gaze, physics, wind, and background payloads", () => {
    expect(structuredCommand("setExpression", {
      expression: "happy",
      layer: "eyes",
      weight: 0.8,
      duration: 0.25,
      disableAutoBlink: false,
    }).payload).toEqual(expect.objectContaining({ expression: "happy" }));
    expect(structuredCommand("setLookAtConfig", {
      holdDurationSec: 1.5,
    }).payload).toEqual({ holdDurationSec: 1.5 });
    expect(structuredCommand("setPhysics", {
      stiffness: 1.2,
      gravity: 0.8,
      drag: 1,
    }).payload).toEqual(expect.objectContaining({ stiffness: 1.2 }));
    expect(structuredCommand("setWind", {
      type: "strong",
      direction: "left",
    }).payload).toEqual({ type: "strong", direction: "left" });
    expect(structuredCommand("setBackground", {
      color: "#112233",
      imageUrl: "https://example.test/background.webp",
      transparent: false,
      hostedImage: false,
    }).payload).toEqual(expect.objectContaining({ color: "#112233" }));
  });

  it.each([
    [
      "setExpression",
      {
        expression: "smirk",
        layer: "eyes",
        weight: 1,
        duration: 0.25,
        disableAutoBlink: false,
      },
      "Command payload setExpression is invalid: expression must be a supported VRM expression.",
    ],
    [
      "setExpression",
      {
        expression: "aa",
        layer: "mouth",
        weight: 1,
        duration: 0.1,
        disableAutoBlink: false,
      },
      "Command payload setExpression is invalid: speechRevision is required for mouth expressions.",
    ],
    [
      "clearExpressionLayer",
      { layer: "mouth" },
      "Command payload clearExpressionLayer is invalid: speechRevision is required for the mouth layer.",
    ],
    [
      "setCustomBlendShape",
      { name: "custom", weight: 1.1 },
      "Command payload setCustomBlendShape is invalid: weight must be between 0 and 1.",
    ],
    [
      "setLookAtTarget",
      { x: 0, y: 1, z: "near" },
      "Command payload setLookAtTarget is invalid: z must be a finite number.",
    ],
    [
      "setLookAtConfig",
      { holdDurationSec: -0.1 },
      "Command payload setLookAtConfig is invalid: holdDurationSec must be a non-negative finite number.",
    ],
    [
      "setPhysics",
      { stiffness: -1, gravity: 1, drag: 1 },
      "Command payload setPhysics is invalid: stiffness must be a non-negative finite number.",
    ],
    [
      "setWind",
      { type: "hurricane", direction: "left" },
      'Command payload setWind is invalid: type must be "none", "light", "strong", or "storm".',
    ],
    [
      "setBackground",
      {
        color: "#112233",
        transparent: false,
        hostedImage: true,
      },
      "Command payload setBackground is invalid: imageUrl is required when hostedImage is true.",
    ],
    [
      "setEnvironmentColor",
      { color: "#112233", intensity: 1.1 },
      "Command payload setEnvironmentColor is invalid: intensity must be between 0 and 1.",
    ],
  ])(
    "rejects malformed interaction payload for %s",
    (action, payload, message) => {
      expect(() => structuredCommand(action, payload)).toThrowError(
        expect.objectContaining({ code: "invalidPayload", message }),
      );
    },
  );

  it.each([
    [
      "playAnimationFromUrl",
      {
        url: "https://example.test/wave.vrma",
        options: { speed: 1 },
      },
      "Command payload playAnimationFromUrl is invalid: playbackId must be a non-empty string.",
    ],
    [
      "playAnimationFromUrl",
      {
        url: "https://example.test/wave.vrma",
        options: { playbackId: "animation-1", speed: 0 },
      },
      "Command payload playAnimationFromUrl is invalid: speed must be a positive finite number.",
    ],
    [
      "playAnimationFromUrl",
      {
        url: "https://example.test/wave.vrma",
        options: {
          playbackId: "animation-1",
          rootMotion: "teleport",
        },
      },
      "Command payload playAnimationFromUrl is invalid: rootMotion must be inPlace or full.",
    ],
    [
      "playAnimationFromUrl",
      {
        url: "https://example.test/wave.vrma",
        options: {
          playbackId: "animation-1",
          fadeDuration: -0.1,
        },
      },
      "Command payload playAnimationFromUrl is invalid: fadeDuration must be a non-negative finite number.",
    ],
    [
      "setLighting",
      { ambientIntensity: -1 },
      "Command payload setLighting is invalid: ambientIntensity must be a non-negative finite number.",
    ],
    [
      "setLighting",
      { directionalColor: "" },
      "Command payload setLighting is invalid: directionalColor must be a non-empty string.",
    ],
  ])(
    "rejects malformed animation or lighting payload for %s",
    (action, payload, message) => {
      expect(() => structuredCommand(action, payload)).toThrowError(
        expect.objectContaining({
          code: "invalidPayload",
          message,
        }),
      );
    },
  );

  it("decodes valid Pose, camera, and graphics payloads", () => {
    expect(
      structuredCommand("setPose", {
        pose: { head: { rotation: [0, 0, 0, 1] } },
        fadeDuration: 0.25,
      }).payload,
    ).toEqual(expect.objectContaining({ fadeDuration: 0.25 }));
    expect(
      structuredCommand("setTransform", {
        transform: { x: 0.1, y: -0.2, zoom: 1.5 },
      }).payload,
    ).toEqual({
      transform: { x: 0.1, y: -0.2, zoom: 1.5 },
    });
    expect(
      structuredCommand("setAdaptiveQuality", {
        settings: {
          enabled: true,
          targetFps: 60,
          minPixelRatio: 0.75,
          maxPixelRatio: 1.5,
        },
      }).payload,
    ).toEqual(expect.objectContaining({
      settings: expect.objectContaining({ targetFps: 60 }),
    }));
  });

  it.each([
    [
      "setPose",
      {
        pose: { tail: { rotation: [0, 0, 0, 1] } },
        fadeDuration: 0.25,
      },
      "Command payload setPose is invalid: Unknown VRM humanoid bone: tail.",
    ],
    [
      "setPose",
      {
        pose: { head: { rotation: [0, 0, 0, 0] } },
        fadeDuration: 0.25,
      },
      "Command payload setPose is invalid: head.rotation must not be a zero quaternion.",
    ],
    [
      "resetPose",
      { fadeDuration: -0.1 },
      "Command payload resetPose is invalid: fadeDuration must be a non-negative finite number.",
    ],
    [
      "setCameraMode",
      { mode: "orbit" },
      'Command payload setCameraMode is invalid: mode must be "constrained" or "free".',
    ],
    [
      "setTransform",
      { transform: { x: "0", y: 0, zoom: 1 } },
      "Command payload setTransform is invalid: Camera transform components must be finite numbers.",
    ],
    [
      "setTransform",
      { transform: { x: 0, y: 0, zoom: 0 } },
      "Command payload setTransform is invalid: Camera transform zoom must be positive.",
    ],
    [
      "resetCamera",
      { durationMs: -1 },
      "Command payload resetCamera is invalid: durationMs must be a non-negative finite number.",
    ],
    [
      "setGraphicsSettings",
      { settings: { fpsCap: "60" } },
      "Command payload setGraphicsSettings is invalid: fpsCap must be zero or a positive finite number.",
    ],
    [
      "setGraphicsPreset",
      { preset: "cinematic" },
      'Command payload setGraphicsPreset is invalid: preset must be "performance", "balanced", or "quality".',
    ],
    [
      "setAdaptiveQuality",
      {
        settings: {
          minPixelRatio: 2,
          maxPixelRatio: 1,
        },
      },
      "Command payload setAdaptiveQuality is invalid: minPixelRatio must not exceed maxPixelRatio.",
    ],
    [
      "setRenderQuality",
      { pixelRatio: 0 },
      "Command payload setRenderQuality is invalid: pixelRatio must be a positive finite number.",
    ],
  ])(
    "rejects malformed structured payload for %s",
    (action, payload, message) => {
      expect(() => structuredCommand(action, payload)).toThrowError(
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
    expect(event("onStateChanged", { state: "initialized" })).toEqual({
      version: protocolVersion,
      type: "event",
      event: "onStateChanged",
      payload: { state: "initialized" },
    });
  });

  it("rejects invalid event payloads before transport", () => {
    expect(() => event(
      "onAnimationFinished",
      { name: "Wave" } as never,
    )).toThrowError(
      expect.objectContaining({
        code: "invalidEventPayload",
        message:
          "Event payload onAnimationFinished.playbackId must be a string.",
      }),
    );
    expect(() => event("onTap", null as never)).toThrowError(
      expect.objectContaining({
        code: "invalidEventPayload",
        message: "Event payload must be an object.",
      }),
    );
    expect(() => event("onModelReport", {
      name: "Avatar",
      vrmVersion: "1.0",
    } as never)).toThrowError(
      expect.objectContaining({
        code: "invalidEventPayload",
        message: "Event payload onModelReport.sourceBytes must be a number.",
      }),
    );
    expect(() => event("onPerformance", {
      fps: 60,
    } as never)).toThrowError(
      expect.objectContaining({
        code: "invalidEventPayload",
        message: "Event payload onPerformance.frameTimeMs must be a number.",
      }),
    );
  });

  it.each([
    [
      "onModelLoadProgress",
      { percent: 50.5, loaded: 5, total: 10 },
      "Event payload onModelLoadProgress is invalid: percent must be a non-negative safe integer.",
    ],
    [
      "onModelLoadProgress",
      { percent: 50, loaded: 11, total: 10 },
      "Event payload onModelLoadProgress is invalid: loaded must not exceed total.",
    ],
    [
      "onModelReport",
      { ...modelReportEventPayload(), height: 0 },
      "Event payload onModelReport is invalid: height must be a positive finite number.",
    ],
    [
      "onModelUnloaded",
      { stale: true },
      "Event payload onModelUnloaded is invalid: payload must be empty.",
    ],
    [
      "onExpressionChanged",
      { expression: "smirk", layer: "eyes" },
      "Event payload onExpressionChanged is invalid: expression must be a supported VRM expression.",
    ],
    [
      "onStateChanged",
      { state: "ready" },
      'Event payload onStateChanged is invalid: state must be "initialized".',
    ],
    [
      "onCameraChanged",
      { x: 0, y: 0, zoom: 0, userInitiated: false },
      "Event payload onCameraChanged is invalid: zoom must be a positive finite number.",
    ],
    [
      "onPerformance",
      { ...performanceEventPayload(), pixelRatio: 0 },
      "Event payload onPerformance is invalid: pixelRatio must be a positive finite number.",
    ],
    [
      "onWebGLContextChanged",
      { state: "suspended" },
      'Event payload onWebGLContextChanged is invalid: state must be "lost" or "restored".',
    ],
  ])("rejects invalid event domain values for %s", (name, payload, message) => {
    expect(() => event(name as never, payload as never)).toThrowError(
      expect.objectContaining({ code: "invalidEventPayload", message }),
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

function structuredCommand(action: string, payload: Record<string, unknown>) {
  return parseCommand(
    JSON.stringify({
      version: protocolVersion,
      id: `structured-${action}`,
      type: "command",
      action,
      payload,
    }),
  );
}

function modelReportEventPayload() {
  return {
    name: "Avatar",
    vrmVersion: "1.0",
    sourceBytes: 1024,
    height: 1.7,
    meshes: 1,
    skinnedMeshes: 1,
    geometries: 1,
    materials: 1,
    textures: 1,
    texturePixels: 1024,
    estimatedTextureMemoryBytes: 4096,
    maxTextureWidth: 32,
    maxTextureHeight: 32,
    vertices: 3,
    triangles: 1,
    morphTargets: 0,
    humanoidBones: 1,
    springBoneJoints: 0,
  };
}

function performanceEventPayload() {
  return {
    fps: 60,
    frameTimeMs: 16.67,
    frameTimeP50Ms: 16.5,
    frameTimeP95Ms: 18.2,
    pixelRatio: 1,
    fpsCap: 60,
    physicsEnabled: true,
    adaptiveQualityEnabled: true,
    drawCalls: 1,
    triangles: 1,
    geometries: 1,
    textures: 1,
    reason: "sample",
  };
}
