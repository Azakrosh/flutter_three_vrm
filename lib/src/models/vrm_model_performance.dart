import 'dart:math' as math;

import 'vrm_graphics.dart';
import 'vrm_model_report.dart';

/// Coarse workload classification for an avatar on a mobile GPU.
enum VrmModelComplexity { standard, elevated, high }

/// A model characteristic that crossed a configured advisory threshold.
enum VrmModelMetric {
  sourceBytes,
  triangles,
  textureCount,
  texturePixels,
  textureDimension,
  morphTargets,
  springBoneJoints,
}

/// Thresholds used to classify a [VrmModelReport].
final class VrmModelComplexityThresholds {
  const VrmModelComplexityThresholds({
    required this.sourceBytes,
    required this.triangles,
    required this.textureCount,
    required this.texturePixels,
    required this.textureDimension,
    required this.morphTargets,
    required this.springBoneJoints,
  }) : assert(sourceBytes > 0),
       assert(triangles > 0),
       assert(textureCount > 0),
       assert(texturePixels > 0),
       assert(textureDimension > 0),
       assert(morphTargets > 0),
       assert(springBoneJoints > 0);

  final int sourceBytes;
  final int triangles;
  final int textureCount;
  final int texturePixels;
  final int textureDimension;
  final int morphTargets;
  final int springBoneJoints;

  @override
  bool operator ==(Object other) =>
      other is VrmModelComplexityThresholds &&
      other.sourceBytes == sourceBytes &&
      other.triangles == triangles &&
      other.textureCount == textureCount &&
      other.texturePixels == texturePixels &&
      other.textureDimension == textureDimension &&
      other.morphTargets == morphTargets &&
      other.springBoneJoints == springBoneJoints;

  @override
  int get hashCode => Object.hash(
    sourceBytes,
    triangles,
    textureCount,
    texturePixels,
    textureDimension,
    morphTargets,
    springBoneJoints,
  );
}

/// One advisory finding produced by [VrmModelPerformancePolicy].
final class VrmModelPerformanceWarning {
  const VrmModelPerformanceWarning({
    required this.metric,
    required this.level,
    required this.actual,
    required this.threshold,
  });

  final VrmModelMetric metric;
  final VrmModelComplexity level;
  final int actual;
  final int threshold;
}

/// Result of evaluating a model without rejecting or modifying the asset.
final class VrmModelAssessment {
  const VrmModelAssessment({
    required this.report,
    required this.complexity,
    required this.warnings,
    required this.recommendedMaxPixelRatio,
  });

  final VrmModelReport report;
  final VrmModelComplexity complexity;
  final List<VrmModelPerformanceWarning> warnings;

  /// Advisory render-resolution cap. This does not affect model fidelity.
  final double? recommendedMaxPixelRatio;
}

/// Advisory mobile workload policy used by [VrmView].
///
/// It never rejects a model and never changes meshes, textures, animations, or
/// spring-bone physics. When [autoTunePixelRatio] is enabled, only the upper
/// bound of adaptive render resolution may be lowered.
final class VrmModelPerformancePolicy {
  const VrmModelPerformancePolicy({
    this.autoTunePixelRatio = true,
    this.elevated = const VrmModelComplexityThresholds(
      sourceBytes: 128 * 1024 * 1024,
      triangles: 250000,
      textureCount: 24,
      texturePixels: 96 * 1024 * 1024,
      textureDimension: 4096,
      morphTargets: 96,
      springBoneJoints: 96,
    ),
    this.high = const VrmModelComplexityThresholds(
      sourceBytes: 512 * 1024 * 1024,
      triangles: 800000,
      textureCount: 64,
      texturePixels: 256 * 1024 * 1024,
      textureDimension: 8192,
      morphTargets: 256,
      springBoneJoints: 256,
    ),
    this.elevatedMaxPixelRatio = 1.25,
    this.highMaxPixelRatio = 1,
  }) : assert(elevatedMaxPixelRatio >= 0.5),
       assert(highMaxPixelRatio >= 0.5),
       assert(highMaxPixelRatio <= elevatedMaxPixelRatio);

  final bool autoTunePixelRatio;
  final VrmModelComplexityThresholds elevated;
  final VrmModelComplexityThresholds high;
  final double elevatedMaxPixelRatio;
  final double highMaxPixelRatio;

