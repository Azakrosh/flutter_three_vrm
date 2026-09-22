import { describe, expect, it, vi } from "vitest";

import { RuntimeFrameScheduler } from "../src/frame-scheduler";

function createHarness() {
  let now = 1000;
  let nextId = 0;
  let contextLost = false;
  let renderAllowed = true;
  const pending = new Map<number, FrameRequestCallback>();
  const cancelFrame = vi.fn((id: number) => { pending.delete(id); });
  const resetGraphicsTiming = vi.fn();
  const onFrame = vi.fn();
  const scheduler = new RuntimeFrameScheduler({
    now: () => now,
    requestFrame: (callback) => {
      const id = nextId++;
      pending.set(id, callback);
      return id;
    },
    cancelFrame,
    shouldRender: () => renderAllowed,
    isContextLost: () => contextLost,
    resetGraphicsTiming,
    onFrame,
  }, now);
  return {
    scheduler,
    pending,
    cancelFrame,
    resetGraphicsTiming,
    onFrame,
    setNow(value: number) { now = value; },
    setContextLost(value: boolean) { contextLost = value; },
    setRenderAllowed(value: boolean) { renderAllowed = value; },
    fire(time: number) {
      const next = pending.entries().next().value;
      if (!next) throw new Error("No frame is scheduled.");
      const [id, callback] = next;
      pending.delete(id);
      now = time;
      callback(time);
    },
  };
}

describe("runtime frame scheduler", () => {
  it("schedules one frame, caps delta, and resumes without a time jump", () => {
    const harness = createHarness();
    harness.scheduler.start();
    harness.scheduler.start();
    expect(harness.pending.size).toBe(1);
    harness.fire(1016);
    expect(harness.onFrame).toHaveBeenLastCalledWith({
      now: 1016,
      delta: 0.016,
      elapsedTime: 0.016,
    });
    harness.scheduler.pause();
    expect(harness.scheduler.isPaused).toBe(true);
    expect(harness.pending.size).toBe(0);
    harness.setNow(10000);
    harness.scheduler.resume();
    expect(harness.resetGraphicsTiming).toHaveBeenCalledWith(10000);
    harness.fire(10016);
    expect(harness.onFrame).toHaveBeenLastCalledWith({
      now: 10016,
      delta: 0.016,
      elapsedTime: 0.032,
    });
    harness.fire(20000);
    expect(harness.onFrame.mock.lastCall?.[0].delta).toBe(0.1);
  });

  it("keeps scheduling while context is lost or FPS gating skips a frame", () => {
    const harness = createHarness();
    harness.scheduler.start();
    harness.setContextLost(true);
    harness.fire(1100);
    expect(harness.onFrame).not.toHaveBeenCalled();
    expect(harness.pending.size).toBe(1);
    harness.setContextLost(false);
    harness.setRenderAllowed(false);
    harness.fire(1200);
    expect(harness.onFrame).not.toHaveBeenCalled();
    harness.setRenderAllowed(true);
    harness.scheduler.resetTiming();
    expect(harness.resetGraphicsTiming).toHaveBeenCalledWith(1200);
    harness.fire(1216);
    expect(harness.onFrame).toHaveBeenCalledWith({
      now: 1216,
      delta: 0.016,
      elapsedTime: 0.016,
    });
  });

  it("cancels frame ID zero and ignores stale callbacks after pause or dispose", () => {
    const harness = createHarness();
    harness.scheduler.start();
    const stale = harness.pending.get(0)!;
    harness.scheduler.pause();
    expect(harness.cancelFrame).toHaveBeenCalledWith(0);
    harness.setNow(2000);
    harness.scheduler.resume();
    expect(harness.pending.size).toBe(1);
    stale(2010);
    expect(harness.pending.size).toBe(1);
    expect(harness.onFrame).not.toHaveBeenCalled();
    const resumed = harness.pending.values().next().value!;
    harness.scheduler.dispose();
    harness.scheduler.dispose();
    expect(harness.pending.size).toBe(0);
    resumed(2020);
    harness.scheduler.start();
    harness.scheduler.resume();
    expect(harness.onFrame).not.toHaveBeenCalled();
    expect(harness.pending.size).toBe(0);
  });
});
