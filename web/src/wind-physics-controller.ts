import type { VRMSpringBoneManager } from "@pixiv/three-vrm";
import { Vector3 } from "three";
import type {
  RuntimeWindDirection,
  RuntimeWindType,
} from "./interaction-protocol-codec";

type SpringJoint = VRMSpringBoneManager["joints"] extends Set<infer T>
  ? T
  : never;

interface JointBaseline {
  readonly stiffness: number;
  readonly gravityPower: number;
  readonly gravityDir: Vector3;
  readonly dragForce: number;
  modifiedGravityPower: number;
}

export interface RuntimeWindPhysicsDependencies {
  readonly getManager: () => VRMSpringBoneManager | null;
  readonly isPhysicsEnabled: () => boolean;
}

/** Applies spring-bone multipliers and simulated wind without mutating joint metadata. */
export class RuntimeWindPhysicsController {
  private baselines = new WeakMap<SpringJoint, JointBaseline>();
  private readonly currentWind = new Vector3();
  private readonly targetWind = new Vector3();
  private readonly windForce = new Vector3();
  private readonly windFluctuation = new Vector3();
  private readonly effectiveGravity = new Vector3();
  private currentVariation = 0;
  private targetVariation = 0;

  public constructor(private readonly dependencies: RuntimeWindPhysicsDependencies) {}

  public resetForModel(): void {
    this.baselines = new WeakMap<SpringJoint, JointBaseline>();
  }

  public setPhysics(stiffness = 1, gravity = 1, drag = 1): void {
    for (const [name, value] of Object.entries({ stiffness, gravity, drag })) {
      if (!Number.isFinite(value) || value < 0) {
        throw new TypeError(`${name} must be a non-negative finite number.`);
      }
    }
    const manager = this.dependencies.getManager();
    if (!manager) return;
    for (const joint of manager.joints) {
      const baseline = this.getBaseline(joint);
      joint.settings.stiffness = baseline.stiffness * stiffness;
      baseline.modifiedGravityPower = baseline.gravityPower * gravity;
      joint.settings.gravityPower = baseline.modifiedGravityPower;
      joint.settings.dragForce = baseline.dragForce * drag;
    }
  }

  public setWind(type: RuntimeWindType, direction: RuntimeWindDirection): void {
    if (type === "none") {
      this.stopWind();
      return;
    }
    const force = type === "light" ? 0.05
      : type === "strong" ? 0.15
      : type === "storm" ? 0.3
      : null;
    const variation = type === "light" ? 0.03
      : type === "strong" ? 0.1
      : type === "storm" ? 0.25
      : null;
    if (force === null || variation === null) {
      throw new TypeError("Unknown wind type.");
    }
    switch (direction) {
      case "left": this.targetWind.set(1, 0, 0); break;
      case "right": this.targetWind.set(-1, 0, 0); break;
      case "front": this.targetWind.set(0, 0, -1); break;
      case "back": this.targetWind.set(0, 0, 1); break;
      default: throw new TypeError("Unknown wind direction.");
    }
    this.targetWind.multiplyScalar(force);
    this.targetVariation = variation;
  }

  public stopWind(): void {
    this.targetWind.set(0, 0, 0);
    this.targetVariation = 0;
  }

  public update(delta: number, elapsedTime: number): void {
    if (!this.dependencies.isPhysicsEnabled()) return;
    const manager = this.dependencies.getManager();
    if (!manager) return;

    const factor = 1 - Math.exp(-1.5 * delta);
    this.currentWind.lerp(this.targetWind, factor);
    this.currentVariation +=
      (this.targetVariation - this.currentVariation) * factor;
    this.windForce.set(0, 0, 0);

    if (this.currentWind.lengthSq() > 0.000001 || this.currentVariation > 0.001) {
      const fluctuation =
        Math.sin(elapsedTime * 1.13) * 0.4 +
        Math.sin(elapsedTime * 2.71) * 0.3 +
        Math.sin(elapsedTime * 4.33) * 0.2 +
        Math.sin(elapsedTime * 7.97) * 0.1;
      this.windFluctuation.copy(this.currentWind).normalize();
      if (this.windFluctuation.lengthSq() === 0) {
        this.windFluctuation.set(1, 0, 0);
      }
      this.windFluctuation.multiplyScalar(fluctuation * this.currentVariation);
      this.windForce.copy(this.currentWind).add(this.windFluctuation);
    }

    for (const joint of manager.joints) {
      const baseline = this.getBaseline(joint);
      this.effectiveGravity.copy(baseline.gravityDir)
        .multiplyScalar(baseline.modifiedGravityPower)
        .add(this.windForce);
      if (this.effectiveGravity.lengthSq() > 0.000001) {
        joint.settings.gravityPower = this.effectiveGravity.length();
        joint.settings.gravityDir.copy(this.effectiveGravity).normalize();
      } else {
        joint.settings.gravityPower = 0;
        joint.settings.gravityDir.copy(baseline.gravityDir);
      }
    }
  }

  private getBaseline(joint: SpringJoint): JointBaseline {
    let baseline = this.baselines.get(joint);
    if (!baseline) {
      baseline = {
        stiffness: joint.settings.stiffness,
        gravityPower: joint.settings.gravityPower,
        gravityDir: joint.settings.gravityDir.clone(),
        dragForce: joint.settings.dragForce,
        modifiedGravityPower: joint.settings.gravityPower,
      };
      this.baselines.set(joint, baseline);
    }
    return baseline;
  }
}
