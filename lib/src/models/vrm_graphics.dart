/// Curated renderer profiles for common mobile workloads.
enum VrmGraphicsPreset { performance, balanced, quality }

/// Runtime state of the WebGL rendering context.
enum VrmWebGlContextState { lost, restored }

/// Policy used to adapt render resolution to sustained frame rate.
final class VrmAdaptiveQualitySettings {
  const VrmAdaptiveQualitySettings({
    this.enabled = true,
    this.targetFps = 55,
    this.minPixelRatio = 0.75,
    this.maxPixelRatio = 1.5,
  });

  final bool enabled;
  final int targetFps;
  final double minPixelRatio;
  final double maxPixelRatio;

  /// Verifies renderer bounds in both debug and release builds.
  void validate() {
    if (targetFps < 15 || targetFps > 120) {
      throw ArgumentError.value(
        targetFps,
        'targetFps',
        'Must be between 15 and 120.',
      );
    }
    if (!minPixelRatio.isFinite || minPixelRatio < 0.5 || minPixelRatio > 3) {
      throw ArgumentError.value(
        minPixelRatio,
        'minPixelRatio',
        'Must be finite and between 0.5 and 3.',
      );
    }
    if (!maxPixelRatio.isFinite || maxPixelRatio < 0.5 || maxPixelRatio > 3) {
      throw ArgumentError.value(
        maxPixelRatio,
        'maxPixelRatio',
        'Must be finite and between 0.5 and 3.',
      );
    }
    if (minPixelRatio > maxPixelRatio) {
      throw ArgumentError(
        'minPixelRatio must not be greater than maxPixelRatio.',
      );
    }
  }

  Map<String, Object> toJson() {
    validate();
    return <String, Object>{
      'enabled': enabled,
      'targetFps': targetFps,
      'minPixelRatio': minPixelRatio,
      'maxPixelRatio': maxPixelRatio,
    };
  }

  VrmAdaptiveQualitySettings copyWith({
    bool? enabled,
    int? targetFps,
    double? minPixelRatio,
    double? maxPixelRatio,
  }) => VrmAdaptiveQualitySettings(
    enabled: enabled ?? this.enabled,
    targetFps: targetFps ?? this.targetFps,
    minPixelRatio: minPixelRatio ?? this.minPixelRatio,
    maxPixelRatio: maxPixelRatio ?? this.maxPixelRatio,
  );

  @override
  bool operator ==(Object other) =>
      other is VrmAdaptiveQualitySettings &&
      other.enabled == enabled &&
      other.targetFps == targetFps &&
      other.minPixelRatio == minPixelRatio &&
      other.maxPixelRatio == maxPixelRatio;

  @override
  int get hashCode =>
      Object.hash(enabled, targetFps, minPixelRatio, maxPixelRatio);
}

/// Latest renderer workload measurement reported by the web runtime.
enum VrmPerformanceReason {
  initialized,
  configurationChanged,
  sample,
  performanceDown,
  performanceUp,
}

/// Best-effort source classification for long steady-state frame intervals.
enum VrmLongFrameSource {
  none,
  runtimeUpdate,
  renderSubmission,
  externalScheduling,
}

/// Explanation of the latest adaptive-quality policy decision.
enum VrmAdaptiveQualityDecision {
  disabled,
  stable,
  collectingSlow,
  collectingFast,
  cooldown,
  atMinimum,
  atMaximum,
  decrease,
  increase,
}

final class VrmPerformanceSnapshot {
  const VrmPerformanceSnapshot({
    required this.fps,
    required this.frameTimeMs,
    required this.frameTimeP50Ms,
    required this.frameTimeP95Ms,
    required this.frameSampleCount,
    required this.longFrameCount,
    required this.longestFrameMs,
    required this.longFrameThresholdMs,
    required this.updateTimeP95Ms,
    required this.renderTimeP95Ms,
    required this.longFrameSource,
    required this.pixelRatio,
    required this.fpsCap,
    required this.physicsEnabled,
    required this.adaptiveQualityEnabled,
    required this.adaptiveTargetFps,
    required this.adaptiveSlowWindowCount,
    required this.adaptiveFastWindowCount,
    required this.adaptiveCooldownRemainingMs,
    required this.adaptiveDecision,
    required this.drawCalls,
    required this.triangles,
    required this.geometries,
    required this.textures,
    required this.reason,
  });

  final double fps;
  final double frameTimeMs;
  final double frameTimeP50Ms;
  final double frameTimeP95Ms;
  final int frameSampleCount;
  final int longFrameCount;
  final double longestFrameMs;
  final double longFrameThresholdMs;
  final double updateTimeP95Ms;
  final double renderTimeP95Ms;
  final VrmLongFrameSource longFrameSource;
  final double pixelRatio;
  final int fpsCap;
  final bool physicsEnabled;
  final bool adaptiveQualityEnabled;
  final int adaptiveTargetFps;
  final int adaptiveSlowWindowCount;
  final int adaptiveFastWindowCount;
  final double adaptiveCooldownRemainingMs;
  final VrmAdaptiveQualityDecision adaptiveDecision;
  final int drawCalls;
  final int triangles;
  final int geometries;
  final int textures;

  final VrmPerformanceReason reason;

