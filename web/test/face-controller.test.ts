import type { VRM } from "@pixiv/three-vrm";
import { describe, expect, it, vi } from "vitest";

import { RuntimeFaceController } from "../src/face-controller";

describe("runtime face controller", () => {
  it("crossfades base emotions across layers and reports the requested layer", () => {
    const harness = createHarness();
    harness.controller.setExpression("happy", "eyes");
    harness.controller.updateExpressions(0.25);
    expect(harness.setValue).toHaveBeenCalledWith("happy", 1);

    harness.setValue.mockClear();
    harness.controller.setExpression("sad", "brows");
    harness.controller.updateExpressions(0.25);
    expect(harness.setValue).toHaveBeenCalledWith("happy", 0);
    expect(harness.setValue).toHaveBeenCalledWith("sad", 1);
    expect(harness.onExpressionChanged).toHaveBeenLastCalledWith("sad", "brows");
  });

  it("fades the previous mouth expression and restores blinking after clearing eyes", () => {
    const harness = createHarness();
    harness.controller.setExpression("aa", "mouth");
    harness.controller.updateExpressions(0.1);
    harness.controller.setExpression("ih", "mouth");
    harness.controller.updateExpressions(0.1);
    expect(harness.setValue).toHaveBeenCalledWith("aa", 0.24);
    expect(harness.setValue).toHaveBeenCalledWith("ih", 0.4);

    harness.controller.setExpression("happy", "eyes", 1, 0.25, true);
    expect(harness.controller.autoBlinkEnabled).toBe(false);
    harness.controller.clearExpressionLayer("eyes");
    expect(harness.controller.autoBlinkEnabled).toBe(true);
  });

  it("maps direct visemes, zeroes mouth presets, and clears on silence", () => {
    const harness = createHarness();
    harness.controller.setViseme("OH", 0.8);
    expect(harness.setValue).toHaveBeenCalledWith("aa", 0);
    expect(harness.setValue).toHaveBeenCalledWith("oh", 0);
    harness.controller.updateExpressions(0.1);
    expect(harness.setValue).toHaveBeenCalledWith("oh", 0.8);

    harness.controller.setViseme("sil");
    harness.controller.updateExpressions(0.1);
    expect(harness.setValue).toHaveBeenLastCalledWith("oh", 0);
  });

  it("updates blink after the expression pass and suppresses overlapping eye emotion", () => {
    const harness = createHarness();
    harness.controller.setExpression("happy");
    harness.controller.updateExpressions(0.25);
    for (let frame = 0; frame < 30; frame += 1) {
      harness.controller.updateBlink(0.1);
    }
    harness.setValue.mockClear();
    harness.controller.updateExpressions(0.1);
    const blink = harness.setValue.mock.calls.find(([name]) => name === "blink")?.[1];
    const happy = harness.setValue.mock.calls.find(([name]) => name === "happy")?.[1];
    expect(blink).toBeGreaterThan(0);
    expect(happy).toBeCloseTo(1 - blink, 6);
  });

  it("applies custom blend shapes and clears them only with a loaded model", () => {
    const harness = createHarness();
    harness.controller.customBlendShapes.set("custom", 0.4);
    harness.controller.updateExpressions(0.1);
    expect(harness.setValue).toHaveBeenCalledWith("custom", 0.4);
    expect(harness.applySpeechAmplitude).toHaveBeenCalledOnce();

    harness.setLoaded(false);
    expect(harness.controller.clearAllExpressions()).toBe(false);
    expect(harness.controller.customBlendShapes.size).toBe(1);
    harness.setLoaded(true);
    expect(harness.controller.clearAllExpressions()).toBe(true);
    expect(harness.controller.customBlendShapes.size).toBe(0);
  });

  it("ignores unknown layers and a missing expression manager", () => {
    const harness = createHarness();
    harness.controller.setExpression("happy", "invalid");
    expect(harness.onExpressionChanged).not.toHaveBeenCalled();
    harness.setLoaded(false);
    harness.controller.setViseme("aa");
    harness.controller.updateExpressions(0.1);
    harness.controller.updateBlink(0.1);
    expect(harness.setValue).not.toHaveBeenCalled();
  });
});

function createHarness() {
  const setValue = vi.fn();
  const applySpeechAmplitude = vi.fn();
  const onExpressionChanged = vi.fn();
  let loaded = true;
  const controller = new RuntimeFaceController({
    getVrm: () =>
      loaded ? ({ expressionManager: { setValue } } as unknown as VRM) : null,
    applySpeechAmplitude,
    onExpressionChanged,
    random: () => 0.5,
  });
  return {
    controller,
    setValue,
    applySpeechAmplitude,
    onExpressionChanged,
    setLoaded(value: boolean) { loaded = value; },
  };
}
