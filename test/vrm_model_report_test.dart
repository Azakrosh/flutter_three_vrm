import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';

void main() {
  test('VrmModelReport parses runtime diagnostics', () {
    final report = VrmModelReport.fromJson(<String, Object>{
      'name': 'Avatar',
      'vrmVersion': '1',
      'sourceBytes': 1048576,
      'height': 1.68,
      'meshes': 5,
      'skinnedMeshes': 4,
      'geometries': 5,
      'materials': 7,
      'textures': 8,
      'texturePixels': 33554432,
      'estimatedTextureMemoryBytes': 178956971,
      'maxTextureWidth': 4096,
      'maxTextureHeight': 4096,
      'vertices': 85000,
      'triangles': 120000,
      'morphTargets': 32,
      'humanoidBones': 55,
      'springBoneJoints': 24,
    });

    expect(report.name, 'Avatar');
    expect(report.sourceBytes, 1048576);
    expect(report.triangles, 120000);
    expect(report.maxTextureWidth, 4096);
    expect(report.texturePixels, 33554432);
    expect(report.estimatedTextureMemoryBytes, 178956971);
    expect(report.springBoneJoints, 24);
  });

  test('VrmModelReport rejects incomplete diagnostics', () {
    expect(
      () => VrmModelReport.fromJson(const <String, Object>{}),
      throwsFormatException,
    );
    expect(
      () => VrmModelReport.fromJson(<String, Object>{
        'name': '',
        'vrmVersion': '1.0',
      }),
      throwsFormatException,
    );
    expect(
      () => VrmModelReport.fromJson(<String, Object>{
        'name': 'Avatar',
        'vrmVersion': '1.0',
        'sourceBytes': -1,
      }),
      throwsFormatException,
    );
  });
}
