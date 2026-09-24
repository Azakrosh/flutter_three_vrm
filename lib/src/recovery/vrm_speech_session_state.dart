import '../models/vrm_lip_sync_data.dart';

/// Owns identity and lifecycle of the speech timeline bound to one runtime.
final class VrmSpeechSessionState {
  int _sessionSequence = 0;
  int _inputRevision = 0;
  String? _activeSessionId;
  VrmSpeechMode? _activeMode;
  bool _isFinishing = false;

  String? get activeSessionId => _activeSessionId;
  VrmSpeechMode? get activeMode => _activeMode;
  bool get hasActiveSession => _activeSessionId != null;

  String activate(VrmSpeechMode mode, {int? timestampMicros}) {
    final sessionId =
        'speech-${timestampMicros ?? DateTime.now().microsecondsSinceEpoch}-'
        '${_sessionSequence++}';
    _activeSessionId = sessionId;
    _activeMode = mode;
    _isFinishing = false;
    return sessionId;
  }

  int nextInputRevision() => ++_inputRevision;

  bool canAppend(String sessionId) =>
      _activeSessionId == sessionId && !_isFinishing;

  bool isActive(String sessionId) => _activeSessionId == sessionId;

  bool markFinishing(String sessionId) {
    if (!canAppend(sessionId)) return false;
    _isFinishing = true;
    return true;
  }

  void clearFinishing(String sessionId) {
    if (_activeSessionId == sessionId) {
      _isFinishing = false;
    }
  }

  void abandon([String? expectedSessionId]) {
    if (expectedSessionId != null && expectedSessionId != _activeSessionId) {
      return;
    }
    _activeSessionId = null;
    _activeMode = null;
    _isFinishing = false;
  }

  /// Makes all handles and direct-input revisions from the old runtime stale.
  void invalidateRuntime() {
    nextInputRevision();
    abandon();
  }
}
