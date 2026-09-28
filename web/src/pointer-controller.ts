import { Vector2 } from "three";

import type { RuntimeCameraController } from "./camera-controller";

export interface RuntimePointerDependencies {
  readonly camera: Pick<
    RuntimeCameraController,
    "mode" | "setConstrainedPanTarget"
  >;
  readonly getPanOffset: () => Vector2;
  readonly getModelHeight: () => number;
  readonly hasModel: () => boolean;
  readonly getViewport: () => { width: number; height: number };
  readonly onTap: (x: number, y: number) => void;
  readonly onCameraChanged: () => void;
}

/** Owns canvas pointer listeners and constrained-pan gesture state. */
export class RuntimePointerController {
  private canvas: HTMLElement | null = null;
  private activePointerId: number | null = null;
  private readonly startPoint = new Vector2();
  private readonly startPan = new Vector2();
  private readonly onDown = (event: PointerEvent): void => this.handleDown(event);
  private readonly onMove = (event: PointerEvent): void => this.handleMove(event);
  private readonly onUp = (event: PointerEvent): void => this.handleEnd(event);

  public constructor(private readonly dependencies: RuntimePointerDependencies) {}

  public attach(canvas: HTMLElement): void {
    if (this.canvas === canvas) return;
    this.detach();
    this.canvas = canvas;
    canvas.addEventListener("pointerdown", this.onDown);
    canvas.addEventListener("pointermove", this.onMove);
    canvas.addEventListener("pointerup", this.onUp);
    canvas.addEventListener("pointercancel", this.onUp);
  }

  public detach(): void {
    const canvas = this.canvas;
    this.canvas = null;
    this.activePointerId = null;
    if (!canvas) return;
    canvas.removeEventListener("pointerdown", this.onDown);
    canvas.removeEventListener("pointermove", this.onMove);
    canvas.removeEventListener("pointerup", this.onUp);
    canvas.removeEventListener("pointercancel", this.onUp);
  }

  private handleDown(event: PointerEvent): void {
    if (!event.isPrimary || this.activePointerId !== null) return;
    this.activePointerId = event.pointerId;
    this.startPoint.set(event.clientX, event.clientY);
    this.startPan.copy(this.dependencies.getPanOffset());
  }

  private handleMove(event: PointerEvent): void {
    if (!event.isPrimary || event.pointerId !== this.activePointerId) return;
    const viewport = this.dependencies.getViewport();
    this.dependencies.camera.setConstrainedPanTarget({
      deltaX: event.clientX - this.startPoint.x,
      deltaY: event.clientY - this.startPoint.y,
      viewportWidth: viewport.width,
      viewportHeight: viewport.height,
      startPan: this.startPan,
      modelHeight: this.dependencies.getModelHeight(),
    });
  }

  private handleEnd(event: PointerEvent): void {
    if (!event.isPrimary || event.pointerId !== this.activePointerId) return;
    this.activePointerId = null;
    const distance = Math.hypot(
      event.clientX - this.startPoint.x,
      event.clientY - this.startPoint.y,
    );
    if (event.type === "pointerup" && distance < 10) {
      if (this.dependencies.hasModel()) {
        this.dependencies.onTap(event.clientX, event.clientY);
      }
    } else if (
      distance >= 10 &&
      this.dependencies.camera.mode === "constrained"
    ) {
      this.dependencies.onCameraChanged();
    }
  }
}
