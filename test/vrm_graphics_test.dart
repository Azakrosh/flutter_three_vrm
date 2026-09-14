import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';

void main() {
  group('VRM graphics models', () {
    test('serializes adaptive quality settings', () {
      const settings = VrmAdaptiveQualitySettings(
        targetFps: 60,
        minPixelRatio: 1,
        maxPixelRatio: 2,
      );

      expect(settings.toJson(), <String, Object>{
        'enabled': true,
        'targetFps': 60,
        'minPixelRatio': 1.0,
        'maxPixelRatio': 2.0,
      });
    });

    test('parses a strict performance snapshot', () {
      final snapshot = VrmPerformanceSnapshot.fromJson(<String, Object>{
        'fps': 57.5,
        'frameTimeMs': 17.4,
        'pixelRatio': 1.35,
        'fpsCap': 60,
        'physicsEnabled': true,
        'adaptiveQualityEnabled': true,
        'drawCalls': 42,
        'triangles': 120000,
        'geometries': 4,
        'textures': 8,
        'reason': 'performanceDown',
      });

      expect(snapshot.fps, 57.5);
      expect(snapshot.pixelRatio, 1.35);
      expect(snapshot.reason, 'performanceDown');
      expect(snapshot.triangles, 120000);
    });

    test('rejects malformed performance telemetry', () {
      expect(
        () => VrmPerformanceSnapshot.fromJson(<String, Object>{}),
        throwsFormatException,
      );
    });
  });
}
