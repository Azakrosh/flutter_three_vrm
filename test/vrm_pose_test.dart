import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';

void main() {
  group('VrmPose', () {
    test('round-trips normalized humanoid transforms', () {
      final pose = VrmPose({
        VrmHumanBone.hips: const VrmPoseTransform(
          position: VrmVector3(0, 0.25, 0),
        ),
        VrmHumanBone.head: const VrmPoseTransform(
          rotation: VrmQuaternion.identity(),
        ),
      });

      final restored = VrmPose.fromJson(pose.toJson());

      expect(restored.bones.length, 2);
      expect(restored[VrmHumanBone.hips]?.position?.y, 0.25);
      expect(restored[VrmHumanBone.head]?.rotation?.w, 1);
    });

    test('rejects unknown bones', () {
      expect(
        () => VrmPose.fromJson(<String, Object>{
          'tail': <String, Object>{
            'rotation': <double>[0, 0, 0, 1],
          },
        }),
        throwsFormatException,
      );
    });

    test('rejects invalid and non-finite components', () {
      expect(() => VrmVector3.fromJson(<double>[0, 1]), throwsFormatException);
      expect(
        () => VrmQuaternion.fromJson(<double>[0, 0, double.nan, 1]),
        throwsFormatException,
      );
      expect(
        () => const VrmVector3(double.nan, 0, 0).toJson(),
        throwsFormatException,
      );
      expect(
        () => const VrmQuaternion(0, 0, 0, 0).toJson(),
        throwsFormatException,
      );
      expect(
        () => VrmQuaternion.fromJson(<double>[0, 0, 0, 0]),
        throwsFormatException,
      );
    });

    test('creates normalized quaternions from XYZ Euler degrees', () {
      final rotation = VrmQuaternion.fromEulerDegrees(0, 90, 0);

      expect(rotation.x, closeTo(0, 1e-12));
      expect(rotation.y, closeTo(0.7071067812, 1e-10));
      expect(rotation.z, closeTo(0, 1e-12));
      expect(rotation.w, closeTo(0.7071067812, 1e-10));
      expect(
        () => VrmQuaternion.fromEulerRadians(double.nan, 0, 0),
        throwsFormatException,
      );
    });
  });
}
