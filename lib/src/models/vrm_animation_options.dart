/// Controls how hips translation from a humanoid animation is applied.
enum VrmRootMotion {
  /// Keeps horizontal hips translation at its first-frame value while
  /// preserving vertical motion such as jumps and breathing.
  inPlace,

  /// Preserves the complete hips translation from the source clip.
  full,
}

/// Identity of one successfully started animation playback.
///
/// The identifier is also included in animation lifecycle events so higher
/// level coordinators can ignore unrelated or replaced animations.
final class VrmAnimationPlayback {
  factory VrmAnimationPlayback({required String id}) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be empty.');
    }
    return VrmAnimationPlayback._(id);
  }

  const VrmAnimationPlayback._(this.id);

  final String id;
}

/// Playback and retargeting options for VRMA and glTF/GLB animation clips.
final class VrmAnimationOptions {
  const VrmAnimationOptions({
    this.loop = true,
    this.speed = 1,
    this.fadeDuration = 0.5,
    this.rootMotion = VrmRootMotion.inPlace,
    this.clipName,
  });

  /// Whether the clip loops continuously.
  final bool loop;

  /// Playback speed multiplier.
  final double speed;

  /// Crossfade duration in seconds when switching clips.
  final double fadeDuration;

  /// Root-motion behavior used when retargeting glTF/GLB humanoid clips.
  final VrmRootMotion rootMotion;

  /// Optional animation name when a glTF/GLB file contains multiple clips.
  final String? clipName;

  factory VrmAnimationOptions.fromJson(Map<String, dynamic> json) {
    final loop = json['loop'];
    final speed = json['speed'];
    final fadeDuration = json['fadeDuration'];
    final rootMotion = json['rootMotion'];
    final clipName = json['clipName'];
    if (loop != null && loop is! bool) {
      throw const FormatException('loop must be a boolean.');
    }
    if (speed != null && (speed is! num || !speed.isFinite || speed <= 0)) {
      throw const FormatException('speed must be positive and finite.');
    }
    if (fadeDuration != null &&
        (fadeDuration is! num ||
            !fadeDuration.isFinite ||
            fadeDuration < 0)) {
      throw const FormatException(
        'fadeDuration must be non-negative and finite.',
      );
    }
    if (rootMotion != null &&
        rootMotion != VrmRootMotion.inPlace.name &&
        rootMotion != VrmRootMotion.full.name) {
      throw const FormatException('rootMotion must be inPlace or full.');
    }
    if (clipName != null &&
        (clipName is! String || clipName.trim().isEmpty)) {
      throw const FormatException('clipName must be a non-empty string.');
    }
    return VrmAnimationOptions(
      loop: loop as bool? ?? true,
      speed: (speed as num?)?.toDouble() ?? 1,
      fadeDuration: (fadeDuration as num?)?.toDouble() ?? 0.5,
      rootMotion: rootMotion == VrmRootMotion.full.name
          ? VrmRootMotion.full
          : VrmRootMotion.inPlace,
      clipName: clipName as String?,
    );
  }

  void validate() {
    if (!speed.isFinite || speed <= 0) {
      throw ArgumentError.value(speed, 'speed', 'Must be positive and finite.');
    }
    if (!fadeDuration.isFinite || fadeDuration < 0) {
      throw ArgumentError.value(
        fadeDuration,
        'fadeDuration',
        'Must be non-negative and finite.',
      );
    }
    if (clipName case final name? when name.trim().isEmpty) {
      throw ArgumentError.value(
        clipName,
        'clipName',
        'Must not be empty.',
      );
    }
  }

  Map<String, dynamic> toJson() {
    validate();
    return <String, dynamic>{
      'loop': loop,
      'speed': speed,
      'fadeDuration': fadeDuration,
      'rootMotion': rootMotion.name,
      if (clipName != null) 'clipName': clipName,
    };
  }

  VrmAnimationOptions copyWith({
    bool? loop,
    double? speed,
    double? fadeDuration,
    VrmRootMotion? rootMotion,
    String? clipName,
    bool clearClipName = false,
  }) {
    return VrmAnimationOptions(
      loop: loop ?? this.loop,
      speed: speed ?? this.speed,
      fadeDuration: fadeDuration ?? this.fadeDuration,
      rootMotion: rootMotion ?? this.rootMotion,
      clipName: clearClipName ? null : clipName ?? this.clipName,
    );
  }
}
