import { type VRM } from "@pixiv/three-vrm";
import * as THREE from "three";
import { describe, expect, it } from "vitest";

import { createHumanoidAnimationClip } from "../src/humanoid-animation";

function createVrm(hipsNode: THREE.Object3D): VRM {
  return {
    humanoid: {
      normalizedRestPose: { hips: { position: [0, 1, 0] } },
      getNormalizedBoneNode: (name: string) => (name === "hips" ? hipsNode : null),
    },
    meta: { metaVersion: "1" },
  } as unknown as VRM;
}

describe("Mixamo-style humanoid animation retargeting", () => {
  it("converts source rest rotation to normalized identity and scales hips", () => {
    const sourceRoot = new THREE.Group();
    const sourceParent = new THREE.Group();
    sourceParent.quaternion.setFromAxisAngle(new THREE.Vector3(0, 1, 0), Math.PI / 2);
    const sourceHips = new THREE.Bone();
    sourceHips.name = "mixamorigHips";
    sourceHips.position.y = 100;
    sourceHips.quaternion.setFromAxisAngle(new THREE.Vector3(1, 0, 0), Math.PI / 4);
    sourceParent.add(sourceHips);
    sourceRoot.add(sourceParent);
    sourceRoot.updateMatrixWorld(true);

    const clip = new THREE.AnimationClip("walk", 1, [
      new THREE.QuaternionKeyframeTrack(
        "mixamorigHips.quaternion",
        [0],
        sourceHips.quaternion.toArray(),
      ),
      new THREE.VectorKeyframeTrack(
        "mixamorigHips.position",
        [0, 1],
        [20, 100, 30, 50, 110, 70],
      ),
    ]);
    const targetHips = new THREE.Bone();
    targetHips.name = "normalizedHips";

    const result = createHumanoidAnimationClip(sourceRoot, clip, createVrm(targetHips));

    expect(result.name).toBe("walk");
    expect(result.tracks.map((track) => track.name)).toEqual([
      "normalizedHips.quaternion",
      "normalizedHips.position",
    ]);
    expect(Array.from(result.tracks[0]!.values)).toEqual(
      expect.arrayContaining([expect.closeTo(0), expect.closeTo(1)]),
    );
    expect(Array.from(result.tracks[1]!.values)).toEqual([
      expect.closeTo(0.2),
      expect.closeTo(1),
      expect.closeTo(0.3),
      expect.closeTo(0.2),
      expect.closeTo(1.1),
      expect.closeTo(0.3),
    ]);

    const fullRootMotion = createHumanoidAnimationClip(
      sourceRoot,
      clip,
      createVrm(targetHips),
      { rootMotion: "full" },
    );
    expect(Array.from(fullRootMotion.tracks[1]!.values).slice(3)).toEqual([
      expect.closeTo(0.5),
      expect.closeTo(1.1),
      expect.closeTo(0.7),
    ]);
  });

  it("supports namespaced Mixamo bone names", () => {
    const sourceRoot = new THREE.Group();
    const hips = new THREE.Bone();
    hips.name = "mixamorig:Hips";
    hips.position.y = 100;
    sourceRoot.add(hips);
    const targetHips = new THREE.Bone();
    targetHips.name = "targetHips";
    const clip = new THREE.AnimationClip("idle", 1, [
      new THREE.QuaternionKeyframeTrack("mixamorig:Hips.quaternion", [0], [0, 0, 0, 1]),
    ]);

    const result = createHumanoidAnimationClip(sourceRoot, clip, createVrm(targetHips));

    expect(result.tracks[0]?.name).toBe("targetHips.quaternion");
  });

  it("rejects clips without humanoid tracks", () => {
    const targetHips = new THREE.Bone();
    expect(() =>
      createHumanoidAnimationClip(
        new THREE.Group(),
        new THREE.AnimationClip("empty", 1, []),
        createVrm(targetHips),
      ),
    ).toThrow("no supported humanoid tracks");
  });
});
