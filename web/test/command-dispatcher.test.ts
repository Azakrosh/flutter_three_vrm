import { describe, expect, expectTypeOf, it, vi } from "vitest";

import {
  createRuntimeCommandDispatcher,
  type RuntimeCommandHost,
} from "../src/command-dispatcher";
import {
  parseCommand,
  protocolVersion,
  type CommandEnvelope,
} from "../src/protocol";
import type { RuntimeCommandResult } from "../src/protocol-contract";

describe("runtime command dispatcher", () => {
  it("routes typed payloads to the runtime host", async () => {
    const host = createHost();
    const dispatch = createRuntimeCommandDispatcher(host);

    await dispatch(command("setWind", { type: "light", direction: "left" }));
    await dispatch(command("setLookAtTarget", { x: 0.25, y: 0.75 }));

    expect(host.setWind).toHaveBeenCalledWith("light", "left");
    expect(host.gazeController.setTarget).toHaveBeenCalledWith(
      0.25, 0.75, undefined,
    );
  });

  it("returns query results and preserves missing-model errors", async () => {
    const host = createHost();
    host.modelReport = {
      name: "Test",
      vrmVersion: "1.0",
      sourceBytes: 1,
      height: 1.6,
      meshes: 1,
      skinnedMeshes: 1,
      geometries: 1,
      materials: 1,
      textures: 1,
      texturePixels: 1,
      estimatedTextureMemoryBytes: 4,
      maxTextureWidth: 1,
      maxTextureHeight: 1,
      vertices: 3,
      triangles: 1,
      morphTargets: 0,
      humanoidBones: 1,
      springBoneJoints: 0,
    };
    const dispatch = createRuntimeCommandDispatcher(host);

    await expect(dispatch(command("getModelReport", {}))).resolves.toEqual(
      expect.objectContaining({ vrmVersion: "1.0" }),
    );
    await expect(dispatch(command("getPose", {}))).rejects.toThrow(
      "Load a VRM model before using the Pose API.",
    );
  });

  it("preserves command-specific result types", async () => {
    const dispatch = createRuntimeCommandDispatcher(createHost());
    const healthCommand: CommandEnvelope<"getRuntimeHealth"> = {
      version: protocolVersion,
      id: "typed-health",
      type: "command",
      action: "getRuntimeHealth",
      payload: {},
    };
    const pauseCommand: CommandEnvelope<"pauseAnimation"> = {
      version: protocolVersion,
      id: "typed-pause",
      type: "command",
      action: "pauseAnimation",
      payload: {},
    };

    expectTypeOf(dispatch(healthCommand)).toEqualTypeOf<
      Promise<RuntimeCommandResult<"getRuntimeHealth">>
    >();
    expectTypeOf(dispatch(pauseCommand)).toEqualTypeOf<Promise<null>>();
    await expect(dispatch(healthCommand)).resolves.toEqual(
      expect.objectContaining({ protocolVersion: 3 }),
    );
    await expect(dispatch(pauseCommand)).resolves.toBeNull();
  });

  it("does not apply stale speech commands", async () => {
    const host = createHost();
    host.speechTimeline.acceptInputRevision = vi.fn(() => false);
    const dispatch = createRuntimeCommandDispatcher(host);

    await dispatch(
      command("setViseme", {
        viseme: "aa",
        weight: 0.8,
        speechRevision: 4,
      }),
    );

    expect(host.cancelSpeech).not.toHaveBeenCalled();
    expect(host.setViseme).not.toHaveBeenCalled();
  });

  it("routes motion and Pose commands only through the host facade", async () => {
    const host = createHost();
    const dispatch = createRuntimeCommandDispatcher(host);
    await dispatch(command("pauseAnimation", {}));
    await dispatch(command("resumeAnimation", { speed: 1.5 }));
    await dispatch(command("setAnimationSpeed", { speed: 0.75 }));
    await dispatch(command("setPose", {
      pose: { head: { rotation: [0, 0, 0, 1] } },
      fadeDuration: 0.3,
    }));
    expect(host.pauseAnimation).toHaveBeenCalledOnce();
    expect(host.resumeAnimation).toHaveBeenCalledWith(1.5);
    expect(host.setAnimationSpeed).toHaveBeenCalledWith(0.75);
    expect(host.setPose).toHaveBeenCalledWith(
      { head: { rotation: [0, 0, 0, 1] } },
      0.3,
    );
  });
});

