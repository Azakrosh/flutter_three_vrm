import '../bridge/vrm_protocol_contract.dart';
import '../models/vrm_lip_sync_data.dart';
import '../recovery/vrm_speech_session_state.dart';

typedef VrmSpeechCommandSender =
    Future<void> Function(
      VrmProtocolCommand action, [
      Map<String, dynamic>? payload,
    ]);

typedef VrmSpeechLatestCommandSender =
    void Function({
      required String channel,
      required VrmProtocolCommand action,
      required Map<String, dynamic> payload,
    });

typedef VrmSpeechLatestCommandClearer = void Function(String channel);

/// Internal identity returned after a speech session begins successfully.
final class VrmSpeechSessionToken {
  const VrmSpeechSessionToken({required this.id, required this.mode});

  final String id;
  final VrmSpeechMode mode;
}

/// Owns speech identity, realtime revisions, validation, and bridge commands.
final class VrmSpeechDispatcher {
  VrmSpeechDispatcher(
    this._ensureActive,
    this._sendCommand,
    this._sendLatestCommand,
    this._clearLatestCommand,
  );

  final void Function() _ensureActive;
  final VrmSpeechCommandSender _sendCommand;
  final VrmSpeechLatestCommandSender _sendLatestCommand;
  final VrmSpeechLatestCommandClearer _clearLatestCommand;
  final VrmSpeechSessionState _state = VrmSpeechSessionState();

  bool get hasActiveSession => _state.hasActiveSession;
  VrmSpeechMode? get activeMode => _state.activeMode;

  bool isActive(String sessionId) => _state.isActive(sessionId);

  void handleFinished(String sessionId) => _state.abandon(sessionId);

  void invalidateRuntime() {
    _state.invalidateRuntime();
    _clearDirectInputs();
  }

  /// Gives the mouth layer to a non-speech operation and returns its revision.
  int takeMouthControl() {
    _state.abandon();
    _clearDirectInputs();
    return _state.nextInputRevision();
  }

  void setAmplitude(double amplitude) {
    _ensureActive();
    if (!amplitude.isFinite) {
      throw ArgumentError.value(amplitude, 'amplitude', 'Must be finite.');
    }
    _state.abandon();
    final speechRevision = _state.nextInputRevision();
    _clearLatestCommand('directViseme');
    _sendLatestCommand(
      channel: 'lipSyncAmplitude',
      action: VrmProtocolCommand.setLipSyncAmplitude,
      payload: <String, dynamic>{
        'amplitude': amplitude.clamp(0.0, 1.0),
        'speechRevision': speechRevision,
      },
    );
  }

  void setViseme(VrmViseme viseme, {double weight = 1}) {
    _ensureActive();
    if (!weight.isFinite) {
      throw ArgumentError.value(weight, 'weight', 'Must be finite.');
    }
    _state.abandon();
    final speechRevision = _state.nextInputRevision();
    _clearLatestCommand('lipSyncAmplitude');
    _sendLatestCommand(
      channel: 'directViseme',
      action: VrmProtocolCommand.setViseme,
      payload: <String, dynamic>{
        'viseme': viseme.name,
        'weight': weight.clamp(0.0, 1.0),
        'speechRevision': speechRevision,
      },
    );
  }

  Future<void> enqueueVisemes(List<VisemeFrame> frames) async {
    if (frames.isEmpty) return;
    _validateVisemeFrames(frames);
    final sortedFrames = List<VisemeFrame>.from(frames)..sort();
    _clearDirectInputs();
    final sessionId = _state.activate(VrmSpeechMode.viseme);
    final speechRevision = _state.nextInputRevision();
    _state.markFinishing(sessionId);
    final timelineOriginEpochMs = DateTime.now().millisecondsSinceEpoch;
    try {
      await _sendCommand(VrmProtocolCommand.enqueueSpeechVisemes, {
        'sessionId': sessionId,
        'mode': VrmSpeechMode.viseme.name,
        'timelineOriginEpochMs': timelineOriginEpochMs,
        'speechRevision': speechRevision,
        'frames': sortedFrames.map((frame) => frame.toJson()).toList(),
      });
    } on Object {
      _state.abandon(sessionId);
      rethrow;
    }
  }

  Future<void> enqueueAmplitudes(List<AmplitudeFrame> frames) async {
    if (frames.isEmpty) return;
    _validateAmplitudeFrames(frames);
    final sortedFrames = List<AmplitudeFrame>.from(frames)..sort();
    _clearDirectInputs();
    final sessionId = _state.activate(VrmSpeechMode.amplitude);
    final speechRevision = _state.nextInputRevision();
    _state.markFinishing(sessionId);
    final timelineOriginEpochMs = DateTime.now().millisecondsSinceEpoch;
    try {
      await _sendCommand(VrmProtocolCommand.enqueueSpeechAmplitudes, {
        'sessionId': sessionId,
        'mode': VrmSpeechMode.amplitude.name,
        'timelineOriginEpochMs': timelineOriginEpochMs,
        'speechRevision': speechRevision,
        'frames': sortedFrames.map((frame) => frame.toJson()).toList(),
      });
    } on Object {
      _state.abandon(sessionId);
      rethrow;
    }
  }

