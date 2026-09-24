import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';
import 'package:flutter_three_vrm/src/recovery/vrm_speech_session_state.dart';

void main() {
  group('VrmSpeechSessionState', () {
    test('finishing session remains active but rejects more frames', () {
      final state = VrmSpeechSessionState();
      final sessionId = state.activate(
        VrmSpeechMode.viseme,
        timestampMicros: 10,
      );

      expect(state.canAppend(sessionId), isTrue);
      expect(state.markFinishing(sessionId), isTrue);
      expect(state.isActive(sessionId), isTrue);
      expect(state.canAppend(sessionId), isFalse);

      state.clearFinishing(sessionId);
      expect(state.canAppend(sessionId), isTrue);
    });

    test('stale command failure cannot abandon a replacement session', () {
      final state = VrmSpeechSessionState();
      final first = state.activate(VrmSpeechMode.viseme, timestampMicros: 20);
      final second = state.activate(
        VrmSpeechMode.amplitude,
        timestampMicros: 20,
      );

      state.abandon(first);
      expect(state.isActive(second), isTrue);
      expect(state.activeMode, VrmSpeechMode.amplitude);
    });

    test('runtime loss invalidates the active handle and input revision', () {
      final state = VrmSpeechSessionState();
      final firstRevision = state.nextInputRevision();
      final sessionId = state.activate(
        VrmSpeechMode.viseme,
        timestampMicros: 30,
      );

      state.invalidateRuntime();

      expect(state.hasActiveSession, isFalse);
      expect(state.canAppend(sessionId), isFalse);
      expect(state.isActive(sessionId), isFalse);
      expect(state.nextInputRevision(), firstRevision + 2);
    });
  });
}
