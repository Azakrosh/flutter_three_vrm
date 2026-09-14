import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';

void main() {
  const policy = VrmModelPerformancePolicy(
    elevated: VrmModelComplexityThresholds(
      sourceBytes: 100,
      triangles: 100,
      textureCount: 10,
      texturePixels: 100,
      textureDimension: 100,
      morphTargets: 10,
      springBoneJoints: 10,
    ),
    high: VrmModelComplexityThresholds(
      sourceBytes: 200,
      triangles: 200,
      textureCount: 20,
      texturePixels: 200,
      textureDimension: 200,
      morphTargets: 20,
      springBoneJoints: 20,
    ),
  );

  group('VrmModelPerformancePolicy', () {
    test('keeps values at thresholds in the standard class', () {
      final assessment = policy.assess(_report(triangles: 100));

      expect(assessment.complexity, VrmModelComplexity.standard);
      expect(assessment.warnings, isEmpty);
      expect(assessment.recommendedMaxPixelRatio, isNull);
    });

    test('reports every crossed metric and uses the highest level', () {
      final assessment = policy.assess(
        _report(triangles: 150, textureDimension: 250),
      );

      expect(assessment.complexity, VrmModelComplexity.high);
      expect(assessment.warnings, hasLength(2));
      expect(
        assessment.warnings.map((warning) => warning.metric),
        containsAll(<VrmModelMetric>[
          VrmModelMetric.triangles,
          VrmModelMetric.textureDimension,
        ]),
      );
      expect(assessment.recommendedMaxPixelRatio, 1);
    });

    test('caps only adaptive maximum and preserves an explicit minimum', () {
      final assessment = policy.assess(_report(triangles: 150));
      const base = VrmAdaptiveQualitySettings(
        minPixelRatio: 1.1,
        maxPixelRatio: 2,
      );

      final adjusted = policy.applyTo(base, assessment);

      expect(adjusted.minPixelRatio, 1.1);
      expect(adjusted.maxPixelRatio, 1.25);
      expect(adjusted.targetFps, base.targetFps);
    });

    test('does not alter manually managed render resolution', () {
      final assessment = policy.assess(_report(triangles: 250));
      const manual = VrmAdaptiveQualitySettings(
        enabled: false,
        minPixelRatio: 1.5,
        maxPixelRatio: 2,
      );

      expect(policy.applyTo(manual, assessment), same(manual));
    });

    test('compares equivalent policies by value', () {
      final first = VrmModelPerformancePolicy(
        elevated: policy.elevated,
        high: policy.high,
      );
      final second = VrmModelPerformancePolicy(
        elevated: policy.elevated,
        high: policy.high,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('rejects thresholds with an inverted severity order', () {
      const invalid = VrmModelPerformancePolicy(
        elevated: VrmModelComplexityThresholds(
          sourceBytes: 200,
          triangles: 100,
          textureCount: 10,
          texturePixels: 100,
          textureDimension: 100,
          morphTargets: 10,
          springBoneJoints: 10,
        ),
        high: VrmModelComplexityThresholds(
          sourceBytes: 100,
          triangles: 200,
          textureCount: 20,
          texturePixels: 200,
          textureDimension: 200,
          morphTargets: 20,
          springBoneJoints: 20,
        ),
      );

      expect(() => invalid.assess(_report()), throwsStateError);
    });
  });
}

VrmModelReport _report({int triangles = 0, int textureDimension = 0}) {
  return VrmModelReport(
    name: 'Avatar',
    vrmVersion: '1',
    sourceBytes: 0,
    height: 1.7,
    meshes: 1,
    skinnedMeshes: 1,
    geometries: 1,
    materials: 1,
    textures: 1,
    texturePixels: 0,
    estimatedTextureMemoryBytes: 0,
    maxTextureWidth: textureDimension,
    maxTextureHeight: textureDimension,
    vertices: 0,
    triangles: triangles,
    morphTargets: 0,
    humanoidBones: 55,
    springBoneJoints: 0,
  );
}
