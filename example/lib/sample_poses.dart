import 'package:flutter_three_vrm/flutter_three_vrm.dart';

// Adapted from the Apache-2.0 BASE_POSES in AnimationPresets.js:
// https://github.com/ruslanmv/3D-Avatar-Chatbot/blob/8e644f82d3587c60481e41825bc9798a6ee851d1/src/AnimationPresets.js
// The source Euler angles are converted to normalized VRM quaternions here.
final VrmPose presenterOpenPose = _pose(<VrmHumanBone, List<double>>{
  VrmHumanBone.leftUpperArm: <double>[10, 0, 28],
  VrmHumanBone.rightUpperArm: <double>[10, 0, -28],
  VrmHumanBone.leftLowerArm: <double>[0, -22, 0],
  VrmHumanBone.rightLowerArm: <double>[0, 22, 0],
  VrmHumanBone.hips: <double>[0, 0, -1],
  VrmHumanBone.spine: <double>[-2, 0, 1],
  VrmHumanBone.chest: <double>[-4, 0, 0],
  VrmHumanBone.head: <double>[4, 0, 0],
});

final VrmPose loungePose = _pose(<VrmHumanBone, List<double>>{
  VrmHumanBone.leftUpperArm: <double>[2, 0, 40],
  VrmHumanBone.rightUpperArm: <double>[8, 0, -30],
  VrmHumanBone.leftLowerArm: <double>[0, -8, 0],
  VrmHumanBone.rightLowerArm: <double>[0, 20, 0],
  VrmHumanBone.hips: <double>[2, 4, -5],
  VrmHumanBone.spine: <double>[-2, 2, 2],
  VrmHumanBone.chest: <double>[-3, 1, 0],
  VrmHumanBone.head: <double>[5, 0, 0],
});

VrmPose _pose(Map<VrmHumanBone, List<double>> eulerDegrees) {
  return VrmPose(<VrmHumanBone, VrmPoseTransform>{
    for (final entry in eulerDegrees.entries)
      entry.key: VrmPoseTransform(
        rotation: VrmQuaternion.fromEulerDegrees(
          entry.value[0],
          entry.value[1],
          entry.value[2],
        ),
      ),
  });
}