  factory VrmPerformanceSnapshot.fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('Performance snapshot must be an object.');
    }
    final snapshot = VrmPerformanceSnapshot(
      fps: _finiteDouble(value['fps'], 'fps'),
      frameTimeMs: _finiteDouble(value['frameTimeMs'], 'frameTimeMs'),
      frameTimeP50Ms: _finiteDouble(value['frameTimeP50Ms'], 'frameTimeP50Ms'),
      frameTimeP95Ms: _finiteDouble(value['frameTimeP95Ms'], 'frameTimeP95Ms'),
      frameSampleCount: _integer(value['frameSampleCount'], 'frameSampleCount'),
      longFrameCount: _integer(value['longFrameCount'], 'longFrameCount'),
      longestFrameMs: _finiteDouble(value['longestFrameMs'], 'longestFrameMs'),
      longFrameThresholdMs: _finiteDouble(
        value['longFrameThresholdMs'],
        'longFrameThresholdMs',
      ),
      updateTimeP95Ms: _finiteDouble(
        value['updateTimeP95Ms'],
        'updateTimeP95Ms',
      ),
      renderTimeP95Ms: _finiteDouble(
        value['renderTimeP95Ms'],
        'renderTimeP95Ms',
      ),
      longFrameSource: _enumByName(
        value['longFrameSource'],
        VrmLongFrameSource.values,
        'longFrameSource',
      ),
      pixelRatio: _finiteDouble(value['pixelRatio'], 'pixelRatio'),
      fpsCap: _integer(value['fpsCap'], 'fpsCap'),
      physicsEnabled: _boolean(value['physicsEnabled'], 'physicsEnabled'),
      adaptiveQualityEnabled: _boolean(
        value['adaptiveQualityEnabled'],
        'adaptiveQualityEnabled',
      ),
      adaptiveTargetFps: _integer(
        value['adaptiveTargetFps'],
        'adaptiveTargetFps',
      ),
      adaptiveSlowWindowCount: _integer(
        value['adaptiveSlowWindowCount'],
        'adaptiveSlowWindowCount',
      ),
      adaptiveFastWindowCount: _integer(
        value['adaptiveFastWindowCount'],
        'adaptiveFastWindowCount',
      ),
      adaptiveCooldownRemainingMs: _finiteDouble(
        value['adaptiveCooldownRemainingMs'],
        'adaptiveCooldownRemainingMs',
      ),
      adaptiveDecision: _enumByName(
        value['adaptiveDecision'],
        VrmAdaptiveQualityDecision.values,
        'adaptiveDecision',
      ),
      drawCalls: _integer(value['drawCalls'], 'drawCalls'),
      triangles: _integer(value['triangles'], 'triangles'),
      geometries: _integer(value['geometries'], 'geometries'),
      textures: _integer(value['textures'], 'textures'),
      reason: _performanceReason(value['reason']),
    );
    if (snapshot.fps < 0 ||
        snapshot.frameTimeMs < 0 ||
        snapshot.frameTimeP50Ms < 0 ||
        snapshot.frameTimeP95Ms < 0 ||
        snapshot.frameSampleCount < 0 ||
        snapshot.longFrameCount < 0 ||
        snapshot.longestFrameMs < 0 ||
        snapshot.longFrameThresholdMs <= 0 ||
        snapshot.updateTimeP95Ms < 0 ||
        snapshot.renderTimeP95Ms < 0 ||
        snapshot.adaptiveTargetFps <= 0 ||
        snapshot.adaptiveSlowWindowCount < 0 ||
        snapshot.adaptiveFastWindowCount < 0 ||
        snapshot.adaptiveCooldownRemainingMs < 0 ||
        snapshot.fpsCap < 0) {
      throw const FormatException(
        'Performance timing values must be non-negative.',
      );
    }
    if (snapshot.frameTimeP50Ms > snapshot.frameTimeP95Ms) {
      throw const FormatException(
        'frameTimeP50Ms must not exceed frameTimeP95Ms.',
      );
    }
    if (snapshot.longFrameCount > snapshot.frameSampleCount) {
      throw const FormatException(
        'longFrameCount must not exceed frameSampleCount.',
      );
    }
    if (snapshot.longFrameCount == 0 &&
        (snapshot.longestFrameMs != 0 ||
            snapshot.longFrameSource != VrmLongFrameSource.none)) {
      throw const FormatException(
        'Empty long-frame samples must use zero duration and none source.',
      );
    }
    if (snapshot.longFrameCount > 0 &&
        (snapshot.longestFrameMs <= snapshot.longFrameThresholdMs ||
            snapshot.longFrameSource == VrmLongFrameSource.none)) {
      throw const FormatException(
        'Long-frame diagnostics must include duration and source.',
      );
    }
    if (snapshot.pixelRatio <= 0) {
      throw const FormatException('Performance pixelRatio must be positive.');
    }
    if (snapshot.drawCalls < 0 ||
        snapshot.triangles < 0 ||
        snapshot.geometries < 0 ||
        snapshot.textures < 0) {
      throw const FormatException(
        'Performance renderer counters must be non-negative.',
      );
    }
    return snapshot;
  }
}

VrmPerformanceReason _performanceReason(Object? value) {
  if (value is String) {
    for (final reason in VrmPerformanceReason.values) {
      if (reason.name == value) return reason;
    }
  }
  throw const FormatException('Unknown performance reason.');
}

T _enumByName<T extends Enum>(Object? value, List<T> values, String name) {
  if (value is String) {
    for (final candidate in values) {
      if (candidate.name == value) return candidate;
    }
  }
  throw FormatException('Unknown $name.');
}

double _finiteDouble(Object? value, String name) {
  if (value case final num number when number.isFinite) {
    return number.toDouble();
  }
  throw FormatException('$name must be a finite number.');
}

int _integer(Object? value, String name) {
  if (value case final num number
      when number.isFinite && number == number.truncateToDouble()) {
    return number.toInt();
  }
  throw FormatException('$name must be a finite integer.');
}

bool _boolean(Object? value, String name) {
  if (value is bool) return value;
  throw FormatException('$name must be a boolean.');
}
