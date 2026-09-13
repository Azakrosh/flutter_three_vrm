/// Controls how hips translation from a humanoid animation is applied.
enum VrmRootMotion {
  /// Keeps horizontal hips translation at its first-frame value while
  /// preserving vertical motion such as jumps and breathing.
  inPlace,

  /// Preserves the complete hips translation from the source clip.
  full,
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
    return VrmAnimationOptions(
      loop: json['loop'] as bool? ?? true,
      speed: (json['speed'] as num?)?.toDouble() ?? 1,
      fadeDuration: (json['fadeDuration'] as num?)?.toDouble() ?? 0.5,
      rootMotion: VrmRootMotion.values.firstWhere(
        (value) => value.name == json['rootMotion'],
        orElse: () => VrmRootMotion.inPlace,
      ),
      clipName: json['clipName'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'loop': loop,
    'speed': speed,
    'fadeDuration': fadeDuration,
    'rootMotion': rootMotion.name,
    if (clipName != null) 'clipName': clipName,
  };

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
