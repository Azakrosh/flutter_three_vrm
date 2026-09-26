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

    test('rejects invalid adaptive settings without relying on asserts', () {
      const invalidFps = VrmAdaptiveQualitySettings(targetFps: 121);
      const invalidMinimum = VrmAdaptiveQualitySettings(
        minPixelRatio: double.nan,
      );
      const inverted = VrmAdaptiveQualitySettings(
        minPixelRatio: 2,
        maxPixelRatio: 1,
      );

      expect(invalidFps.validate, throwsArgumentError);
      expect(invalidMinimum.toJson, throwsArgumentError);
      expect(inverted.validate, throwsArgumentError);
    });

    test('parses a strict performance snapshot', () {
      final snapshot = VrmPerformanceSnapshot.fromJson(<String, Object>{
        'fps': 57.5,
        'frameTimeMs': 17.4,
        'frameTimeP50Ms': 16.8,
        'frameTimeP95Ms': 24.2,
        'frameSampleCount': 60,
        'longFrameCount': 1,
        'longestFrameMs': 32.0,
        'longFrameThresholdMs': 25.0,
        'updateTimeP95Ms': 4.2,
        'renderTimeP95Ms': 18.0,
        'longFrameSource': 'renderSubmission',
        'pixelRatio': 1.35,
        'fpsCap': 60,
        'physicsEnabled': true,
        'adaptiveQualityEnabled': true,
        'adaptiveTargetFps': 60,
        'adaptiveSlowWindowCount': 3,
        'adaptiveFastWindowCount': 0,
        'adaptiveCooldownRemainingMs': 0.0,
        'adaptiveDecision': 'decrease',
        'drawCalls': 42,
        'triangles': 120000,
        'geometries': 4,
        'textures': 8,
        'reason': 'performanceDown',
      });

      expect(snapshot.fps, 57.5);
      expect(snapshot.pixelRatio, 1.35);
      expect(snapshot.frameTimeP50Ms, 16.8);
      expect(snapshot.frameTimeP95Ms, 24.2);
      expect(snapshot.longFrameCount, 1);
      expect(snapshot.longFrameSource, VrmLongFrameSource.renderSubmission);
      expect(snapshot.adaptiveDecision, VrmAdaptiveQualityDecision.decrease);
      expect(snapshot.reason, VrmPerformanceReason.performanceDown);
      expect(snapshot.triangles, 120000);
    });

    test('rejects malformed performance telemetry', () {
      expect(
        () => VrmPerformanceSnapshot.fromJson(<String, Object>{}),
        throwsFormatException,
      );
      expect(
        () => VrmPerformanceSnapshot.fromJson(<String, Object>{
          'fps': 60,
          'frameTimeMs': 16.67,
          'frameTimeP50Ms': 16.5,
          'frameTimeP95Ms': 18.2,
          ..._validPerformanceDiagnostics,
          'pixelRatio': 1,
          'fpsCap': 59.5,
          'physicsEnabled': true,
          'adaptiveQualityEnabled': true,
          'drawCalls': 1,
          'triangles': 2,
          'geometries': 3,
          'textures': 4,
          'reason': 'sample',
        }),
        throwsFormatException,
      );
      expect(
        () => VrmPerformanceSnapshot.fromJson(<String, Object>{
          'fps': 60,
          'frameTimeMs': 16.67,
          'frameTimeP50Ms': 20,
          'frameTimeP95Ms': 18,
          ..._validPerformanceDiagnostics,
          'pixelRatio': 1,
          'fpsCap': 60,
          'physicsEnabled': true,
          'adaptiveQualityEnabled': true,
          'drawCalls': 1,
          'triangles': 2,
          'geometries': 3,
          'textures': 4,
          'reason': 'sample',
        }),
        throwsFormatException,
      );
      expect(
        () => VrmPerformanceSnapshot.fromJson(<String, Object>{
          'fps': 60,
          'frameTimeMs': 16.67,
          'frameTimeP50Ms': 16.5,
          'frameTimeP95Ms': 18.2,
          ..._validPerformanceDiagnostics,
          'pixelRatio': 1,
          'fpsCap': 60,
          'physicsEnabled': true,
          'adaptiveQualityEnabled': true,
          'drawCalls': 1,
          'triangles': 2,
          'geometries': 3,
          'textures': 4,
          'reason': 'unknown',
        }),
        throwsFormatException,
      );
    });
  });
}

const _validPerformanceDiagnostics = <String, Object>{
  'frameSampleCount': 60,
  'longFrameCount': 0,
  'longestFrameMs': 0.0,
  'longFrameThresholdMs': 25.0,
  'updateTimeP95Ms': 2.0,
  'renderTimeP95Ms': 3.0,
  'longFrameSource': 'none',
  'adaptiveTargetFps': 60,
  'adaptiveSlowWindowCount': 0,
  'adaptiveFastWindowCount': 1,
  'adaptiveCooldownRemainingMs': 0.0,
  'adaptiveDecision': 'collectingFast',
};
