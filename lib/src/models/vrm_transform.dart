import 'dart:convert';

/// Serializable pan and zoom state of the avatar camera.
final class VrmTransform {
  const VrmTransform({required this.x, required this.y, required this.zoom});

  final double x;
  final double y;
  final double zoom;

  Map<String, double> toMap() => <String, double>{'x': x, 'y': y, 'zoom': zoom};

  factory VrmTransform.fromMap(Map<String, dynamic> map) {
    return VrmTransform(
      x: _asDouble(map['x']),
      y: _asDouble(map['y']),
      zoom: _asDouble(map['zoom']),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory VrmTransform.fromJson(String source) {
    final Object? decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('VRM transform must be a JSON object.');
    }
    return VrmTransform.fromMap(decoded);
  }

  static double _asDouble(Object? value) => value is num ? value.toDouble() : 0;

  @override
  String toString() => 'VrmTransform(x: $x, y: $y, zoom: $zoom)';
}
