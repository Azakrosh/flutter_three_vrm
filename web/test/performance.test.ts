import { describe, expect, it } from "vitest";

import { AdaptiveQualityController } from "../src/performance";

describe("adaptive quality policy", () => {
  it("reduces pixel ratio only after sustained slow windows", () => {
    const controller = new AdaptiveQualityController();
    controller.configure({ enabled: true, targetFps: 60, minPixelRatio: 0.75, maxPixelRatio: 1.5 });

    expect(controller.evaluate(40, 1.5, 60, 0)).toBeNull();
    expect(controller.evaluate(40, 1.5, 60, 1000)).toBeNull();
    expect(controller.evaluate(40, 1.5, 60, 2000)).toEqual({
      pixelRatio: 1.35,
      reason: "performanceDown",
    });
    expect(controller.diagnostics).toMatchObject({
      decision: "decrease",
      effectiveTargetFps: 60,
      slowWindowCount: 3,
    });
    expect(controller.evaluate(40, 1.35, 60, 3000)).toBeNull();
  });

  it("raises pixel ratio slowly after sustained healthy windows", () => {
    const controller = new AdaptiveQualityController();
    controller.configure({ enabled: true, targetFps: 55, minPixelRatio: 0.75, maxPixelRatio: 1.5 });

    let adjustment = null;
    for (let index = 0; index < 8; index += 1) {
      adjustment = controller.evaluate(60, 1, 60, 5000 + index * 1000);
    }
    expect(adjustment).toEqual({ pixelRatio: 1.1, reason: "performanceUp" });
    expect(controller.diagnostics.decision).toBe("increase");
  });

  it("respects a lower explicit FPS cap and validates bounds", () => {
    const controller = new AdaptiveQualityController();
    controller.configure({ enabled: true, targetFps: 60, minPixelRatio: 1, maxPixelRatio: 2 });

    const adjustments = [];
    for (let index = 0; index < 10; index += 1) {
      const adjustment = controller.evaluate(30, 1, 30, index * 1000);
      if (adjustment !== null) adjustments.push(adjustment);
    }
    expect(adjustments.every((value) => value.reason !== "performanceDown")).toBe(true);
    expect(controller.diagnostics).toMatchObject({
      effectiveTargetFps: 30,
    });
    controller.configure({
      enabled: true,
      targetFps: 60,
      minPixelRatio: 1,
      maxPixelRatio: 2,
    });
    for (let index = 0; index < 5; index += 1) {
      controller.evaluate(20, 1, 60, 20000 + index * 1000);
    }
    expect(controller.diagnostics).toMatchObject({
      decision: "atMinimum",
      slowWindowCount: 3,
    });
    expect(() =>
      controller.configure({ enabled: true, minPixelRatio: 2, maxPixelRatio: 1 }),
    ).toThrow("must not exceed");
  });

  it("explains cooldown after a quality transition", () => {
    const controller = new AdaptiveQualityController();
    controller.configure({
      enabled: true,
      targetFps: 60,
      minPixelRatio: 0.75,
      maxPixelRatio: 1.5,
    });
    controller.evaluate(40, 1.5, 60, 0);
    controller.evaluate(40, 1.5, 60, 1000);
    controller.evaluate(40, 1.5, 60, 2000);
    controller.evaluate(40, 1.35, 60, 2500);
    controller.evaluate(40, 1.35, 60, 3000);
    expect(controller.evaluate(40, 1.35, 60, 3500)).toBeNull();
    expect(controller.diagnostics).toMatchObject({
      decision: "cooldown",
      slowWindowCount: 3,
      cooldownRemainingMs: 2500,
    });
  });
});
