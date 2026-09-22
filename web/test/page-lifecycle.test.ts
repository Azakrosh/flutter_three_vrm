import { describe, expect, it, vi } from "vitest";

import { RuntimePageLifecycle } from "../src/page-lifecycle";

function createHarness(cleanupSteps: readonly (() => void)[] = []) {
  const page = new EventTarget();
  const resizeScene = vi.fn();
  const frameAvatar = vi.fn();
  const onCleanupError = vi.fn();
  let customCamera = false;
  const lifecycle = new RuntimePageLifecycle({
    page,
    getViewport: () => ({ width: 800, height: 600 }),
    resizeScene,
    hasCustomCameraTransform: () => customCamera,
    frameAvatar,
    cleanupSteps,
    onCleanupError,
  });
  return {
    page,
    resizeScene,
    frameAvatar,
    onCleanupError,
    lifecycle,
    setCustomCamera(value: boolean) { customCamera = value; },
  };
}

describe("runtime page lifecycle", () => {
  it("resizes and reframes only when the camera has no custom transform", () => {
    const harness = createHarness();
    harness.lifecycle.attach();
    harness.lifecycle.attach();
    harness.page.dispatchEvent(new Event("resize"));
    expect(harness.resizeScene).toHaveBeenCalledTimes(1);
    expect(harness.resizeScene).toHaveBeenCalledWith(800, 600);
    expect(harness.frameAvatar).toHaveBeenCalledTimes(1);

    harness.setCustomCamera(true);
    harness.page.dispatchEvent(new Event("resize"));
    expect(harness.resizeScene).toHaveBeenCalledTimes(2);
    expect(harness.frameAvatar).toHaveBeenCalledTimes(1);
  });

  it("detaches page listeners before ordered cleanup and ignores repeated dispose", () => {
    const order: string[] = [];
    const harness = createHarness([
      () => {
        order.push("stop");
        harness.page.dispatchEvent(new Event("resize"));
        harness.page.dispatchEvent(new Event("pagehide"));
      },
      () => { order.push("cancel"); },
      () => { order.push("release"); },
    ]);
    harness.lifecycle.attach();
    harness.page.dispatchEvent(new Event("pagehide"));
    expect(order).toEqual(["stop", "cancel", "release"]);
    expect(harness.lifecycle.isDisposed).toBe(true);
    expect(harness.resizeScene).not.toHaveBeenCalled();
    harness.lifecycle.dispose();
    harness.lifecycle.attach();
    harness.page.dispatchEvent(new Event("resize"));
    expect(order).toHaveLength(3);
    expect(harness.resizeScene).not.toHaveBeenCalled();
  });

  it("continues releasing resources if one cleanup step throws", () => {
    const afterFailure = vi.fn();
    const error = new Error("failed to release a blob");
    const harness = createHarness([
      () => { throw error; },
      afterFailure,
    ]);
    harness.lifecycle.attach();
    harness.lifecycle.dispose();
    expect(harness.onCleanupError).toHaveBeenCalledWith(error);
    expect(afterFailure).toHaveBeenCalledOnce();
  });
});
