import type { VRMSpringBoneManager } from "@pixiv/three-vrm";
import { Vector3 } from "three";
import { describe, expect, it } from "vitest";

import { RuntimeWindPhysicsController } from "../src/wind-physics-controller";

function createHarness() {
  const joint = {
    settings: {
      stiffness: 2,
      gravityPower: 0.4,
      gravityDir: new Vector3(0, -1, 0),
      dragForce: 0.3,
    },
  };
  const manager = {
    joints: new Set([joint]),
  } as unknown as VRMSpringBoneManager;
  let enabled = true;
  const controller = new RuntimeWindPhysicsController({
    getManager: () => manager,
    isPhysicsEnabled: () => enabled,
  });
  return {
    joint,
    controller,
    setEnabled(value: boolean) { enabled = value; },
  };
}

describe("runtime wind and physics controller", () => {
  it("applies multipliers against original settings, not previously scaled values", () => {
    const { controller, joint } = createHarness();
    controller.setPhysics(1.5, 2, 0.5);
    expect(joint.settings.stiffness).toBe(3);
    expect(joint.settings.gravityPower).toBeCloseTo(0.8);
    expect(joint.settings.dragForce).toBeCloseTo(0.15);
    controller.setPhysics();
    controller.update(0.1, 0.1);
    expect(joint.settings.stiffness).toBe(2);
    expect(joint.settings.gravityPower).toBeCloseTo(0.4);
    expect(joint.settings.dragForce).toBeCloseTo(0.3);
    expect("userData" in joint).toBe(false);
  });

  it("smoothly applies wind and restores the base gravity after stop", () => {
    const { controller, joint } = createHarness();
    controller.setWind("strong", "left");
    controller.update(0.5, 1);
    expect(joint.settings.gravityDir.x).toBeGreaterThan(0);
    expect(joint.settings.gravityPower).toBeGreaterThan(0.4);

    controller.stopWind();
    for (let frame = 0; frame < 100; frame += 1) {
      controller.update(0.1, 1 + frame * 0.1);
    }
    expect(joint.settings.gravityPower).toBeCloseTo(0.4, 3);
    expect(joint.settings.gravityDir.x).toBeCloseTo(0, 3);
    expect(joint.settings.gravityDir.y).toBeCloseTo(-1, 3);
  });

  it("accepts spring settings while rendering physics is temporarily disabled", () => {
    const { controller, joint, setEnabled } = createHarness();
    setEnabled(false);
    controller.setPhysics(3, 2, 0.5);
    expect(joint.settings.stiffness).toBe(6);
    expect(joint.settings.gravityPower).toBeCloseTo(0.8);
    controller.setWind("light", "right");
    controller.update(0.5, 1);
    expect(joint.settings.gravityDir.x).toBe(0);
    setEnabled(true);
    controller.update(0.5, 2);
    expect(joint.settings.gravityDir.x).toBeLessThan(0);
  });

  it("forgets old model baselines and rejects malformed commands", () => {
    const { controller, joint } = createHarness();
    expect(() => controller.setPhysics(-1, 1, 1)).toThrow(TypeError);
    expect(() => controller.setWind("invalid", "left")).toThrow(TypeError);
    expect(() => controller.setWind("light", "up")).toThrow(TypeError);

    controller.setPhysics(2, 1, 1);
    controller.resetForModel();
    joint.settings.stiffness = 4;
    controller.setPhysics(2, 1, 1);
    expect(joint.settings.stiffness).toBe(8);
  });
});
