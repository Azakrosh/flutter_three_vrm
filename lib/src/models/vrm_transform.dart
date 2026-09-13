import 'dart:convert';

/// Represents the physical position and zoom level of the avatar on screen.
/// 
/// This state can be retrieved and restored to maintain the user's custom
/// framing of the 3D model across sessions or screen changes.
class VrmTransform {
  /// The X coordinate (pan) of the avatar in world space.
  final double x;

  /// The Y coordinate (pan) of the avatar in world space.
  final double y;

  /// The distance of the camera from the avatar (zoom level).
  final double zoom;

  const VrmTransform({
    required this.x,
    required this.y,
    required this.zoom,
  });

  Map<String, dynamic> toMap() {
    return {
      'x': x,
      'y': y,
      'zoom': zoom,
    };
  }

  factory VrmTransform.fromMap(Map<String, dynamic> map) {
    return VrmTransform(
      x: (map['x'] ?? 0.0).toDouble(),
      y: (map['y'] ?? 0.0).toDouble(),
      zoom: (map['zoom'] ?? 0.0).toDouble(),
    );
  }

  String toJson() => json.encode(toMap());

  factory VrmTransform.fromJson(String source) =>
      VrmTransform.fromMap(json.decode(source));

  @override
  String toString() => 'VrmTransform(x: $x, y: $y, zoom: $zoom)';
}
