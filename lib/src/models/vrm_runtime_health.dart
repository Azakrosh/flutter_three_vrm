import 'dart:math' as math;

/// Typed runtime and WebGL capability snapshot used by smoke tests and logs.
final class VrmRuntimeHealth {
  const VrmRuntimeHealth({
    required this.runtimeVersion,
    required this.protocolVersion,
    required this.threeRevision,
    required this.threeVrmVersion,
    required this.webGlVersion,
    required this.maxTextureSize,
    required this.maxTextures,
    required this.maxVertexTextures,
    required this.rendererTextureCount,
    required this.estimatedTextureMemoryBytes,
    required this.lastModelLoadDurationMs,
    required this.modelLoaded,
    required this.animationActive,
    required this.animationPaused,
    required this.renderingPaused,
    required this.contextLost,
    required this.contextLossCount,
  });

  final String runtimeVersion;
  final int protocolVersion;
  final String threeRevision;
  final String threeVrmVersion;
  final int webGlVersion;
  final int maxTextureSize;
  final int maxTextures;
  final int maxVertexTextures;
  final int rendererTextureCount;
  final int estimatedTextureMemoryBytes;
  final double lastModelLoadDurationMs;
  final bool modelLoaded;
  final bool animationActive;
  final bool animationPaused;
  final bool renderingPaused;
  final bool contextLost;
  final int contextLossCount;

  factory VrmRuntimeHealth.fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('Runtime health must be an object.');
    }
    String string(String name) {
      final field = value[name];
      if (field is String && field.isNotEmpty) return field;
      throw FormatException('$name must be a non-empty string.');
    }

    int integer(String name) {
      final field = value[name];
      if (field case final num number
          when number.isFinite && number == number.truncateToDouble()) {
        return number.toInt();
      }
      throw FormatException('$name must be a finite integer.');
    }

    bool boolean(String name) {
      final field = value[name];
      if (field is bool) return field;
      throw FormatException('$name must be a boolean.');
    }

    double finiteNumber(String name) {
      final field = value[name];
      if (field is num && field.isFinite) return field.toDouble();
      throw FormatException('$name must be a finite number.');
    }

    final protocolVersion = integer('protocolVersion');
    final webGlVersion = integer('webGlVersion');
    final maxTextureSize = integer('maxTextureSize');
    final maxTextures = integer('maxTextures');
    final maxVertexTextures = integer('maxVertexTextures');
    final rendererTextureCount = integer('rendererTextureCount');
    final estimatedTextureMemoryBytes = integer('estimatedTextureMemoryBytes');
    final lastModelLoadDurationMs = finiteNumber('lastModelLoadDurationMs');
    final contextLossCount = integer('contextLossCount');
    if (protocolVersion < 1) {
      throw const FormatException('protocolVersion must be positive.');
    }
    if (webGlVersion != 1 && webGlVersion != 2) {
      throw const FormatException('webGlVersion must be 1 or 2.');
    }
    if (maxTextureSize < 0 ||
        maxTextures < 0 ||
        maxVertexTextures < 0 ||
        rendererTextureCount < 0 ||
        estimatedTextureMemoryBytes < 0 ||
        lastModelLoadDurationMs < 0 ||
        contextLossCount < 0) {
      throw const FormatException('Runtime metrics must not be negative.');
    }

    return VrmRuntimeHealth(
      runtimeVersion: string('runtimeVersion'),
      protocolVersion: protocolVersion,
      threeRevision: string('threeRevision'),
      threeVrmVersion: string('threeVrmVersion'),
      webGlVersion: webGlVersion,
      maxTextureSize: maxTextureSize,
      maxTextures: maxTextures,
      maxVertexTextures: maxVertexTextures,
      rendererTextureCount: rendererTextureCount,
      estimatedTextureMemoryBytes: estimatedTextureMemoryBytes,
      lastModelLoadDurationMs: lastModelLoadDurationMs,
      modelLoaded: boolean('modelLoaded'),
      animationActive: boolean('animationActive'),
      animationPaused: boolean('animationPaused'),
      renderingPaused: boolean('renderingPaused'),
      contextLost: boolean('contextLost'),
      contextLossCount: contextLossCount,
    );
  }
}

/// Bounded retry policy for main-frame runtime loading failures.
final class VrmRuntimeRecoveryPolicy {
  const VrmRuntimeRecoveryPolicy({
    this.enabled = true,
    this.maxAttempts = 2,
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 4),
  });

  final bool enabled;
  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;

  /// Verifies retry bounds in both debug and release builds.
  void validate() {
    if (maxAttempts < 0) {
      throw ArgumentError.value(
        maxAttempts,
        'maxAttempts',
        'Must not be negative.',
      );
    }
    if (baseDelay.isNegative) {
      throw ArgumentError.value(
        baseDelay,
        'baseDelay',
        'Must not be negative.',
      );
    }
    if (maxDelay.isNegative) {
      throw ArgumentError.value(maxDelay, 'maxDelay', 'Must not be negative.');
    }
  }

  Duration delayForAttempt(int attempt) {
    if (attempt < 1) {
      throw RangeError.range(attempt, 1, null, 'attempt');
    }
    validate();
    final exponent = math.min(attempt - 1, 20);
    final milliseconds = math.min(
      maxDelay.inMilliseconds,
      baseDelay.inMilliseconds * (1 << exponent),
    );
    return Duration(milliseconds: milliseconds);
  }

  @override
  bool operator ==(Object other) =>
      other is VrmRuntimeRecoveryPolicy &&
      other.enabled == enabled &&
      other.maxAttempts == maxAttempts &&
      other.baseDelay == baseDelay &&
      other.maxDelay == maxDelay;

  @override
  int get hashCode => Object.hash(enabled, maxAttempts, baseDelay, maxDelay);
}
