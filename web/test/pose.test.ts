import { describe, expect, it } from "vitest";

import { parseNormalizedPose } from "../src/pose";

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
});
