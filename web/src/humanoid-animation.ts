import { VRMHumanBoneName, type VRM, type VRMHumanBoneName as BoneName } from "@pixiv/three-vrm";
import * as THREE from "three";

const sourceRigMap = {
  hips: VRMHumanBoneName.Hips,
  spine: VRMHumanBoneName.Spine,
  spine1: VRMHumanBoneName.Chest,
  spine2: VRMHumanBoneName.UpperChest,
  chest: VRMHumanBoneName.Chest,
  upperchest: VRMHumanBoneName.UpperChest,
  neck: VRMHumanBoneName.Neck,
  head: VRMHumanBoneName.Head,
  lefteye: VRMHumanBoneName.LeftEye,
  righteye: VRMHumanBoneName.RightEye,
  jaw: VRMHumanBoneName.Jaw,
  leftshoulder: VRMHumanBoneName.LeftShoulder,
  leftarm: VRMHumanBoneName.LeftUpperArm,
  leftupperarm: VRMHumanBoneName.LeftUpperArm,
  leftforearm: VRMHumanBoneName.LeftLowerArm,
  leftlowerarm: VRMHumanBoneName.LeftLowerArm,
  lefthand: VRMHumanBoneName.LeftHand,
  rightshoulder: VRMHumanBoneName.RightShoulder,
  rightarm: VRMHumanBoneName.RightUpperArm,
  rightupperarm: VRMHumanBoneName.RightUpperArm,
  rightforearm: VRMHumanBoneName.RightLowerArm,
  rightlowerarm: VRMHumanBoneName.RightLowerArm,
  righthand: VRMHumanBoneName.RightHand,
  leftupleg: VRMHumanBoneName.LeftUpperLeg,
  leftupperleg: VRMHumanBoneName.LeftUpperLeg,
  leftleg: VRMHumanBoneName.LeftLowerLeg,
  leftlowerleg: VRMHumanBoneName.LeftLowerLeg,
  leftfoot: VRMHumanBoneName.LeftFoot,
  lefttoebase: VRMHumanBoneName.LeftToes,
  lefttoes: VRMHumanBoneName.LeftToes,
  rightupleg: VRMHumanBoneName.RightUpperLeg,
  rightupperleg: VRMHumanBoneName.RightUpperLeg,
  rightleg: VRMHumanBoneName.RightLowerLeg,
  rightlowerleg: VRMHumanBoneName.RightLowerLeg,
  rightfoot: VRMHumanBoneName.RightFoot,
  righttoebase: VRMHumanBoneName.RightToes,
  righttoes: VRMHumanBoneName.RightToes,
  lefthandthumb1: VRMHumanBoneName.LeftThumbMetacarpal,
  lefthandthumb2: VRMHumanBoneName.LeftThumbProximal,
  lefthandthumb3: VRMHumanBoneName.LeftThumbDistal,
  leftthumbmetacarpal: VRMHumanBoneName.LeftThumbMetacarpal,
  leftthumbproximal: VRMHumanBoneName.LeftThumbProximal,
  leftthumbdistal: VRMHumanBoneName.LeftThumbDistal,
  lefthandindex1: VRMHumanBoneName.LeftIndexProximal,
  lefthandindex2: VRMHumanBoneName.LeftIndexIntermediate,
  lefthandindex3: VRMHumanBoneName.LeftIndexDistal,
  leftindexproximal: VRMHumanBoneName.LeftIndexProximal,
  leftindexintermediate: VRMHumanBoneName.LeftIndexIntermediate,
  leftindexdistal: VRMHumanBoneName.LeftIndexDistal,
  lefthandmiddle1: VRMHumanBoneName.LeftMiddleProximal,
  lefthandmiddle2: VRMHumanBoneName.LeftMiddleIntermediate,
  lefthandmiddle3: VRMHumanBoneName.LeftMiddleDistal,
  leftmiddleproximal: VRMHumanBoneName.LeftMiddleProximal,
  leftmiddleintermediate: VRMHumanBoneName.LeftMiddleIntermediate,
  leftmiddledistal: VRMHumanBoneName.LeftMiddleDistal,
  lefthandring1: VRMHumanBoneName.LeftRingProximal,
  lefthandring2: VRMHumanBoneName.LeftRingIntermediate,
  lefthandring3: VRMHumanBoneName.LeftRingDistal,
  leftringproximal: VRMHumanBoneName.LeftRingProximal,
  leftringintermediate: VRMHumanBoneName.LeftRingIntermediate,
  leftringdistal: VRMHumanBoneName.LeftRingDistal,
  lefthandpinky1: VRMHumanBoneName.LeftLittleProximal,
  lefthandpinky2: VRMHumanBoneName.LeftLittleIntermediate,
  lefthandpinky3: VRMHumanBoneName.LeftLittleDistal,
  leftlittleproximal: VRMHumanBoneName.LeftLittleProximal,
  leftlittleintermediate: VRMHumanBoneName.LeftLittleIntermediate,
  leftlittledistal: VRMHumanBoneName.LeftLittleDistal,
  righthandthumb1: VRMHumanBoneName.RightThumbMetacarpal,
  righthandthumb2: VRMHumanBoneName.RightThumbProximal,
  righthandthumb3: VRMHumanBoneName.RightThumbDistal,
  rightthumbmetacarpal: VRMHumanBoneName.RightThumbMetacarpal,
  rightthumbproximal: VRMHumanBoneName.RightThumbProximal,
  rightthumbdistal: VRMHumanBoneName.RightThumbDistal,
  righthandindex1: VRMHumanBoneName.RightIndexProximal,
  righthandindex2: VRMHumanBoneName.RightIndexIntermediate,
  righthandindex3: VRMHumanBoneName.RightIndexDistal,
  rightindexproximal: VRMHumanBoneName.RightIndexProximal,
  rightindexintermediate: VRMHumanBoneName.RightIndexIntermediate,
  rightindexdistal: VRMHumanBoneName.RightIndexDistal,
  righthandmiddle1: VRMHumanBoneName.RightMiddleProximal,
  righthandmiddle2: VRMHumanBoneName.RightMiddleIntermediate,
  righthandmiddle3: VRMHumanBoneName.RightMiddleDistal,
  rightmiddleproximal: VRMHumanBoneName.RightMiddleProximal,
  rightmiddleintermediate: VRMHumanBoneName.RightMiddleIntermediate,
  rightmiddledistal: VRMHumanBoneName.RightMiddleDistal,
  righthandring1: VRMHumanBoneName.RightRingProximal,
  righthandring2: VRMHumanBoneName.RightRingIntermediate,
  righthandring3: VRMHumanBoneName.RightRingDistal,
  rightringproximal: VRMHumanBoneName.RightRingProximal,
  rightringintermediate: VRMHumanBoneName.RightRingIntermediate,
  rightringdistal: VRMHumanBoneName.RightRingDistal,
  righthandpinky1: VRMHumanBoneName.RightLittleProximal,
  righthandpinky2: VRMHumanBoneName.RightLittleIntermediate,
  righthandpinky3: VRMHumanBoneName.RightLittleDistal,
  rightlittleproximal: VRMHumanBoneName.RightLittleProximal,
  rightlittleintermediate: VRMHumanBoneName.RightLittleIntermediate,
  rightlittledistal: VRMHumanBoneName.RightLittleDistal,
} as const satisfies Readonly<Record<string, BoneName>>;

