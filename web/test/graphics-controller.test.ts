import type { WebGLRenderer } from "three";
import { describe, expect, it, vi } from "vitest";

import {
  RuntimeGraphicsController,
  type RuntimeGraphicsDependencies,
  type RuntimePerformanceSnapshot,
} from "../src/graphics-controller";

describe("runtime graphics controller", () => {
  it("validates complete settings before mutating renderer or physics", () => {
    const harness = createHarness();
    expect(() => harness.controller.setSettings({
      enablePhysics: false,
      fpsCap: -1,
    })).toThrow("fpsCap");
    expect(harness.setPhysicsEnabled).not.toHaveBeenCalled();
    expect(() => harness.controller.setSettings({
      antialias: false,
      pixelRatio: Number.NaN,
    })).toThrow("pixelRatio");
    expect(harness.recreateRenderer).not.toHaveBeenCalled();

    harness.controller.setSettings({
      antialias: false,
      enablePhysics: false,
      fpsCap: 200,
      pixelRatio: 4,
    });
    expect(harness.recreateRenderer).toHaveBeenCalledWith(false);
    expect(harness.setPhysicsEnabled).toHaveBeenCalledWith(false);
    expect(harness.scene.setPixelRatio).toHaveBeenCalledWith(3);
    expect(harness.controller.fpsCap).toBe(120);
    expect(harness.controller.physicsEnabled).toBe(false);
    expect(harness.controller.getSnapshot()).toMatchObject({
      fpsCap: 120,
      physicsEnabled: false,
      pixelRatio: 3,
    });
  });

  it("uses the configured frame cap and resets cadence after resume", () => {
    const harness = createHarness();
    const graphics = harness.controller;
    graphics.setSettings({ fpsCap: 30 });
    expect(graphics.shouldRender(1000)).toBe(true);
    expect(graphics.shouldRender(1010)).toBe(false);
    expect(graphics.shouldRender(1034)).toBe(true);
    graphics.resetTiming(1040);
    expect(graphics.shouldRender(1041)).toBe(true);
    graphics.setSettings({ fpsCap: 0 });
    expect(graphics.shouldRender(1042)).toBe(true);
    expect(graphics.shouldRender(1042)).toBe(true);
  });

  it("does not burst on the vsync after an accepted early frame", () => {
    const harness = createHarness();
    const graphics = harness.controller;
    graphics.setSettings({ fpsCap: 30 });

    expect(graphics.shouldRender(1000)).toBe(true);
    expect(graphics.shouldRender(1022)).toBe(false);
    expect(graphics.shouldRender(1031)).toBe(true);
    expect(graphics.shouldRender(1042)).toBe(false);
    expect(graphics.shouldRender(1062)).toBe(true);
  });

  it("applies preset and re-clamps ratio to the active adaptive policy", () => {
    const harness = createHarness();
    const graphics = harness.controller;
    graphics.setAdaptiveQuality({
      enabled: true,
      targetFps: 60,
      minPixelRatio: 0.75,
      maxPixelRatio: 1.25,
    });
    graphics.setPreset("performance");
    expect(harness.scene.setShadows).toHaveBeenLastCalledWith(false);
    expect(harness.recreateRenderer).toHaveBeenCalledWith(false);
    expect(graphics.fpsCap).toBe(30);
    expect(harness.ratio()).toBe(1);
    expect(graphics.getSnapshot().adaptiveTargetFps).toBe(30);

    graphics.setPreset("quality");
    expect(harness.scene.setShadows).toHaveBeenLastCalledWith(true);
    expect(harness.recreateRenderer).toHaveBeenLastCalledWith(true);
    expect(graphics.fpsCap).toBe(60);
    expect(harness.ratio()).toBe(1.25);
    expect(() => graphics.setPreset("unknown")).toThrow("Unknown graphics preset");
  });

  it("emits telemetry and lowers resolution after sustained slow windows", () => {
    const harness = createHarness();
    const graphics = harness.controller;
    graphics.setAdaptiveQuality({
      enabled: true,
      targetFps: 60,
      minPixelRatio: 0.75,
      maxPixelRatio: 1.5,
    });
    for (let frame = 1; frame <= 120; frame += 1) {
      graphics.recordFrame(frame * 25);
    }
    expect(harness.ratio()).toBe(1.35);
    expect(harness.onPerformance).toHaveBeenCalled();
    expect(harness.onPerformance).toHaveBeenLastCalledWith(
      expect.objectContaining({
        reason: "performanceDown",
        pixelRatio: 1.35,
        fps: 40,
        frameTimeMs: 25,
        frameTimeP50Ms: 25,
        frameTimeP95Ms: 25,
        drawCalls: 5,
        triangles: 10,
        geometries: 2,
        textures: 3,
      }),
    );
    expect(graphics.getSnapshot().reason).toBe("performanceDown");
  });

  it("retains telemetry after a timing reset without counting paused time", () => {
    const harness = createHarness();
    const graphics = harness.controller;
    graphics.recordFrame(1000);
    graphics.resetTiming(20000);
    graphics.recordFrame(20010);
    expect(graphics.getSnapshot().reason).toBe("sample");
    graphics.recordFrame(21000);
    expect(harness.onPerformance).toHaveBeenLastCalledWith(
      expect.objectContaining({
        fps: 2,
        frameTimeMs: 500,
        frameTimeP50Ms: 990,
        frameTimeP95Ms: 990,
      }),
    );
  });

  it("starts a clean percentile window after an operational pause", () => {
    const harness = createHarness();
    const graphics = harness.controller;
    graphics.recordFrame(1000);
    graphics.recordFrame(1040);

    graphics.resetTiming(7000);
    graphics.recordFrame(7010);
    graphics.recordFrame(7050);
    graphics.recordFrame(8010);

    expect(harness.onPerformance).toHaveBeenCalled();
    const snapshot = graphics.getSnapshot();
    expect(snapshot.fps).toBeCloseTo(3000 / 1010);
    expect(snapshot.frameTimeMs).toBeCloseTo(1010 / 3);
    expect(snapshot.frameTimeP50Ms).toBe(40);
    expect(snapshot.frameTimeP95Ms).toBe(960);
    expect(snapshot.frameTimeP95Ms).toBeLessThan(5960);
  });

  it("attributes long frames to measured runtime phases", () => {
    const harness = createHarness();
    const graphics = harness.controller;
    graphics.setSettings({ fpsCap: 60 });
    graphics.setAdaptiveQuality({
      enabled: true,
      targetFps: 60,
      minPixelRatio: 0.75,
      maxPixelRatio: 1.5,
    });
    graphics.recordFrame(1000, 2, 3);
    graphics.recordFrame(1040, 30, 4);
    graphics.recordFrame(2040, 30, 4);

    expect(graphics.getSnapshot()).toMatchObject({
      frameSampleCount: 2,
      longFrameCount: 2,
      longestFrameMs: 1000,
      longFrameThresholdMs: 25,
      updateTimeP95Ms: 30,
      renderTimeP95Ms: 4,
      longFrameSource: "runtimeUpdate",
    });
  });

  it("classifies unexplained long intervals as external scheduling", () => {
    const harness = createHarness();
    const graphics = harness.controller;
    graphics.recordFrame(1000, 1, 2);
    graphics.recordFrame(2000, 1, 2);

    expect(graphics.getSnapshot()).toMatchObject({
      longFrameCount: 1,
      longFrameSource: "externalScheduling",
    });
  });
});

function createHarness() {
  let pixelRatio = 1.5;
  let antialias = true;
  const setPixelRatio = vi.fn((ratio: number) => { pixelRatio = ratio; });
  const setShadows = vi.fn();
  const recreateRenderer = vi.fn((value: boolean) => { antialias = value; });
  const setPhysicsEnabled = vi.fn();
  const onPerformance = vi.fn<(snapshot: RuntimePerformanceSnapshot) => void>();
  const renderer = {
    getPixelRatio: () => pixelRatio,
    info: {
      render: { calls: 5, triangles: 10 },
      memory: { geometries: 2, textures: 3 },
    },
  } as unknown as WebGLRenderer;
  const scene = {
    get renderer() { return renderer; },
    get antialias() { return antialias; },
    setPixelRatio,
    setShadows,
  };
  const dependencies: RuntimeGraphicsDependencies = {
    scene,
    recreateRenderer,
    setPhysicsEnabled,
    onPerformance,
    devicePixelRatio: () => 2,
  };
  return {
    controller: new RuntimeGraphicsController(dependencies, 0),
    scene,
    recreateRenderer,
    setPhysicsEnabled,
    onPerformance,
    ratio: () => pixelRatio,
  };
}
