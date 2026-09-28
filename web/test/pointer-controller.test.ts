import { Vector2 } from "three";
import { describe, expect, it, vi } from "vitest";

import { RuntimePointerController } from "../src/pointer-controller";

function pointer(
  canvas: EventTarget,
  type: string,
  x: number,
  y: number,
  pointerId = 1,
  isPrimary = true,
): void {
  const event = Object.assign(new Event(type), {
    clientX: x,
    clientY: y,
    pointerId,
    isPrimary,
  });
  canvas.dispatchEvent(event);
}

function createHarness() {
  const canvas = new EventTarget() as HTMLElement;
  const camera = {
    mode: "constrained" as "constrained" | "free",
    setConstrainedPanTarget: vi.fn(),
  };
  const onTap = vi.fn();
  const onCameraChanged = vi.fn();
  let loaded = true;
  const controller = new RuntimePointerController({
    camera,
    getPanOffset: () => new Vector2(0.2, -0.1),
    getModelHeight: () => 1.7,
    hasModel: () => loaded,
    getViewport: () => ({ width: 800, height: 600 }),
    onTap,
    onCameraChanged,
  });
  controller.attach(canvas);
  return {
    canvas,
    camera,
    controller,
    onTap,
    onCameraChanged,
    setLoaded(value: boolean) { loaded = value; },
  };
}

describe("runtime pointer controller", () => {
  it("emits a tap without changing camera or avatar state", () => {
    const harness = createHarness();
    pointer(harness.canvas, "pointerdown", 100, 100);
    pointer(harness.canvas, "pointerup", 103, 105);
    expect(harness.onTap).toHaveBeenCalledWith(103, 105);
    expect(harness.onCameraChanged).not.toHaveBeenCalled();
    expect(harness.camera.setConstrainedPanTarget).not.toHaveBeenCalled();

    harness.setLoaded(false);
    pointer(harness.canvas, "pointerdown", 100, 100);
    pointer(harness.canvas, "pointerup", 100, 100);
    expect(harness.onTap).toHaveBeenCalledOnce();
  });

  it("passes primary drag to constrained pan and reports the final transform", () => {
    const harness = createHarness();
    pointer(harness.canvas, "pointerdown", 100, 100);
    pointer(harness.canvas, "pointermove", 130, 80, 2);
    expect(harness.camera.setConstrainedPanTarget).not.toHaveBeenCalled();
    pointer(harness.canvas, "pointermove", 130, 80);
    expect(harness.camera.setConstrainedPanTarget).toHaveBeenCalledWith({
      deltaX: 30,
      deltaY: -20,
      viewportWidth: 800,
      viewportHeight: 600,
      startPan: new Vector2(0.2, -0.1),
      modelHeight: 1.7,
    });
    pointer(harness.canvas, "pointerup", 130, 80);
    expect(harness.onTap).not.toHaveBeenCalled();
    expect(harness.onCameraChanged).toHaveBeenCalledOnce();
  });

  it("never turns pointer cancellation into a tap", () => {
    const harness = createHarness();
    pointer(harness.canvas, "pointerdown", 100, 100);
    pointer(harness.canvas, "pointercancel", 100, 100);
    expect(harness.onTap).not.toHaveBeenCalled();
    expect(harness.onCameraChanged).not.toHaveBeenCalled();
    pointer(harness.canvas, "pointerdown", 100, 100);
    pointer(harness.canvas, "pointercancel", 130, 100);
    expect(harness.onCameraChanged).toHaveBeenCalledOnce();
  });

  it("removes old canvas listeners and resets an interrupted gesture", () => {
    const harness = createHarness();
    const replacement = new EventTarget() as HTMLElement;
    pointer(harness.canvas, "pointerdown", 100, 100);
    harness.controller.attach(replacement);
    pointer(harness.canvas, "pointerup", 100, 100);
    pointer(replacement, "pointerup", 100, 100);
    expect(harness.onTap).not.toHaveBeenCalled();
    pointer(replacement, "pointerdown", 120, 120);
    pointer(replacement, "pointerup", 120, 120);
    expect(harness.onTap).toHaveBeenCalledOnce();
    harness.controller.detach();
    pointer(replacement, "pointerdown", 120, 120);
    pointer(replacement, "pointerup", 120, 120);
    expect(harness.onTap).toHaveBeenCalledOnce();
  });
});