export interface HumanoidAnimationOptions {
  readonly rootMotion?: "inPlace" | "full";
}

/** Retargets a Mixamo-style glTF/GLB clip to a VRM normalized humanoid. */
export function createHumanoidAnimationClip(
  sourceRoot: THREE.Object3D,
  sourceClip: THREE.AnimationClip,
  vrm: VRM,
  options: HumanoidAnimationOptions = {},
): THREE.AnimationClip {
  if (!vrm.humanoid) {
    throw new Error("The loaded VRM does not expose a humanoid skeleton.");
  }

  sourceRoot.updateMatrixWorld(true);
  const tracks: THREE.KeyframeTrack[] = [];

  for (const sourceTrack of sourceClip.tracks) {
    const binding = parseTrackBinding(sourceTrack.name);
    if (binding === null) continue;

    const boneName = resolveBoneName(binding.nodeName);
    if (boneName === null) continue;

    const sourceNode = findSourceNode(sourceRoot, binding.nodeName, boneName);
    const targetNode = vrm.humanoid.getNormalizedBoneNode(boneName);
    if (sourceNode === null || targetNode === null) continue;

    if (sourceTrack instanceof THREE.QuaternionKeyframeTrack && binding.property === "quaternion") {
      tracks.push(retargetQuaternionTrack(sourceTrack, sourceNode, targetNode.name, vrm));
    } else if (
      sourceTrack instanceof THREE.VectorKeyframeTrack &&
      binding.property === "position" &&
      boneName === VRMHumanBoneName.Hips
    ) {
      tracks.push(retargetHipsPositionTrack(sourceTrack, sourceNode, targetNode.name, vrm, options));
    }
  }

  if (tracks.length === 0) {
    throw new Error(
      "The glTF/GLB clip contains no supported humanoid tracks. Export a Mixamo-style skeleton with bone animation.",
    );
  }

  return new THREE.AnimationClip(sourceClip.name || "vrmAnimation", sourceClip.duration, tracks);
}

