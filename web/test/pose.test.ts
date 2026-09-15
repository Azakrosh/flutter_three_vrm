import { Object3D } from "three";
import type { VRM } from "@pixiv/three-vrm";
import { describe, expect, it } from "vitest";

import { createNormalizedPoseClip, parseNormalizedPose } from "../src/pose";

describe("normalized VRM pose", () => {
  it("parses bone transforms and normalizes quaternions", () => {
    expect(
      parseNormalizedPose({
        hips: { position: [0, 0.25, 0] },
        head: { rotation: [0, 0, 0, 2] },
      }),
    ).toEqual({
      hips: { position: [0, 0.25, 0] },
      head: { rotation: [0, 0, 0, 1] },
    });
  });

  it("rejects unknown humanoid bones", () => {
    expect(() => parseNormalizedPose({ tail: { rotation: [0, 0, 0, 1] } })).toThrow(
      "Unknown VRM humanoid bone",
    );
  });

  it("rejects invalid vectors and zero quaternions", () => {
    expect(() => parseNormalizedPose({ hips: { position: [0, 1] } })).toThrow(
      "exactly 3 numbers",
    );
    expect(() => parseNormalizedPose({ head: { rotation: [0, 0, 0, 0] } })).toThrow(
      "zero quaternion",
    );
  });

  it("creates a constant mixer clip for an available normalized bone", () => {
    const head = new Object3D();
    head.name = "normalizedHead";
    const vrm = {
      humanoid: {
        getNormalizedBoneNode: (name: string) => (name === "head" ? head : null),
      },
    } as unknown as VRM;

    const clip = createNormalizedPoseClip(vrm, {
      head: { rotation: [0, 0, 0, 2] },
    });

    expect(clip.duration).toBe(1);
    expect(clip.tracks).toHaveLength(1);
    expect(clip.tracks[0]?.name).toBe("normalizedHead.quaternion");
    expect(Array.from(clip.tracks[0]?.values ?? [])).toEqual([
      0, 0, 0, 1,
      0, 0, 0, 1,
    ]);
  });
});
