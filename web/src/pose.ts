import {
  VRMHumanBoneName,
  type VRM,
  type VRMPose,
  type VRMPoseTransform,
} from "@pixiv/three-vrm";
import {
  AnimationClip,
  QuaternionKeyframeTrack,
  VectorKeyframeTrack,
  type KeyframeTrack,
} from "three";

const humanBoneNames = new Set<string>(Object.values(VRMHumanBoneName));

export function parseNormalizedPose(value: unknown): VRMPose {
  if (!isRecord(value)) {
    throw new TypeError("A VRM pose must be an object.");
  }

  const pose: VRMPose = {};
  for (const [boneName, rawTransform] of Object.entries(value)) {
    if (!humanBoneNames.has(boneName)) {
      throw new TypeError(`Unknown VRM humanoid bone: ${boneName}.`);
    }
    if (!isRecord(rawTransform)) {
      throw new TypeError(`Transform for ${boneName} must be an object.`);
    }

    const transform: VRMPoseTransform = {};
    if (rawTransform.position !== undefined) {
      transform.position = readTuple(rawTransform.position, 3, `${boneName}.position`);
    }
    if (rawTransform.rotation !== undefined) {
      const rotation = readTuple(rawTransform.rotation, 4, `${boneName}.rotation`);
      const magnitude = Math.hypot(...rotation);
      if (magnitude < 1e-8) {
        throw new TypeError(`${boneName}.rotation must not be a zero quaternion.`);
      }
      transform.rotation = rotation.map((component) => component / magnitude) as [
        number,
        number,
        number,
        number,
      ];
    }
    pose[boneName as keyof VRMPose] = transform;
  }
  return pose;
}

export function getNormalizedPose(vrm: VRM | null): VRMPose {
  return clonePose(requireHumanoid(vrm).getNormalizedPose());
}

export function setNormalizedPose(vrm: VRM | null, value: unknown): void {
  requireHumanoid(vrm).setNormalizedPose(parseNormalizedPose(value));
}

export function resetNormalizedPose(vrm: VRM | null): void {
  requireHumanoid(vrm).resetNormalizedPose();
}

export function createNormalizedPoseClip(
  vrm: VRM | null,
  value: unknown,
  name = "Pose",
): AnimationClip {
  const humanoid = requireHumanoid(vrm);
  const pose = parseNormalizedPose(value);
  const tracks: KeyframeTrack[] = [];

  for (const [boneName, transform] of Object.entries(pose)) {
    const node = humanoid.getNormalizedBoneNode(
      boneName as keyof VRMPose,
    );
    if (node === null) continue;

    if (transform.position !== undefined) {
      tracks.push(
        new VectorKeyframeTrack(
          `${node.name}.position`,
          [0, 1],
          [...transform.position, ...transform.position],
        ),
      );
    }
    if (transform.rotation !== undefined) {
      tracks.push(
        new QuaternionKeyframeTrack(
          `${node.name}.quaternion`,
          [0, 1],
          [...transform.rotation, ...transform.rotation],
        ),
      );
    }
  }

  if (Object.keys(pose).length > 0 && tracks.length === 0) {
    throw new Error("The pose does not target any bones available in this VRM.");
  }
  return new AnimationClip(name, 1, tracks);
}

function requireHumanoid(vrm: VRM | null): VRM["humanoid"] {
  if (!vrm?.humanoid) {
    throw new Error("Load a VRM model before using the Pose API.");
  }
  return vrm.humanoid;
}

function clonePose(pose: VRMPose): VRMPose {
  const result: VRMPose = {};
  for (const [boneName, transform] of Object.entries(pose)) {
    result[boneName as keyof VRMPose] = {
      ...(transform.position === undefined
        ? {}
        : { position: [...transform.position] as [number, number, number] }),
      ...(transform.rotation === undefined
        ? {}
        : { rotation: [...transform.rotation] as [number, number, number, number] }),
    };
  }
  return result;
}

function readTuple<const Length extends 3 | 4>(
  value: unknown,
  length: Length,
  fieldName: string,
): Length extends 3 ? [number, number, number] : [number, number, number, number] {
  if (!Array.isArray(value) || value.length !== length) {
    throw new TypeError(`${fieldName} must contain exactly ${length} numbers.`);
  }
  const result = value.map((component) => {
    if (typeof component !== "number" || !Number.isFinite(component)) {
      throw new TypeError(`${fieldName} contains a non-finite number.`);
    }
    return component;
  });
  return result as Length extends 3
    ? [number, number, number]
    : [number, number, number, number];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
