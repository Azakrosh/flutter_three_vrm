import 'dart:convert';

/// Serializable pan and zoom state of the avatar camera.
final class VrmTransform {
  const VrmTransform({required this.x, required this.y, required this.zoom});

  /// Horizontal framing offset relative to the avatar torso pivot.
  final double x;

  /// Vertical framing offset relative to the avatar torso pivot.
  final double y;

  /// Camera distance from the avatar torso pivot.
  final double zoom;

  /// Verifies values in both debug and release builds.
  void validate() {
    if (!x.isFinite) {
      throw ArgumentError.value(x, 'x', 'Must be finite.');
    }
    if (!y.isFinite) {
      throw ArgumentError.value(y, 'y', 'Must be finite.');
    }
    if (!zoom.isFinite || zoom <= 0) {
      throw ArgumentError.value(zoom, 'zoom', 'Must be positive and finite.');
    }
  }

  Map<String, double> toMap() {
    validate();
    return <String, double>{'x': x, 'y': y, 'zoom': zoom};
  }

  factory VrmTransform.fromMap(Map<String, dynamic> map) {
    return VrmTransform(
      x: _finiteDouble(map['x'], 'x'),
      y: _finiteDouble(map['y'], 'y'),
      zoom: _finiteDouble(map['zoom'], 'zoom', positive: true),
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

  static double _finiteDouble(
    Object? value,
    String name, {
    bool positive = false,
  }) {
    if (value case final num number when number.isFinite) {
      final result = number.toDouble();
      if (!positive || result > 0) return result;
    }
    throw FormatException(
      positive
          ? 'VRM transform $name must be a positive finite number.'
          : 'VRM transform $name must be a finite number.',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VrmTransform &&
      other.x == x &&
      other.y == y &&
      other.zoom == zoom;

  @override
  int get hashCode => Object.hash(x, y, zoom);

  @override
  String toString() => 'VrmTransform(x: $x, y: $y, zoom: $zoom)';
}
