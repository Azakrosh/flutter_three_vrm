import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';

void main() {
  group('VrmController realtime input validation', () {
    late VrmController controller;

    setUp(() => controller = VrmController());
    tearDown(() => controller.dispose());

    test('rejects non-finite direct input', () {
      expect(
        () => controller.setLipSyncAmplitude(double.nan),
        throwsArgumentError,
      );
      expect(
        () => controller.setViseme(VrmViseme.aa, weight: double.infinity),
        throwsArgumentError,
      );
      expect(
        () => controller.setLookAtTarget(const Offset(double.nan, 0)),
        throwsArgumentError,
      );
    });

    test('rejects invalid timeline frames before dispatch', () {
      expect(
        () => controller.enqueueSpeechVisemes(<VisemeFrame>[
          VisemeFrame(
            viseme: VrmViseme.aa,
            weight: 1.1,
            timestamp: Duration.zero,
          ),
        ]),
        throwsArgumentError,
      );
      expect(
        () => controller.enqueueSpeechVisemes(<VisemeFrame>[
          VisemeFrame(
            viseme: VrmViseme.aa,
            timestamp: const Duration(milliseconds: -1),
          ),
        ]),
        throwsArgumentError,
      );
      expect(
        () => controller.enqueueSpeechAmplitudes(<AmplitudeFrame>[
          const AmplitudeFrame(amplitude: 1.1, timestamp: Duration.zero),
        ]),
        throwsArgumentError,
      );
    });

    test('amplitude frames round-trip their timeline values', () {
      const frame = AmplitudeFrame(
        amplitude: 0.75,
        timestamp: Duration(milliseconds: 120),
        duration: Duration(milliseconds: 40),
      );

      final restored = AmplitudeFrame.fromJson(frame.toJson());
      expect(restored.amplitude, 0.75);
      expect(restored.timestamp, const Duration(milliseconds: 120));
      expect(restored.duration, const Duration(milliseconds: 40));
    });

    test('speech frames preserve the protocol-v3 wire representation', () {
      final viseme = VisemeFrame(
        viseme: VrmViseme.oh,
        weight: 0.6,
        timestamp: const Duration(milliseconds: 120),
        duration: const Duration(milliseconds: 80),
      );
      const amplitude = AmplitudeFrame(
        amplitude: 0.75,
        timestamp: Duration(milliseconds: 200),
        duration: Duration(milliseconds: 40),
      );

      expect(viseme.toJson(), <String, dynamic>{
        'viseme': 'oh',
        'weight': 0.6,
        'timestampMs': 120,
        'durationMs': 80,
      });
      expect(amplitude.toJson(), <String, dynamic>{
        'amplitude': 0.75,
        'timestampMs': 200,
        'durationMs': 40,
      });
      expect(VrmSpeechMode.values.map((mode) => mode.name), <String>[
        'viseme',
        'amplitude',
      ]);
    });

    test('rejects negative speech timing', () {
      expect(
        () => controller.beginSpeech(
          startDelay: const Duration(milliseconds: -1),
        ),
        throwsArgumentError,
      );
    });
  });
}
