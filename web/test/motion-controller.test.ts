import type { VRM } from "@pixiv/three-vrm";
import {
  AnimationClip,
  AnimationMixer,
  Bone,
  Group,
  QuaternionKeyframeTrack,
} from "three";
import type { GLTF } from "three/addons/loaders/GLTFLoader.js";
import { describe, expect, it, vi } from "vitest";

import { RuntimeMotionController } from "../src/motion-controller";
import { MotionTransitionController } from "../src/motion-transition";

describe("runtime motion controller", () => {
  it("keeps missing-model Pose and rest errors stable", () => {
    const harness = createHarness();
    harness.setLoaded(false);
    expect(() => harness.controller.getPose()).toThrow(
      "Load a VRM model before using the Pose API.",
    );
    expect(() => harness.controller.setPose({}, 0.2)).toThrow(
      "Load a VRM model before using the Pose API.",
    );
    expect(() => harness.controller.transitionToRest(0.2)).toThrow(
      "Load a VRM model before stopping its motion.",
    );
  });

  it("crossfades Pose to rest and finalizes after fade-out", () => {
    const harness = createHarness();
    expect(harness.controller.getPose()).toEqual({});
    harness.controller.setPose({
      hips: { rotation: [0, 0, 0, 1] },
    }, 0);
    expect(harness.transitions.currentSource).toBe("pose");
    expect(harness.controller.isActive).toBe(true);

    harness.controller.transitionToRest(0.5);
    expect(harness.transitions.currentAction).toBeNull();
    expect(harness.controller.isActive).toBe(true);
    harness.controller.update(0.25);
    expect(harness.finalizeRestPose).not.toHaveBeenCalled();
    harness.controller.update(0.25);
    expect(harness.finalizeRestPose).toHaveBeenCalledOnce();
    expect(harness.controller.isActive).toBe(false);
    harness.controller.update(0.1);
    expect(harness.finalizeRestPose).toHaveBeenCalledOnce();
  });

  it("retargets a glTF clip and reports completion once for its playback ID", () => {
    const harness = createHarness();
    const source = new Group();
    const sourceHips = new Bone();
    sourceHips.name = "mixamorigHips";
    source.add(sourceHips);
    const clip = new AnimationClip("Wave", 1, [
      new QuaternionKeyframeTrack(
        "mixamorigHips.quaternion",
        [0, 1],
        [0, 0, 0, 1, 0, 0, 0, 1],
      ),
    ]);
    const gltf = {
      scene: source,
      animations: [clip],
      userData: {},
    } as unknown as GLTF;

    harness.controller.playLoadedAnimation(gltf, {
      playbackId: "play-1",
      clipName: "Wave",
      fadeDuration: 0,
      loop: false,
    });
    expect(harness.transitions.currentSource).toBe("clip");
    expect(harness.onStarted).toHaveBeenCalledWith({
      name: "Wave",
      playbackId: "play-1",
    });
    harness.controller.update(1);
    harness.controller.update(0.1);
    expect(harness.onFinished).toHaveBeenCalledOnce();
    expect(harness.onFinished).toHaveBeenCalledWith({
      name: "Wave",
      playbackId: "play-1",
    });
  });

  it("isolates control commands and rejects unavailable clips", () => {
    const harness = createHarness();
    harness.controller.pause();
    expect(harness.controller.isPaused).toBe(true);
    expect(harness.mixer.timeScale).toBe(0);
    harness.controller.resume(1.5);
    expect(harness.controller.isPaused).toBe(false);
    expect(harness.mixer.timeScale).toBe(1);
    expect(() => harness.controller.playLoadedAnimation({
      scene: new Group(),
      animations: [],
      userData: {},
    } as unknown as GLTF, { playbackId: "missing" })).toThrow(
      "No VRMA or glTF animation clip was found.",
    );
    expect(() => harness.controller.playLoadedAnimation({
      scene: new Group(),
      animations: [],
      userData: {},
    } as unknown as GLTF, {})).toThrow(
      "playbackId must be a non-empty string.",
    );
    expect(() => harness.controller.playLoadedAnimation({
      scene: new Group(),
      animations: [],
      userData: {},
    } as unknown as GLTF, {
      playbackId: "invalid",
      speed: "fast",
    })).toThrow("speed must be a positive finite number.");
  });
});

function createHarness() {
  const root = new Group();
  const targetHips = new Bone();
  targetHips.name = "normalizedHips";
  root.add(targetHips);
  const mixer = new AnimationMixer(root);
  const transitions = new MotionTransitionController(mixer);
  const finalizeRestPose = vi.fn();
  const onStarted = vi.fn();
  const onFinished = vi.fn();
  const vrm = {
    scene: root,
    humanoid: {
      getNormalizedPose: () => ({}),
      getNormalizedBoneNode: (name: string) =>
        name === "hips" ? targetHips : null,
    },
    meta: { metaVersion: "1" },
    update: vi.fn(),
  } as unknown as VRM;
  let loaded = true;
  const controller = new RuntimeMotionController({
    getVrm: () => loaded ? vrm : null,
    getTransitions: () => loaded ? transitions : null,
    finalizeRestPose,
    onStarted,
    onFinished,
  });
  return {
    controller,
    mixer,
    transitions,
    finalizeRestPose,
    onStarted,
    onFinished,
    setLoaded(value: boolean) { loaded = value; },
  };
}
