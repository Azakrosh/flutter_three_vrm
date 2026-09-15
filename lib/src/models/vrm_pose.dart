import 'dart:math' as math;

/// Standard humanoid bones defined by VRM 1.0.
enum VrmHumanBone {
  hips,
  spine,
  chest,
  upperChest,
  neck,
  head,
  leftEye,
  rightEye,
  jaw,
  leftUpperLeg,
  leftLowerLeg,
  leftFoot,
  leftToes,
  rightUpperLeg,
  rightLowerLeg,
  rightFoot,
  rightToes,
  leftShoulder,
  leftUpperArm,
  leftLowerArm,
  leftHand,
  rightShoulder,
  rightUpperArm,
  rightLowerArm,
  rightHand,
  leftThumbMetacarpal,
  leftThumbProximal,
  leftThumbDistal,
  leftIndexProximal,
  leftIndexIntermediate,
  leftIndexDistal,
  leftMiddleProximal,
  leftMiddleIntermediate,
  leftMiddleDistal,
  leftRingProximal,
  leftRingIntermediate,
  leftRingDistal,
  leftLittleProximal,
  leftLittleIntermediate,
  leftLittleDistal,
  rightThumbMetacarpal,
  rightThumbProximal,
  rightThumbDistal,
  rightIndexProximal,
  rightIndexIntermediate,
  rightIndexDistal,
  rightMiddleProximal,
  rightMiddleIntermediate,
  rightMiddleDistal,
  rightRingProximal,
  rightRingIntermediate,
  rightRingDistal,
  rightLittleProximal,
  rightLittleIntermediate,
  rightLittleDistal;

  static VrmHumanBone? tryParse(String value) {
    for (final bone in values) {
      if (bone.name == value) {
        return bone;
      }
    }
    return null;
  }
}

/// A three-component vector in VRM local bone space.
final class VrmVector3 {
  const VrmVector3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  List<double> toJson() => <double>[x, y, z];

  factory VrmVector3.fromJson(Object? value) {
    final values = _readNumbers(value, 3, 'position');
    return VrmVector3(values[0], values[1], values[2]);
  }
}

/// Quaternion rotation in `[x, y, z, w]` order.
final class VrmQuaternion {
  const VrmQuaternion(this.x, this.y, this.z, this.w);

  const VrmQuaternion.identity() : this(0, 0, 0, 1);

  /// Creates a quaternion from intrinsic XYZ Euler angles in radians.
  factory VrmQuaternion.fromEulerRadians(double x, double y, double z) {
    if (![x, y, z].every((value) => value.isFinite)) {
      throw const FormatException('Euler angles must be finite numbers.');
    }
    final halfX = x / 2;
    final halfY = y / 2;
    final halfZ = z / 2;
    final sinX = math.sin(halfX);
    final cosX = math.cos(halfX);
    final sinY = math.sin(halfY);
    final cosY = math.cos(halfY);
    final sinZ = math.sin(halfZ);
    final cosZ = math.cos(halfZ);
    return VrmQuaternion(
      sinX * cosY * cosZ + cosX * sinY * sinZ,
      cosX * sinY * cosZ - sinX * cosY * sinZ,
      cosX * cosY * sinZ + sinX * sinY * cosZ,
      cosX * cosY * cosZ - sinX * sinY * sinZ,
    );
  }

  /// Creates a quaternion from intrinsic XYZ Euler angles in degrees.
  factory VrmQuaternion.fromEulerDegrees(double x, double y, double z) {
    const radiansPerDegree = math.pi / 180;
    return VrmQuaternion.fromEulerRadians(
      x * radiansPerDegree,
      y * radiansPerDegree,
      z * radiansPerDegree,
    );
  }

  final double x;
  final double y;
  final double z;
  final double w;

  List<double> toJson() => <double>[x, y, z, w];

  factory VrmQuaternion.fromJson(Object? value) {
    final values = _readNumbers(value, 4, 'rotation');
    return VrmQuaternion(values[0], values[1], values[2], values[3]);
  }
}

/// Relative transform of one normalized humanoid bone.
final class VrmPoseTransform {
  const VrmPoseTransform({this.position, this.rotation});

  final VrmVector3? position;
  final VrmQuaternion? rotation;

  Map<String, Object> toJson() => <String, Object>{
    if (position case final value?) 'position': value.toJson(),
    if (rotation case final value?) 'rotation': value.toJson(),
  };

  factory VrmPoseTransform.fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('A VRM bone transform must be an object.');
    }
    return VrmPoseTransform(
      position: value['position'] == null
          ? null
          : VrmVector3.fromJson(value['position']),
      rotation: value['rotation'] == null
          ? null
          : VrmQuaternion.fromJson(value['rotation']),
    );
  }
}

/// Immutable normalized pose accepted by `VRMHumanoid.setNormalizedPose()`.
final class VrmPose {
  VrmPose([Map<VrmHumanBone, VrmPoseTransform> bones = const {}])
    : bones = Map<VrmHumanBone, VrmPoseTransform>.unmodifiable(bones);

  final Map<VrmHumanBone, VrmPoseTransform> bones;

  bool get isEmpty => bones.isEmpty;

  VrmPoseTransform? operator [](VrmHumanBone bone) => bones[bone];

  Map<String, Object> toJson() => <String, Object>{
    for (final entry in bones.entries) entry.key.name: entry.value.toJson(),
  };

  factory VrmPose.fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('A VRM pose must be an object.');
    }
    final bones = <VrmHumanBone, VrmPoseTransform>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const FormatException('VRM pose bone names must be strings.');
      }
      final bone = VrmHumanBone.tryParse(key);
      if (bone == null) {
        throw FormatException('Unknown VRM humanoid bone: $key.');
      }
      bones[bone] = VrmPoseTransform.fromJson(entry.value);
    }
    return VrmPose(bones);
  }
}

List<double> _readNumbers(Object? value, int length, String fieldName) {
  if (value is! List<Object?> || value.length != length) {
    throw FormatException('$fieldName must contain exactly $length numbers.');
  }
  return <double>[
    for (final component in value)
      switch (component) {
        final num number when number.isFinite => number.toDouble(),
        _ => throw FormatException('$fieldName contains a non-finite number.'),
      },
  ];
}
