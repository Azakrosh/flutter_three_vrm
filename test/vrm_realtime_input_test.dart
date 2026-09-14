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
        () => controller.appendSpeechVisemes(<VisemeFrame>[
          VisemeFrame(
            viseme: VrmViseme.aa,
            timestamp: const Duration(milliseconds: -1),
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('rejects negative speech timing', () {
      expect(
        () => controller.beginSpeech(
          startDelay: const Duration(milliseconds: -1),
        ),
        throwsArgumentError,
      );
      expect(
        () => controller.finishSpeech(const Duration(milliseconds: -1)),
        throwsArgumentError,
      );
    });
  });
}
