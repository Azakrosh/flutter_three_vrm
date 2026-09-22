import type { VRM } from "@pixiv/three-vrm";
import { MathUtils, Object3D, Vector3 } from "three";

/** Owns programmatic VRM eye gaze; pointer events never change this state. */
export class RuntimeGazeController {
  public readonly target = new Object3D();

  private readonly defaultPosition = new Vector3(0, 1.4, 2.1);
  private readonly desiredPosition = new Vector3(0, 1.4, 2.1);
  private readonly targetSaccadeOffset = new Vector3();
  private readonly currentSaccadeOffset = new Vector3();
  private holdRemaining = 0;
  private holdDuration = 1;
  private saccadeRemaining = 0;
  private autoSaccades = true;

  public constructor(
    private readonly getVrm: () => VRM | null,
    private readonly random: () => number = Math.random,
  ) {}

  public setTarget(x: number, y: number, z = 2.1): void {
    this.desiredPosition.set(-x, y, z || 2.1);
    this.holdRemaining = this.holdDuration;
  }

  public setAutoSaccades(enabled: boolean): void {
    this.autoSaccades = enabled;
    if (!enabled) this.targetSaccadeOffset.set(0, 0, 0);
  }

  public setHoldDuration(seconds: number): void {
    this.holdDuration = seconds;
  }

  public resetForModel(): void {
    this.holdRemaining = 0;
    this.desiredPosition.copy(this.defaultPosition);
    this.targetSaccadeOffset.set(0, 0, 0);
    this.currentSaccadeOffset.set(0, 0, 0);
    this.saccadeRemaining = 0;
  }

  public update(delta: number): void {
    const vrm = this.getVrm();
    if (!vrm) return;

    const head = vrm.humanoid?.getNormalizedBoneNode("head")
      ?? vrm.humanoid?.getRawBoneNode("head");
    if (head) {
      head.getWorldPosition(this.defaultPosition);
      this.defaultPosition.y -= 0.05;
      this.defaultPosition.z += 2;
    }

    if (this.holdRemaining > 0) {
      this.holdRemaining -= delta;
    } else {
      this.desiredPosition.copy(this.defaultPosition);
    }

    if (this.autoSaccades && this.holdRemaining <= 0) {
      this.saccadeRemaining -= delta;
      if (this.saccadeRemaining <= 0) {
        this.saccadeRemaining = 0.5 + this.random() * 2;
        this.targetSaccadeOffset.set(
          (this.random() - 0.5) * 0.4,
          (this.random() - 0.5) * 0.2,
          0,
        );
      }
    } else {
      this.targetSaccadeOffset.set(0, 0, 0);
    }

    this.currentSaccadeOffset.lerp(this.targetSaccadeOffset, 0.5);
    this.target.position.x = MathUtils.lerp(
      this.target.position.x,
      this.desiredPosition.x + this.currentSaccadeOffset.x,
      0.15,
    );
    this.target.position.y = MathUtils.lerp(
      this.target.position.y,
      this.desiredPosition.y + this.currentSaccadeOffset.y,
      0.15,
    );
    this.target.position.z = MathUtils.lerp(
      this.target.position.z,
      this.desiredPosition.z + this.currentSaccadeOffset.z,
      0.15,
    );
  }
}