function retargetQuaternionTrack(
  sourceTrack: THREE.QuaternionKeyframeTrack,
  sourceNode: THREE.Object3D,
  targetNodeName: string,
  vrm: VRM,
): THREE.QuaternionKeyframeTrack {
  const restWorldInverse = sourceNode.getWorldQuaternion(new THREE.Quaternion()).invert();
  const parentRestWorld = sourceNode.parent?.getWorldQuaternion(new THREE.Quaternion()) ?? new THREE.Quaternion();
  const quaternion = new THREE.Quaternion();
  const values = new Float32Array(sourceTrack.values.length);

  for (let index = 0; index < sourceTrack.values.length; index += 4) {
    quaternion
      .fromArray(sourceTrack.values, index)
      .premultiply(parentRestWorld)
      .multiply(restWorldInverse)
      .normalize();
    quaternion.toArray(values, index);
  }

  if (vrm.meta?.metaVersion === "0") {
    for (let index = 0; index < values.length; index += 4) {
      values[index] = -values[index]!;
      values[index + 2] = -values[index + 2]!;
    }
  }

  return new THREE.QuaternionKeyframeTrack(
    `${targetNodeName}.quaternion`,
    sourceTrack.times.slice(),
    values,
  );
}

function retargetHipsPositionTrack(
  sourceTrack: THREE.VectorKeyframeTrack,
  sourceHips: THREE.Object3D,
  targetNodeName: string,
  vrm: VRM,
  options: HumanoidAnimationOptions,
): THREE.VectorKeyframeTrack {
  const sourceHipsHeight = Math.abs(sourceHips.position.y);
  const targetHipsHeight = Math.abs(vrm.humanoid.normalizedRestPose.hips?.position?.[1] ?? 0);
  if (sourceHipsHeight < 1e-6 || targetHipsHeight < 1e-6) {
    throw new Error("Cannot retarget hips translation because a rest-pose hips height is zero.");
  }

  const scale = targetHipsHeight / sourceHipsHeight;
  const values = Float32Array.from(sourceTrack.values, (value) => value * scale);
  if ((options.rootMotion ?? "inPlace") === "inPlace" && values.length >= 3) {
    const originX = values[0]!;
    const originZ = values[2]!;
    for (let index = 0; index < values.length; index += 3) {
      values[index] = originX;
      values[index + 2] = originZ;
    }
  }
  if (vrm.meta?.metaVersion === "0") {
    for (let index = 0; index < values.length; index += 3) {
      values[index] = -values[index]!;
      values[index + 2] = -values[index + 2]!;
    }
  }

  return new THREE.VectorKeyframeTrack(
    `${targetNodeName}.position`,
    sourceTrack.times.slice(),
    values,
  );
}

function parseTrackBinding(trackName: string): { nodeName: string; property: string } | null {
  const separator = trackName.lastIndexOf(".");
  if (separator <= 0 || separator === trackName.length - 1) return null;

  const path = trackName.slice(0, separator);
  const boneBinding = /\.bones\[([^\]]+)\]$/.exec(path);
  return {
    nodeName: boneBinding?.[1] ?? path,
    property: trackName.slice(separator + 1),
  };
}

function resolveBoneName(sourceName: string): BoneName | null {
  const leafName = sourceName.split(/[|:/\\]/).at(-1) ?? sourceName;
  const key = leafName.toLowerCase().replace(/^mixamorig/, "").replace(/[^a-z0-9]/g, "");
  return sourceRigMap[key as keyof typeof sourceRigMap] ?? null;
}

function findSourceNode(
  sourceRoot: THREE.Object3D,
  sourceName: string,
  boneName: BoneName,
): THREE.Object3D | null {
  const exact = sourceRoot.getObjectByName(sourceName);
  if (exact !== undefined) return exact;

  let match: THREE.Object3D | null = null;
  sourceRoot.traverse((node) => {
    if (match === null && resolveBoneName(node.name) === boneName) match = node;
  });
  return match;
}
