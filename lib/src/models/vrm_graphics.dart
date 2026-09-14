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
  }) : assert(targetFps >= 15 && targetFps <= 120),
       assert(minPixelRatio >= 0.5 && minPixelRatio <= 3),
       assert(maxPixelRatio >= 0.5 && maxPixelRatio <= 3),
       assert(minPixelRatio <= maxPixelRatio);

  final bool enabled;
  final int targetFps;
  final double minPixelRatio;
  final double maxPixelRatio;

  Map<String, Object> toJson() => <String, Object>{
    'enabled': enabled,
    'targetFps': targetFps,
    'minPixelRatio': minPixelRatio,
    'maxPixelRatio': maxPixelRatio,
  };

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
final class VrmPerformanceSnapshot {
  const VrmPerformanceSnapshot({
    required this.fps,
    required this.frameTimeMs,
    required this.pixelRatio,
    required this.fpsCap,
    required this.physicsEnabled,
    required this.adaptiveQualityEnabled,
    required this.drawCalls,
    required this.triangles,
    required this.geometries,
    required this.textures,
    required this.reason,
  });

  final double fps;
  final double frameTimeMs;
  final double pixelRatio;
  final int fpsCap;
  final bool physicsEnabled;
  final bool adaptiveQualityEnabled;
  final int drawCalls;
  final int triangles;
  final int geometries;
  final int textures;

  /// `sample`, `performanceDown`, `performanceUp`, or another runtime reason.
  final String reason;

  factory VrmPerformanceSnapshot.fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('Performance snapshot must be an object.');
    }
    return VrmPerformanceSnapshot(
      fps: _finiteDouble(value['fps'], 'fps'),
      frameTimeMs: _finiteDouble(value['frameTimeMs'], 'frameTimeMs'),
      pixelRatio: _finiteDouble(value['pixelRatio'], 'pixelRatio'),
      fpsCap: _integer(value['fpsCap'], 'fpsCap'),
      physicsEnabled: _boolean(value['physicsEnabled'], 'physicsEnabled'),
      adaptiveQualityEnabled: _boolean(
        value['adaptiveQualityEnabled'],
        'adaptiveQualityEnabled',
      ),
      drawCalls: _integer(value['drawCalls'], 'drawCalls'),
      triangles: _integer(value['triangles'], 'triangles'),
      geometries: _integer(value['geometries'], 'geometries'),
      textures: _integer(value['textures'], 'textures'),
      reason: value['reason'] is String ? value['reason']! as String : 'sample',
    );
  }
}

double _finiteDouble(Object? value, String name) {
  if (value case final num number when number.isFinite) {
    return number.toDouble();
  }
  throw FormatException('$name must be a finite number.');
}

int _integer(Object? value, String name) {
  if (value case final num number when number.isFinite) {
    return number.toInt();
  }
  throw FormatException('$name must be a finite number.');
}

bool _boolean(Object? value, String name) {
  if (value is bool) return value;
  throw FormatException('$name must be a boolean.');
}