function command(action: string, payload: Record<string, unknown>) {
  return parseCommand(
    JSON.stringify({
      version: protocolVersion,
      id: `test-${action}`,
      type: "command",
      action,
      payload,
    }),
  );
}

function createHost(): RuntimeCommandHost {
  return {
    modelReport: null,
    speechTimeline: { acceptInputRevision: vi.fn(() => true) },
    customBlendShapes: new Map(),
    gazeController: {
      setTarget: vi.fn(),
      setAutoSaccades: vi.fn(),
      setHoldDuration: vi.fn(),
    },
    lipSyncAmplitude: 0,
    autoBlinkEnabled: true,
    loadModelFromUrl: vi.fn(async () => undefined),
    cancelModelLoad: vi.fn(),
    getRuntimeHealth: vi.fn(() => ({
      runtimeVersion: "test",
      threeRevision: "180",
      threeVrmVersion: "3.5.5",
      protocolVersion: 3,
      webGlVersion: 2 as const,
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
    })),
    unloadModel: vi.fn(),
    playAnimationFromUrl: vi.fn(async () => undefined),
    cancelAnimationLoad: vi.fn(),
    pauseRendering: vi.fn(),
    resumeRendering: vi.fn(),
    transitionToRest: vi.fn(),
    pauseAnimation: vi.fn(),
    resumeAnimation: vi.fn(),
    setAnimationSpeed: vi.fn(),
    getPose: vi.fn(() => {
      throw new Error("Load a VRM model before using the Pose API.");
    }),
    setPose: vi.fn(),
    setShadows: vi.fn(),
    setExpression: vi.fn(),
    clearExpressionLayer: vi.fn(),
    clearAllExpressions: vi.fn(),
    setViseme: vi.fn(),
    enqueueSpeechVisemes: vi.fn(),
    enqueueSpeechAmplitudes: vi.fn(),
    beginSpeech: vi.fn(() => true),
    appendSpeechVisemes: vi.fn(),
    appendSpeechAmplitudes: vi.fn(),
    finishSpeech: vi.fn(),
    cancelSpeech: vi.fn(),
    setCameraMode: vi.fn(),
    resetCamera: vi.fn(),
    getAvatarTransform: vi.fn(() => ({ x: 0, y: 0, zoom: 1 })),
    setAvatarTransform: vi.fn(),
    setLighting: vi.fn(),
    setBackground: vi.fn(async () => undefined),
    setPhysics: vi.fn(),
    stopWind: vi.fn(),
    setWind: vi.fn(),
    setEnvironmentColor: vi.fn(),
    setGraphicsSettings: vi.fn(),
    setGraphicsPreset: vi.fn(),
    setAdaptiveQuality: vi.fn(),
    getPerformanceSnapshot: vi.fn(() => ({
      fps: 60,
      frameTimeMs: 16.67,
      frameTimeP50Ms: 16.5,
      frameTimeP95Ms: 18.2,
      frameSampleCount: 60,
      longFrameCount: 0,
      longestFrameMs: 0,
      longFrameThresholdMs: 25,
      updateTimeP95Ms: 2,
      renderTimeP95Ms: 3,
      longFrameSource: "none" as const,
      pixelRatio: 1,
      fpsCap: 60,
      physicsEnabled: true,
      adaptiveQualityEnabled: true,
      adaptiveTargetFps: 60,
      adaptiveSlowWindowCount: 0,
      adaptiveFastWindowCount: 1,
      adaptiveCooldownRemainingMs: 0,
      adaptiveDecision: "collectingFast" as const,
      drawCalls: 0,
      triangles: 0,
      geometries: 0,
      textures: 0,
      reason: "sample" as const,
    })),
    setRenderQuality: vi.fn(),
  };
}
