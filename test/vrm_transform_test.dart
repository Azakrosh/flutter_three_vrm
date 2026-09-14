import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';

void main() {
  group('VrmTransform', () {
    test('round-trips a finite pan and zoom state', () {
      const transform = VrmTransform(x: 0.2, y: -0.1, zoom: 1.4);

      final restored = VrmTransform.fromJson(transform.toJson());

      expect(restored, transform);
      expect(restored.hashCode, transform.hashCode);
    });

    test('rejects missing, non-finite, and non-positive values', () {
      expect(
        () => VrmTransform.fromMap(<String, dynamic>{}),
        throwsFormatException,
      );
      expect(
        () => VrmTransform.fromMap(<String, dynamic>{
          'x': double.nan,
          'y': 0,
          'zoom': 1,
        }),
        throwsFormatException,
      );
      expect(
        () =>
            VrmTransform.fromMap(<String, dynamic>{'x': 0, 'y': 0, 'zoom': 0}),
        throwsFormatException,
      );
    });
  });
}
