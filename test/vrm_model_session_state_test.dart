import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/src/recovery/vrm_model_session_state.dart';

void main() {
  group('VrmModelSessionState', () {
    test('runtime loss prevents a stale load from becoming current', () {
      final state = VrmModelSessionState();
      final generation = state.beginLoad();
      expect(state.isLoading, isTrue);

      state.invalidateRuntime();
      expect(state.isLoading, isFalse);
      expect(state.isLoaded, isFalse);

      expect(state.completeLoad(generation), isFalse);
      state.finishLoad(generation);
      expect(state.isLoaded, isFalse);
      expect(state.isLoading, isFalse);
    });

    test('a replacement load owns completion and loading state', () {
      final state = VrmModelSessionState();
      final first = state.beginLoad();
      final second = state.beginLoad();

      expect(state.completeLoad(first), isFalse);
      state.finishLoad(first);
      expect(state.isLoading, isTrue);

      expect(state.completeLoad(second), isTrue);
      state.finishLoad(second);
      expect(state.isLoading, isFalse);
      expect(state.isLoaded, isTrue);
    });

    test('cancel keeps the previously displayed model', () {
      final state = VrmModelSessionState()..setLoaded(true);
      final generation = state.beginLoad();

      state.cancelLoad();
      expect(state.isLoading, isFalse);
      expect(state.isLoaded, isTrue);
      expect(state.completeLoad(generation), isFalse);
    });
  });
}
