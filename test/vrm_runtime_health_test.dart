import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';

void main() {
  group('VrmRuntimeHealth', () {
    test('parses a strict runtime capability snapshot', () {
      final health = VrmRuntimeHealth.fromJson(<String, Object>{
        'runtimeVersion': '0.2.0-dev.1',
        'protocolVersion': 3,
        'threeRevision': '180',
        'threeVrmVersion': '3.5.5',
        'webGlVersion': 2,
        'maxTextureSize': 16384,
        'maxTextures': 16,
        'maxVertexTextures': 16,
        'rendererTextureCount': 4,
        'estimatedTextureMemoryBytes': 67108864,
        'lastModelLoadDurationMs': 812.5,
        'modelLoaded': true,
        'animationActive': true,
        'animationPaused': false,
        'renderingPaused': false,
        'contextLost': false,
        'contextLossCount': 1,
      });

      expect(health.protocolVersion, 3);
      expect(health.threeRevision, '180');
      expect(health.webGlVersion, 2);
      expect(health.maxTextureSize, 16384);
      expect(health.rendererTextureCount, 4);
      expect(health.estimatedTextureMemoryBytes, 67108864);
      expect(health.lastModelLoadDurationMs, 812.5);
      expect(health.contextLossCount, 1);
      expect(health.modelLoaded, isTrue);
      expect(health.animationActive, isTrue);
      expect(health.animationPaused, isFalse);
    });

    test('rejects incomplete or malformed snapshots', () {
      expect(
        () => VrmRuntimeHealth.fromJson(const <String, Object>{}),
        throwsFormatException,
      );
      expect(
        () => VrmRuntimeHealth.fromJson(<String, Object>{'runtimeVersion': ''}),
        throwsFormatException,
      );
      expect(
        () => VrmRuntimeHealth.fromJson(<String, Object>{
          'runtimeVersion': 'test',
          'protocolVersion': 3.5,
        }),
        throwsFormatException,
      );
      final valid = <String, Object>{
        'runtimeVersion': 'test',
        'protocolVersion': 3,
        'threeRevision': '180',
        'threeVrmVersion': '3.5.5',
        'webGlVersion': 2,
        'maxTextureSize': 4096,
        'maxTextures': 16,
        'maxVertexTextures': 16,
        'rendererTextureCount': 0,
        'estimatedTextureMemoryBytes': 0,
        'lastModelLoadDurationMs': 0,
        'modelLoaded': false,
        'animationActive': false,
        'animationPaused': false,
        'renderingPaused': false,
        'contextLost': false,
        'contextLossCount': 0,
      };
      expect(
        () => VrmRuntimeHealth.fromJson(<String, Object>{
          ...valid,
          'contextLossCount': -1,
        }),
        throwsFormatException,
      );
      expect(
        () => VrmRuntimeHealth.fromJson(<String, Object>{
          ...valid,
          'lastModelLoadDurationMs': double.nan,
        }),
        throwsFormatException,
      );
    });
  });

  group('VrmRuntimeRecoveryPolicy', () {
    test('uses capped exponential backoff', () {
      const policy = VrmRuntimeRecoveryPolicy(
        baseDelay: Duration(milliseconds: 250),
        maxDelay: Duration(seconds: 1),
      );

      expect(policy.delayForAttempt(1), const Duration(milliseconds: 250));
      expect(policy.delayForAttempt(2), const Duration(milliseconds: 500));
      expect(policy.delayForAttempt(3), const Duration(seconds: 1));
      expect(policy.delayForAttempt(10), const Duration(seconds: 1));
    });

    test('rejects invalid retry configuration without relying on asserts', () {
      const negative = VrmRuntimeRecoveryPolicy(
        baseDelay: Duration(milliseconds: -1),
      );
      const invalidAttempts = VrmRuntimeRecoveryPolicy(maxAttempts: -1);

      expect(() => negative.delayForAttempt(1), throwsArgumentError);
      expect(invalidAttempts.validate, throwsArgumentError);
      expect(
        () => const VrmRuntimeRecoveryPolicy().delayForAttempt(0),
        throwsRangeError,
      );
    });

    test('compares equivalent policies by value', () {
      final first = VrmRuntimeRecoveryPolicy(
        baseDelay: const Duration(milliseconds: 300),
      );
      final second = VrmRuntimeRecoveryPolicy(
        baseDelay: const Duration(milliseconds: 300),
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });
  });
}