  @override
  bool operator ==(Object other) =>
      other is VrmModelPerformancePolicy &&
      other.autoTunePixelRatio == autoTunePixelRatio &&
      other.elevated == elevated &&
      other.high == high &&
      other.elevatedMaxPixelRatio == elevatedMaxPixelRatio &&
      other.highMaxPixelRatio == highMaxPixelRatio;

  @override
  int get hashCode => Object.hash(
    autoTunePixelRatio,
    elevated,
    high,
    elevatedMaxPixelRatio,
    highMaxPixelRatio,
  );

  VrmModelAssessment assess(VrmModelReport report) {
    if (!_thresholdsAreOrdered) {
      throw StateError(
        'High complexity thresholds must not be lower than elevated '
        'thresholds.',
      );
    }
    final warnings = <VrmModelPerformanceWarning>[];
    final textureDimension = math.max(
      report.maxTextureWidth,
      report.maxTextureHeight,
    );

    void evaluateMetric(
      VrmModelMetric metric,
      int actual,
      int elevatedThreshold,
      int highThreshold,
    ) {
      if (actual > highThreshold) {
        warnings.add(
          VrmModelPerformanceWarning(
            metric: metric,
            level: VrmModelComplexity.high,
            actual: actual,
            threshold: highThreshold,
          ),
        );
      } else if (actual > elevatedThreshold) {
        warnings.add(
          VrmModelPerformanceWarning(
            metric: metric,
            level: VrmModelComplexity.elevated,
            actual: actual,
            threshold: elevatedThreshold,
          ),
        );
      }
    }

    evaluateMetric(
      VrmModelMetric.sourceBytes,
      report.sourceBytes,
      elevated.sourceBytes,
      high.sourceBytes,
    );
    evaluateMetric(
      VrmModelMetric.triangles,
      report.triangles,
      elevated.triangles,
      high.triangles,
    );
    evaluateMetric(
      VrmModelMetric.textureCount,
      report.textures,
      elevated.textureCount,
      high.textureCount,
    );
    evaluateMetric(
      VrmModelMetric.texturePixels,
      report.texturePixels,
      elevated.texturePixels,
      high.texturePixels,
    );
    evaluateMetric(
      VrmModelMetric.textureDimension,
      textureDimension,
      elevated.textureDimension,
      high.textureDimension,
    );
    evaluateMetric(
      VrmModelMetric.morphTargets,
      report.morphTargets,
      elevated.morphTargets,
      high.morphTargets,
    );
    evaluateMetric(
      VrmModelMetric.springBoneJoints,
      report.springBoneJoints,
      elevated.springBoneJoints,
      high.springBoneJoints,
    );

    final complexity =
        warnings.any((warning) => warning.level == VrmModelComplexity.high)
        ? VrmModelComplexity.high
        : warnings.isNotEmpty
        ? VrmModelComplexity.elevated
        : VrmModelComplexity.standard;
    final recommendedMaxPixelRatio = switch (complexity) {
      VrmModelComplexity.standard => null,
      VrmModelComplexity.elevated => elevatedMaxPixelRatio,
      VrmModelComplexity.high => highMaxPixelRatio,
    };

    return VrmModelAssessment(
      report: report,
      complexity: complexity,
      warnings: List.unmodifiable(warnings),
      recommendedMaxPixelRatio: recommendedMaxPixelRatio,
    );
  }

  bool get _thresholdsAreOrdered =>
      high.sourceBytes >= elevated.sourceBytes &&
      high.triangles >= elevated.triangles &&
      high.textureCount >= elevated.textureCount &&
      high.texturePixels >= elevated.texturePixels &&
      high.textureDimension >= elevated.textureDimension &&
      high.morphTargets >= elevated.morphTargets &&
      high.springBoneJoints >= elevated.springBoneJoints;

  /// Derives adaptive-quality bounds for [assessment].
  VrmAdaptiveQualitySettings applyTo(
    VrmAdaptiveQualitySettings settings,
    VrmModelAssessment assessment,
  ) {
    final cap = assessment.recommendedMaxPixelRatio;
    if (!autoTunePixelRatio || !settings.enabled || cap == null) {
      return settings;
    }
    return settings.copyWith(
      maxPixelRatio: math.max(
        settings.minPixelRatio,
        math.min(settings.maxPixelRatio, cap),
      ),
    );
  }
}
