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
