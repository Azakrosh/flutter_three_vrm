import {
  AnimationClip,
  AnimationMixer,
  Object3D,
  Quaternion,
  QuaternionKeyframeTrack,
} from "three";
import { describe, expect, it } from "vitest";

import { MotionTransitionController } from "../src/motion-transition";

describe("MotionTransitionController", () => {
  it("crossfades clip to pose and then smoothly returns to rest", () => {
    const root = new Object3D();
    const bone = new Object3D();
    bone.name = "head";
    root.add(bone);
    const mixer = new AnimationMixer(root);
    const transitions = new MotionTransitionController(mixer);
    const left = new Quaternion().setFromAxisAngle(
      { x: 0, y: 1, z: 0 },
      -Math.PI / 3,
    );
    const right = new Quaternion().setFromAxisAngle(
      { x: 0, y: 1, z: 0 },
      Math.PI / 3,
    );

    transitions.transitionTo(constantClip("left", left), {
      source: "clip",
      fadeDuration: 0,
    });
    transitions.update(0);
    expect(bone.quaternion.angleTo(left)).toBeLessThan(1e-3);

    transitions.transitionTo(constantClip("right", right), {
      source: "pose",
      fadeDuration: 1,
    });
    transitions.update(0.5);
    expect(bone.quaternion.angleTo(left)).toBeGreaterThan(0.1);
    expect(bone.quaternion.angleTo(right)).toBeGreaterThan(0.1);

    transitions.update(0.5);
    expect(bone.quaternion.angleTo(right)).toBeLessThan(1e-3);

    transitions.transitionToRest(1);
    expect(transitions.isActive).toBe(true);
    transitions.update(0.5);
    expect(transitions.isActive).toBe(true);
    expect(bone.quaternion.angleTo(right)).toBeGreaterThan(0.1);
    expect(bone.quaternion.angleTo(new Quaternion())).toBeGreaterThan(0.1);

    transitions.update(0.5);
    expect(bone.quaternion.angleTo(new Quaternion())).toBeLessThan(1e-3);
    expect(transitions.isActive).toBe(false);
  });

  it("rejects invalid transition parameters", () => {
    const transitions = new MotionTransitionController(
      new AnimationMixer(new Object3D()),
    );
    const clip = new AnimationClip("empty", 1, []);
    expect(() =>
      transitions.transitionTo(clip, {
        source: "pose",
        fadeDuration: -1,
      }),
    ).toThrow("fadeDuration");
    expect(() =>
      transitions.transitionTo(clip, { source: "clip", speed: 0 }),
    ).toThrow("speed");
  });
});

function constantClip(name: string, quaternion: Quaternion): AnimationClip {
  return new AnimationClip(name, 1, [
    new QuaternionKeyframeTrack(
      "head.quaternion",
      [0, 1],
      [...quaternion.toArray(), ...quaternion.toArray()],
    ),
  ]);
}
