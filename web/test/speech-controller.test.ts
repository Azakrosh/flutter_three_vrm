import { describe, expect, it, vi } from "vitest";

import { RuntimeSpeechController } from "../src/speech-controller";

describe("runtime speech controller", () => {
  it("rejects stale revisions and resets mouth when a newer session starts", () => {
    const harness = createHarness();
    const controller = harness.controller;
    expect(controller.begin(begin("old", "viseme", 2))).toBe(true);
    expect(controller.begin(begin("stale", "viseme", 1))).toBe(false);
    expect(controller.timeline.sessionId).toBe("old");
    controller.setAmplitude(0.8);

    expect(controller.begin(begin("new", "amplitude", 3))).toBe(true);
    expect(controller.timeline.sessionId).toBe("new");
    expect(controller.amplitude).toBe(0);
    expect(harness.clearMouth).toHaveBeenCalledTimes(2);
  });

  it("presents visemes and completes a one-shot batch without seeking", () => {
    const harness = createHarness();
    const controller = harness.controller;
    controller.enqueueVisemes({
      ...begin("speech-1", "viseme", 1),
      frames: [
        { viseme: "aa", timestampMs: 0, durationMs: 40, weight: 0.75 },
        { viseme: "sil", timestampMs: 40, durationMs: 0 },
      ],
    });
    controller.update(0);
    expect(harness.setMouthExpression).toHaveBeenCalledWith(
      "aa",
      0.75,
      0.02,
    );
    controller.update(40);
    expect(harness.clearMouth).toHaveBeenCalled();
    expect(harness.onFinished).toHaveBeenCalledOnce();
    expect(harness.onFinished).toHaveBeenCalledWith("speech-1");
    expect(controller.timeline.isActive).toBe(false);
  });

  it("isolates stale cancel and fully stops only the active session", () => {
    const harness = createHarness();
    const controller = harness.controller;
    controller.begin(begin("active", "amplitude", 1));
    controller.setAmplitude(0.7);
    harness.clearMouth.mockClear();

    expect(controller.cancel("stale")).toBe(false);
    expect(controller.timeline.sessionId).toBe("active");
    expect(controller.amplitude).toBe(0.7);
    expect(harness.clearMouth).not.toHaveBeenCalled();

    expect(controller.cancel("active")).toBe(true);
    expect(controller.timeline.isActive).toBe(false);
    expect(controller.amplitude).toBe(0);
    expect(harness.clearMouth).toHaveBeenCalledOnce();
    expect(controller.cancel()).toBe(false);
    expect(harness.clearMouth).toHaveBeenCalledTimes(2);
  });

  it("smooths direct amplitude and resets it on explicit stop", () => {
    const harness = createHarness();
    const controller = harness.controller;
    const setValue = vi.fn();
    controller.setAmplitude(1);
    controller.applyAmplitude({ setValue });
    expect(setValue).toHaveBeenCalledWith("aa", 0.25);
    controller.applyAmplitude({ setValue });
    expect(setValue).toHaveBeenLastCalledWith("aa", 0.4375);
    controller.resetAmplitude();
    setValue.mockClear();
    controller.applyAmplitude({ setValue });
    expect(setValue).not.toHaveBeenCalled();
  });

  it("streams amplitude frames and reports finish only once", () => {
    const harness = createHarness();
    const controller = harness.controller;
    controller.begin(begin("stream", "amplitude", 1));
    expect(controller.appendAmplitudes("stream", [
      { amplitude: 0.9, timestampMs: 0, durationMs: 30 },
    ])).toBe(true);
    controller.finish("stream", 30);
    controller.update(0);
    expect(controller.amplitude).toBe(0.9);
    controller.update(30);
    expect(controller.amplitude).toBe(0);
    expect(harness.onFinished).toHaveBeenCalledOnce();
    controller.update(50);
    expect(harness.onFinished).toHaveBeenCalledOnce();
  });
});

function begin(
  sessionId: string,
  mode: "viseme" | "amplitude",
  speechRevision: number,
) {
  return {
    sessionId,
    mode,
    speechRevision,
    timelineOriginEpochMs: 1000,
  };
}

function createHarness() {
  const clearMouth = vi.fn();
  const setMouthExpression = vi.fn();
  const onFinished = vi.fn();
  const controller = new RuntimeSpeechController({
    clearMouth,
    setMouthExpression,
    onFinished,
    nowMs: () => 0,
    wallNowEpochMs: () => 1000,
  });
  return { controller, clearMouth, setMouthExpression, onFinished };
}
