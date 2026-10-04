import { PerspectiveCamera } from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { describe, expect, it } from "vitest";

interface OrbitControlsPointerInternals {
  _onPointerDown(event: PointerEvent): void;
  _onPointerMove(event: PointerEvent): void;
  _onPointerUp(event: PointerEvent): void;
}

class FakeControlsElement extends EventTarget {
  public readonly style: Record<string, string> = {};
  public readonly ownerDocument = new EventTarget();
  public clientWidth = 400;
  public clientHeight = 800;

  public getRootNode(): EventTarget {
    return this.ownerDocument;
  }

  public setPointerCapture(): void {}
  public releasePointerCapture(): void {}
}

describe("patched OrbitControls touch lifecycle", () => {
  it("ends a constrained pinch before the remaining pointer moves", () => {
    const camera = new PerspectiveCamera(36, 0.5, 0.1, 20);
    camera.position.set(0, 1.5, 2);
    const element = new FakeControlsElement();
    const controls = new OrbitControls(
      camera,
      element as unknown as HTMLElement,
    );
    controls.enableZoom = true;
    controls.enablePan = false;
    controls.enableRotate = false;
    const pointers = controls as unknown as OrbitControlsPointerInternals;

    pointers._onPointerDown(touchEvent(1, 120, 300, true));
    pointers._onPointerDown(touchEvent(2, 280, 300, false));
    pointers._onPointerMove(touchEvent(2, 300, 300, false));

    expect(() => {
      pointers._onPointerUp(touchEvent(2, 300, 300, false));
      pointers._onPointerMove(touchEvent(1, 120, 300, true));
    }).not.toThrow();
    expect(camera.position.toArray().every(Number.isFinite)).toBe(true);

    pointers._onPointerUp(touchEvent(1, 120, 300, true));
    controls.dispose();
  });
});

function touchEvent(
  pointerId: number,
  x: number,
  y: number,
  isPrimary: boolean,
): PointerEvent {
  return {
    pointerId,
    pointerType: "touch",
    pageX: x,
    pageY: y,
    clientX: x,
    clientY: y,
    isPrimary,
    preventDefault() {},
  } as PointerEvent;
}
