import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';

void main() {
  group('VrmAnimationOptions', () {
    test('defaults to in-place root motion', () {
      const options = VrmAnimationOptions();

      expect(options.rootMotion, VrmRootMotion.inPlace);
      expect(options.toJson()['rootMotion'], 'inPlace');
    });

    test('round-trips named clips and full root motion', () {
      final restored = VrmAnimationOptions.fromJson(
        const VrmAnimationOptions(
          loop: false,
          speed: 1.25,
          fadeDuration: 0.2,
          rootMotion: VrmRootMotion.full,
          clipName: 'Talking',
        ).toJson(),
      );

      expect(restored.loop, isFalse);
      expect(restored.speed, 1.25);
      expect(restored.fadeDuration, 0.2);
      expect(restored.rootMotion, VrmRootMotion.full);
      expect(restored.clipName, 'Talking');
    });
  });

  group('VrmAnimationPlayback', () {
    test('preserves a non-empty opaque identifier', () {
      final playback = VrmAnimationPlayback(id: 'animation-42');

      expect(playback.id, 'animation-42');
    });

    test('rejects an empty identifier', () {
      expect(() => VrmAnimationPlayback(id: '  '), throwsArgumentError);
    });
  });
}
