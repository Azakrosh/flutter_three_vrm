import type { VRM } from "@pixiv/three-vrm";
import { Bone, Group } from "three";
import { describe, expect, it } from "vitest";

import { RuntimeGazeController } from "../src/gaze-controller";

function createGaze() {
  const head = new Bone();
  head.position.set(0, 1.6, 0);
  const scene = new Group();
  scene.add(head);
  scene.updateMatrixWorld(true);
  const vrm = {
    humanoid: {
      getNormalizedBoneNode: (name: string) => name === "head" ? head : null,
    },
  } as unknown as VRM;
  return new RuntimeGazeController(() => vrm, () => 0.5);
}

describe("runtime gaze controller", () => {
  it("moves only its eye target for an explicit command and returns to center", () => {
    const gaze = createGaze();
    gaze.setAutoSaccades(false);
    gaze.setTarget(1, 1.5, 2);
    gaze.update(0.1);
    expect(gaze.target.position.x).toBeLessThan(0);
    expect(gaze.target.position.y).toBeGreaterThan(0);
    gaze.update(1);
    const lastHeldX = gaze.target.position.x;
    gaze.update(0.1);
    expect(gaze.target.position.x).toBeGreaterThan(lastHeldX);
  });

  it("resets held gaze when the model changes", () => {
    const gaze = createGaze();
    gaze.setAutoSaccades(false);
    gaze.setTarget(1, 1.5);
    gaze.update(0.1);
    gaze.resetForModel();
    const previousX = gaze.target.position.x;
    gaze.update(0.1);
    expect(gaze.target.position.x).toBeGreaterThan(previousX);
  });

  it("keeps auto-saccades separate from explicit gaze", () => {
    const gaze = createGaze();
    gaze.update(0.1);
    expect(gaze.target.position.x).toBe(0);
    gaze.setAutoSaccades(false);
    gaze.update(0.1);
    expect(gaze.target.position.x).toBe(0);
  });
});