  Future<VrmSpeechSessionToken> begin({
    VrmSpeechMode mode = VrmSpeechMode.viseme,
    Duration startDelay = Duration.zero,
  }) async {
    if (startDelay.isNegative) {
      throw ArgumentError.value(
        startDelay,
        'startDelay',
        'Must not be negative.',
      );
    }
    _clearDirectInputs();
    final sessionId = _state.activate(mode);
    final speechRevision = _state.nextInputRevision();
    final timelineOriginEpochMs = DateTime.now()
        .add(startDelay)
        .millisecondsSinceEpoch;
    try {
      await _sendCommand(VrmProtocolCommand.beginSpeech, {
        'sessionId': sessionId,
        'mode': mode.name,
        'timelineOriginEpochMs': timelineOriginEpochMs,
        'speechRevision': speechRevision,
      });
      return VrmSpeechSessionToken(id: sessionId, mode: mode);
    } on Object {
      _state.abandon(sessionId);
      rethrow;
    }
  }

  Future<bool> appendVisemes(String sessionId, List<VisemeFrame> frames) async {
    if (!_state.canAppend(sessionId)) return false;
    _validateVisemeFrames(frames);
    if (frames.isEmpty) return true;
    final sortedFrames = List<VisemeFrame>.from(frames)..sort();
    await _sendCommand(VrmProtocolCommand.appendSpeechVisemes, {
      'sessionId': sessionId,
      'frames': sortedFrames.map((frame) => frame.toJson()).toList(),
    });
    return true;
  }

  Future<bool> appendAmplitudes(
    String sessionId,
    List<AmplitudeFrame> frames,
  ) async {
    if (!_state.canAppend(sessionId)) return false;
    _validateAmplitudeFrames(frames);
    if (frames.isEmpty) return true;
    final sortedFrames = List<AmplitudeFrame>.from(frames)..sort();
    await _sendCommand(VrmProtocolCommand.appendSpeechAmplitudes, {
      'sessionId': sessionId,
      'frames': sortedFrames.map((frame) => frame.toJson()).toList(),
    });
    return true;
  }

  Future<bool> finish(String sessionId, Duration audioDuration) async {
    if (!_state.canAppend(sessionId)) return false;
    if (audioDuration.isNegative) {
      throw ArgumentError.value(
        audioDuration,
        'audioDuration',
        'Must not be negative.',
      );
    }
    _state.markFinishing(sessionId);
    try {
      await _sendCommand(VrmProtocolCommand.finishSpeech, {
        'sessionId': sessionId,
        'audioDurationMs': audioDuration.inMilliseconds,
      });
    } on Object {
      _state.clearFinishing(sessionId);
      rethrow;
    }
    return true;
  }

  Future<void> cancel() {
    _clearDirectInputs();
    final sessionId = _state.activeSessionId;
    _state.abandon();
    return _sendCommand(VrmProtocolCommand.cancelSpeech, {
      'sessionId': ?sessionId,
      'speechRevision': _state.nextInputRevision(),
    });
  }

  Future<bool> cancelSession(String sessionId) async {
    if (!_state.isActive(sessionId)) return false;
    _clearDirectInputs();
    _state.abandon(sessionId);
    await _sendCommand(VrmProtocolCommand.cancelSpeech, {
      'sessionId': sessionId,
      'speechRevision': _state.nextInputRevision(),
    });
    return true;
  }

  void _clearDirectInputs() {
    _clearLatestCommand('lipSyncAmplitude');
    _clearLatestCommand('directViseme');
  }

  void _validateVisemeFrames(List<VisemeFrame> frames) {
    for (var index = 0; index < frames.length; index += 1) {
      final frame = frames[index];
      if (!frame.weight.isFinite || frame.weight < 0 || frame.weight > 1) {
        throw ArgumentError.value(
          frame.weight,
          'frames[$index].weight',
          'Must be a finite value from 0 to 1.',
        );
      }
      if (frame.timestamp.isNegative) {
        throw ArgumentError.value(
          frame.timestamp,
          'frames[$index].timestamp',
          'Must not be negative.',
        );
      }
      if (frame.duration.isNegative) {
        throw ArgumentError.value(
          frame.duration,
          'frames[$index].duration',
          'Must not be negative.',
        );
      }
    }
  }

  void _validateAmplitudeFrames(List<AmplitudeFrame> frames) {
    for (var index = 0; index < frames.length; index += 1) {
      final frame = frames[index];
      if (!frame.amplitude.isFinite ||
          frame.amplitude < 0 ||
          frame.amplitude > 1) {
        throw ArgumentError.value(
          frame.amplitude,
          'frames[$index].amplitude',
          'Must be a finite value from 0 to 1.',
        );
      }
      if (frame.timestamp.isNegative) {
        throw ArgumentError.value(
          frame.timestamp,
          'frames[$index].timestamp',
          'Must not be negative.',
        );
      }
      if (frame.duration.isNegative) {
        throw ArgumentError.value(
          frame.duration,
          'frames[$index].duration',
          'Must not be negative.',
        );
      }
    }
  }
}
