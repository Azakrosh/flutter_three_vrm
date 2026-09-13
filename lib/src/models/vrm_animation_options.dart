/// Playback options for VRMA animation clips.
class VrmAnimationOptions {
  /// Whether the animation clip should loop continuously.
  /// If false, the animation plays once and stops at the last frame.
  final bool loop;

  /// Playback speed multiplier (1.0 = normal speed, 0.5 = half speed, 2.0 = double speed).
  final double speed;

  /// Crossfade transition duration in seconds when switching between animations.
  final double fadeDuration;

  const VrmAnimationOptions({
    this.loop = true,
    this.speed = 1.0,
    this.fadeDuration = 0.5,
  });

  /// Creates a [VrmAnimationOptions] from a JSON map.
  factory VrmAnimationOptions.fromJson(Map<String, dynamic> json) {
    return VrmAnimationOptions(
      loop: json['loop'] as bool? ?? true,
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      fadeDuration: (json['fadeDuration'] as num?)?.toDouble() ?? 0.5,
    );
  }

  /// Serializes the options to a JSON map.
  Map<String, dynamic> toJson() => {
        'loop': loop,
        'speed': speed,
        'fadeDuration': fadeDuration,
      };

  /// Creates a copy of this object with the given fields replaced with the new values.
  VrmAnimationOptions copyWith({
    bool? loop,
    double? speed,
    double? fadeDuration,
  }) {
    return VrmAnimationOptions(
      loop: loop ?? this.loop,
      speed: speed ?? this.speed,
      fadeDuration: fadeDuration ?? this.fadeDuration,
    );
  }
}
