part of 'vrm_runtime.dart';

/// Primary controller for loading, animating, and interacting with one VRM model.
class VrmController {
  final _VrmBridge _bridge = _VrmBridge();
  late final StreamSubscription<VrmEvent> _stateSubscription;
  bool _isLoadingModel = false;
  bool _isModelLoaded = false;
  int _modelLoadGeneration = 0;
  VrmTransform? _lastKnownCameraTransform;
  int _cameraTransformRevision = 0;
  VrmContentHost? _contentHost;
  int _speechSessionSequence = 0;
  int _speechInputRevision = 0;
  String? _activeSpeechSessionId;
  VrmSpeechMode? _activeSpeechMode;
  bool _speechIsFinishing = false;

  VrmController() {
    _stateSubscription = _bridge.eventStream.listen((event) {
      switch (event) {
        case VrmModelLoadedEvent():
          _isModelLoaded = true;
        case VrmModelUnloadedEvent():
          _isModelLoaded = false;
        case VrmCameraChangedEvent(
          :final x,
          :final y,
          :final zoom,
          :final userInitiated,
        ):
          if (userInitiated && x != null && y != null && zoom != null) {
            _lastKnownCameraTransform = VrmTransform(x: x, y: y, zoom: zoom);
            _cameraTransformRevision += 1;
          }
        case VrmSpeechFinishedEvent(:final sessionId):
          _abandonSpeechSession(sessionId);
        default:
          break;
      }
    });
  }

  /// True while a model is being transferred and parsed by the runtime.
  bool get isLoadingModel => _isLoadingModel;

  /// Whether the currently attached runtime contains an avatar.
  bool get isModelLoaded => _isModelLoaded;

  /// Whether the JavaScript runtime completed protocol initialization.
  bool get isRuntimeReady => _bridge.isRuntimeReady;

  /// Whether a speech timeline is active or waiting for its declared end.
  bool get isSpeechActive => _activeSpeechSessionId != null;

  /// Input type accepted by the current speech timeline.
  VrmSpeechMode? get speechMode => _activeSpeechMode;

  void _attachContentHost(VrmContentHost contentHost) {
    _contentHost = contentHost;
  }

  void _detachContentHost(VrmContentHost contentHost) {
    if (identical(_contentHost, contentHost)) {
      _contentHost = null;
      _isModelLoaded = false;
    }
  }

  VrmContentHost get _requiredContentHost {
    final contentHost = _contentHost;
    if (contentHost == null || !contentHost.isStarted) {
      throw StateError(
        'VrmView is not ready. Wait for VrmView.onCreated before loading '
        'assets or local files.',
      );
    }
    return contentHost;
  }

  void _sendCommand(String action, [Map<String, dynamic>? payload]) {
    unawaited(
      _bridge.sendCommand(action, payload).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        _bridge.reportAsyncError(error, stackTrace);
      }),
    );
  }

  Future<void> _sendHostedResourceCommand({
    required Uri Function(VrmContentHost host) expose,
    required String action,
    required String fileName,
    String urlField = 'url',
    Map<String, dynamic>? payload,
  }) async {
    final host = _requiredContentHost;
    final uri = expose(host);
    try {
      await _bridge.sendCommand(action, <String, dynamic>{
        ...?payload,
        urlField: uri.toString(),
        'fileName': fileName,
      });
    } finally {
      host.release(uri);
    }
  }

  // --- Model lifecycle ---

  /// Loads a VRM model from Flutter assets.
  Future<void> loadModel(String folderPath, String fileName) async {
    final loadGeneration = ++_modelLoadGeneration;
    _isLoadingModel = true;
    try {
      await _sendHostedResourceCommand(
        expose: (host) => host.exposeAsset('$folderPath$fileName'),
        action: 'loadModelFromUrl',
        fileName: fileName,
      );
      if (loadGeneration == _modelLoadGeneration) {
        _isModelLoaded = true;
      }
    } finally {
      if (loadGeneration == _modelLoadGeneration) {
        _isLoadingModel = false;
      }
    }
  }

  /// Loads a VRM model from a local file.
  Future<void> loadModelFromFile(io.File file) async {
    final loadGeneration = ++_modelLoadGeneration;
    _isLoadingModel = true;
    try {
      await _sendHostedResourceCommand(
        expose: (host) => host.exposeFile(file),
        action: 'loadModelFromUrl',
        fileName: p.basename(file.path),
      );
      if (loadGeneration == _modelLoadGeneration) {
        _isModelLoaded = true;
      }
    } finally {
      if (loadGeneration == _modelLoadGeneration) {
        _isLoadingModel = false;
      }
    }
  }

  /// Loads VRM bytes obtained by an authenticated Flutter API client.
  ///
  /// For very large models prefer [loadModelFromFile] to avoid retaining the
  /// complete file in Dart memory.
  Future<void> loadModelFromBytes(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final loadGeneration = ++_modelLoadGeneration;
    _isLoadingModel = true;
    try {
      await _sendHostedResourceCommand(
        expose: (host) => host.exposeBytes(bytes, fileName: fileName),
        action: 'loadModelFromUrl',
        fileName: fileName,
      );
      if (loadGeneration == _modelLoadGeneration) {
        _isModelLoaded = true;
      }
    } finally {
      if (loadGeneration == _modelLoadGeneration) {
        _isLoadingModel = false;
      }
    }
  }

  /// Loads a public URL directly in WebView.
  ///
  /// Prefer [loadModelFromFile] or [loadModelFromBytes] for authenticated URLs.
  Future<void> loadModelFromUrl(String url) async {
    final loadGeneration = ++_modelLoadGeneration;
    _isLoadingModel = true;
    try {
      await _bridge.sendCommand('loadModelFromUrl', {
        'url': url,
        'fileName': Uri.parse(url).pathSegments.lastOrNull ?? 'avatar.vrm',
      });
      if (loadGeneration == _modelLoadGeneration) {
        _isModelLoaded = true;
      }
    } finally {
      if (loadGeneration == _modelLoadGeneration) {
        _isLoadingModel = false;
      }
    }
  }

  /// Cancels the active model transfer or parse operation.
  ///
  /// The previously displayed avatar remains active. The canceled load Future
  /// completes with `VrmRuntimeException(code: 'canceled')`.
  Future<void> cancelModelLoad() async {
    _modelLoadGeneration += 1;
    _isLoadingModel = false;
    await _bridge.sendCommand('cancelModelLoad');
  }

  /// Returns the diagnostic report for the current avatar.
  Future<VrmModelReport> getModelReport() async {
    final result = await _bridge.requestCommand('getModelReport');
    return VrmModelReport.fromJson(result);
  }

  /// Waits for the attached runtime to become ready for commands.
  Future<void> waitUntilReady({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (_bridge.isRuntimeReady) return;
    await onStateChanged
        .firstWhere((event) => event.state == 'initialized')
        .timeout(timeout);
  }

  /// Returns runtime versions, WebGL limits, and current engine state.
  Future<VrmRuntimeHealth> getRuntimeHealth() async {
    final result = await _bridge.requestCommand('getRuntimeHealth');
    final health = VrmRuntimeHealth.fromJson(result);
    _isModelLoaded = health.modelLoaded;
    return health;
  }

  /// Reloads the embedded runtime. [VrmView.onCreated] runs again afterwards.
  Future<void> reloadRuntime() async {
    _isModelLoaded = false;
    _abandonSpeechSession();
    await _bridge.reloadRuntime();
  }

  void _markRuntimeUnavailable(Object error) {
    _isModelLoaded = false;
    _abandonSpeechSession();
    _bridge.markRuntimeUnavailable(error);
  }

  void _publishModelAssessment(VrmModelAssessment assessment) {
    _bridge.publishEvent(VrmModelAssessmentEvent(assessment: assessment));
  }

  /// Unloads the model and releases its GPU resources.
  Future<void> unloadModel() async {
    _modelLoadGeneration += 1;
    _isLoadingModel = false;
    _abandonSpeechSession();
    _clearDirectSpeechInputs();
    await _bridge.sendCommand('unloadModel', {
      'speechRevision': _nextSpeechRevision(),
    });
    _isModelLoaded = false;
    _lastKnownCameraTransform = null;
    _cameraTransformRevision += 1;
  }

  /// Disposes this controller and its event streams.
  Future<void> dispose() async {
    _isModelLoaded = false;
    _abandonSpeechSession();
    await _stateSubscription.cancel();
    await _bridge.dispose();
  }

  Future<void> _setRenderingPaused(bool paused) =>
      _bridge.sendCommand(paused ? 'pauseRendering' : 'resumeRendering');

  // --- Animation control ---

  /// Plays a VRMA animation from Flutter assets.
  Future<void> playAnimation(
    String folderPath,
    String fileName, {
    bool loop = true,
    double speed = 1,
    double fadeDuration = 0.5,
    VrmRootMotion rootMotion = VrmRootMotion.inPlace,
    String? clipName,
  }) {
    return _playHostedAnimation(
      expose: (host) => host.exposeAsset('$folderPath$fileName'),
      fileName: fileName,
      loop: loop,
      speed: speed,
      fadeDuration: fadeDuration,
      rootMotion: rootMotion,
      clipName: clipName,
    );
  }

  /// Plays a VRMA or glTF animation from a local file.
  Future<void> playAnimationFromFile(
    io.File file, {
    bool loop = true,
    double speed = 1,
    double fadeDuration = 0.5,
    VrmRootMotion rootMotion = VrmRootMotion.inPlace,
    String? clipName,
  }) {
    return _playHostedAnimation(
      expose: (host) => host.exposeFile(file),
      fileName: p.basename(file.path),
      loop: loop,
      speed: speed,
      fadeDuration: fadeDuration,
      rootMotion: rootMotion,
      clipName: clipName,
    );
  }

  /// Plays VRMA or glTF animation bytes obtained by Flutter.
  Future<void> playAnimationFromBytes(
    Uint8List bytes, {
    required String fileName,
    bool loop = true,
    double speed = 1,
    double fadeDuration = 0.5,
    VrmRootMotion rootMotion = VrmRootMotion.inPlace,
    String? clipName,
  }) {
    return _playHostedAnimation(
      expose: (host) => host.exposeBytes(bytes, fileName: fileName),
      fileName: fileName,
      loop: loop,
      speed: speed,
      fadeDuration: fadeDuration,
      rootMotion: rootMotion,
      clipName: clipName,
    );
  }

  /// Plays an external-resource glTF animation from an explicit file bundle.
  ///
  /// Keys are safe relative URI paths used by the glTF document, for example
  /// `animation.gltf`, `animation.bin`, and `textures/atlas.png`.
  Future<void> playAnimationFromFileBundle(
    Map<String, io.File> files, {
    required String entryFileName,
    bool loop = true,
    double speed = 1,
    double fadeDuration = 0.5,
    VrmRootMotion rootMotion = VrmRootMotion.inPlace,
    String? clipName,
  }) {
    return _playHostedAnimation(
      expose: (host) =>
          host.exposeFileBundle(files, entryFileName: entryFileName),
      fileName: entryFileName,
      loop: loop,
      speed: speed,
      fadeDuration: fadeDuration,
      rootMotion: rootMotion,
      clipName: clipName,
    );
  }

  /// Plays an external-resource glTF animation from authenticated bytes.
  ///
  /// Every URI referenced by the entrypoint must be present in [files].
  Future<void> playAnimationFromBytesBundle(
    Map<String, Uint8List> files, {
    required String entryFileName,
    bool loop = true,
    double speed = 1,
    double fadeDuration = 0.5,
    VrmRootMotion rootMotion = VrmRootMotion.inPlace,
    String? clipName,
  }) {
    return _playHostedAnimation(
      expose: (host) =>
          host.exposeBytesBundle(files, entryFileName: entryFileName),
      fileName: entryFileName,
      loop: loop,
      speed: speed,
      fadeDuration: fadeDuration,
      rootMotion: rootMotion,
      clipName: clipName,
    );
  }

  Future<void> _playHostedAnimation({
    required Uri Function(VrmContentHost host) expose,
    required String fileName,
    required bool loop,
    required double speed,
    required double fadeDuration,
    required VrmRootMotion rootMotion,
    required String? clipName,
  }) {
    final options = VrmAnimationOptions(
      loop: loop,
      speed: speed,
      fadeDuration: fadeDuration,
      rootMotion: rootMotion,
      clipName: clipName,
    );
    return _sendHostedResourceCommand(
      expose: expose,
      action: 'playAnimationFromUrl',
      fileName: fileName,
      payload: {'options': options.toJson()},
    );
  }

  /// Plays a VRMA or glTF animation from a public URL.
  Future<void> playAnimationFromUrl(
    String url, {
    bool loop = true,
    double speed = 1,
    double fadeDuration = 0.5,
    VrmRootMotion rootMotion = VrmRootMotion.inPlace,
    String? clipName,
  }) {
    final options = VrmAnimationOptions(
      loop: loop,
      speed: speed,
      fadeDuration: fadeDuration,
      rootMotion: rootMotion,
      clipName: clipName,
    );
    return _bridge.sendCommand('playAnimationFromUrl', {
      'url': url,
      'fileName': Uri.parse(url).pathSegments.lastOrNull ?? 'animation.vrma',
      'options': options.toJson(),
    });
  }

  /// Pauses animation clip playback.
  Future<void> pauseAnimation() async {
    await _bridge.sendCommand('pauseAnimation');
  }

  /// Resumes animation clip playback.
  Future<void> resumeAnimation({double speed = 1.0}) async {
    await _bridge.sendCommand('resumeAnimation', {'speed': speed});
  }

  /// Cancels an animation transfer without stopping the current action.
  Future<void> cancelAnimationLoad() {
    return _bridge.sendCommand('cancelAnimationLoad');
  }

  /// Stops the current action and cancels an in-flight animation load.
  Future<void> stopAnimation({double fadeDuration = 0.5}) async {
    await _bridge.sendCommand('stopAnimation', {'fadeDuration': fadeDuration});
  }

  /// Sets playback speed multiplier for current animation.
  Future<void> setAnimationSpeed(double speed) async {
    await _bridge.sendCommand('setAnimationSpeed', {'speed': speed});
  }

  // --- Humanoid pose ---

  /// Returns the model's normalized humanoid pose.
  ///
  /// Bone transforms are relative to the normalized rest pose defined by
  /// `@pixiv/three-vrm`, so the result can be stored and applied to another
  /// compatible VRM avatar.
  Future<VrmPose> getPose() async {
    final result = await _bridge.requestCommand('getPose');
    return VrmPose.fromJson(result);
  }

  /// Applies a normalized humanoid [pose].
  ///
  /// Pose and clip playback share one mixer, so switching from either source
  /// crossfades without snapping through the rest pose.
  Future<void> setPose(VrmPose pose, {double fadeDuration = 0.5}) {
    return _bridge.sendCommand('setPose', {
      'pose': pose.toJson(),
      'fadeDuration': fadeDuration,
    });
  }

  /// Smoothly restores all normalized humanoid bones to their rest transforms.
  Future<void> resetPose({double fadeDuration = 0.5}) {
    return _bridge.sendCommand('resetPose', {'fadeDuration': fadeDuration});
  }

  // --- Mood Presets ---

  /// Applies a mood preset that combines expression, wind, physics,
  /// and saccades into a single call.
  ///
  /// ```dart
  /// controller.setMood(VrmMood.happy);
  /// controller.setMood(VrmMood.custom(
  ///   expression: VrmExpression.sad,
  ///   expressionWeight: 0.7,
  ///   disableAutoBlink: false,
  /// ));
  /// ```
  void setMood(VrmMood mood, {bool disableAutoBlink = false}) {
    // Eyes layer
    if (mood.expression != null) {
      setExpression(
        mood.expression!,
        layer: ExpressionLayer.eyes,
        weight: mood.expressionWeight,
        disableAutoBlink: disableAutoBlink,
      );
    }

    // Brows layer
    if (mood.browExpression != null) {
      setExpression(
        mood.browExpression!,
        layer: ExpressionLayer.brows,
        weight: mood.browWeight,
        disableAutoBlink: disableAutoBlink,
      );
    } else {
      clearExpressionLayer(ExpressionLayer.brows);
    }

    // Wind
    if (mood.wind != null) {
      setWind(type: mood.wind!.type, direction: mood.wind!.direction);
    } else {
      stopWind();
    }

    // Physics
    if (mood.physics != null) {
      setPhysics(
        stiffness: mood.physics!.stiffness,
        gravity: mood.physics!.gravity,
        drag: mood.physics!.drag,
      );
    } else {
      setPhysics(); // reset to defaults
    }

    // Saccades
    if (mood.autoSaccades != null) {
      setAutoSaccades(enabled: mood.autoSaccades!);
    }
  }

  /// Resets the avatar to a neutral mood (clears expressions, stops wind,
  /// resets physics to defaults, enables saccades).
  void clearMood() {
    setMood(VrmMood.neutral);
  }

  // --- Expressions & Layers ---

  /// Sets an expression on a specific expression layer (eyes, mouth, brows).
  /// If [layer] is not provided, it defaults to the recommended layer for the expression.
  void setExpression(
    VrmExpression expression, {
    ExpressionLayer? layer,
    double weight = 1.0,
    Duration duration = const Duration(milliseconds: 250),
    bool disableAutoBlink = false,
  }) {
    final resolvedLayer = layer ?? expression.defaultLayer;
    int? speechRevision;
    if (resolvedLayer == ExpressionLayer.mouth) {
      _abandonSpeechSession();
      _clearDirectSpeechInputs();
      speechRevision = _nextSpeechRevision();
    }
    _sendCommand('setExpression', {
      'expression': expression.name,
      'layer': resolvedLayer.name,
      'weight': weight,
      'duration': duration.inMilliseconds / 1000.0,
      'disableAutoBlink': disableAutoBlink,
      'speechRevision': ?speechRevision,
    });
  }

  /// Clears active expression from a layer.
  void clearExpressionLayer(ExpressionLayer layer) {
    int? speechRevision;
    if (layer == ExpressionLayer.mouth) {
      _abandonSpeechSession();
      _clearDirectSpeechInputs();
      speechRevision = _nextSpeechRevision();
    }
    _sendCommand('clearExpressionLayer', {
      'layer': layer.name,
      'speechRevision': ?speechRevision,
    });
  }

  /// Clears all active facial expressions, blendshapes, and visemes.
  void clearAllExpressions() {
    _abandonSpeechSession();
    _clearDirectSpeechInputs();
    _sendCommand('clearAllExpressions', {
      'speechRevision': _nextSpeechRevision(),
    });
  }

  /// Sets a custom blendshape key by name and weight (0.0 to 1.0).
  void setCustomBlendShape(String name, double weight) {
    _sendCommand('setCustomBlendShape', {'name': name, 'weight': weight});
  }

  // --- Lip Sync (ElevenLabs & Amplitude) ---

  /// Sets real-time audio volume amplitude (0.0 to 1.0) for smooth speech mouth opening.
  void setLipSyncAmplitude(double amplitude) {
    if (!amplitude.isFinite) {
      throw ArgumentError.value(amplitude, 'amplitude', 'Must be finite.');
    }
    _abandonSpeechSession();
    final speechRevision = _nextSpeechRevision();
    _bridge
      ..clearLatestCommand('directViseme')
      ..sendLatestCommand(
        channel: 'lipSyncAmplitude',
        action: 'setLipSyncAmplitude',
        payload: {
          'amplitude': amplitude.clamp(0.0, 1.0),
          'speechRevision': speechRevision,
        },
      );
  }

  /// Sets the latest direct viseme state without queueing stale bridge updates.
  void setViseme(VrmViseme viseme, {double weight = 1.0}) {
    if (!weight.isFinite) {
      throw ArgumentError.value(weight, 'weight', 'Must be finite.');
    }
    _abandonSpeechSession();
    final speechRevision = _nextSpeechRevision();
    _bridge
      ..clearLatestCommand('lipSyncAmplitude')
      ..sendLatestCommand(
        channel: 'directViseme',
        action: 'setViseme',
        payload: {
          'viseme': viseme.name,
          'weight': weight.clamp(0.0, 1.0),
          'speechRevision': speechRevision,
        },
      );
  }

  /// Enqueues a list of timed speech viseme frames for TTS playback.
  Future<void> enqueueSpeechVisemes(List<VisemeFrame> frames) async {
    if (frames.isEmpty) return;
    _validateVisemeFrames(frames);
    final sortedFrames = List<VisemeFrame>.from(frames)..sort();
    _clearDirectSpeechInputs();
    final sessionId = _activateSpeechSession(VrmSpeechMode.viseme);
    final speechRevision = _nextSpeechRevision();
    _speechIsFinishing = true;
    final timelineOriginEpochMs = DateTime.now().millisecondsSinceEpoch;
    try {
      await _bridge.sendCommand('enqueueSpeechVisemes', {
        'sessionId': sessionId,
        'mode': VrmSpeechMode.viseme.name,
        'timelineOriginEpochMs': timelineOriginEpochMs,
        'speechRevision': speechRevision,
        'frames': sortedFrames.map((frame) => frame.toJson()).toList(),
      });
    } on Object {
      _abandonSpeechSession(sessionId);
      rethrow;
    }
  }

  /// Enqueues a complete timestamped amplitude timeline in one command.
  Future<void> enqueueSpeechAmplitudes(List<AmplitudeFrame> frames) async {
    if (frames.isEmpty) return;
    _validateAmplitudeFrames(frames);
    final sortedFrames = List<AmplitudeFrame>.from(frames)..sort();
    _clearDirectSpeechInputs();
    final sessionId = _activateSpeechSession(VrmSpeechMode.amplitude);
    final speechRevision = _nextSpeechRevision();
    _speechIsFinishing = true;
    final timelineOriginEpochMs = DateTime.now().millisecondsSinceEpoch;
    try {
      await _bridge.sendCommand('enqueueSpeechAmplitudes', {
        'sessionId': sessionId,
        'mode': VrmSpeechMode.amplitude.name,
        'timelineOriginEpochMs': timelineOriginEpochMs,
        'speechRevision': speechRevision,
        'frames': sortedFrames.map((frame) => frame.toJson()).toList(),
      });
    } on Object {
      _abandonSpeechSession(sessionId);
      rethrow;
    }
  }

  /// Starts a real-time speech timeline without pause or seek semantics.
  ///
  /// Frame timestamps are relative to the instant this method is called plus
  /// [startDelay]. Bridge latency is compensated inside the WebView. Invoke
  /// this alongside audio playback rather than awaiting it before starting
  /// the player.
  Future<void> beginSpeech({
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
    _clearDirectSpeechInputs();
    final sessionId = _activateSpeechSession(mode);
    final speechRevision = _nextSpeechRevision();
    final timelineOriginEpochMs = DateTime.now()
        .add(startDelay)
        .millisecondsSinceEpoch;
    try {
      await _bridge.sendCommand('beginSpeech', {
        'sessionId': sessionId,
        'mode': mode.name,
        'timelineOriginEpochMs': timelineOriginEpochMs,
        'speechRevision': speechRevision,
      });
    } on Object {
      _abandonSpeechSession(sessionId);
      rethrow;
    }
  }

  /// Appends timed frames to the active streaming speech timeline.
  Future<void> appendSpeechVisemes(List<VisemeFrame> frames) {
    if (frames.isEmpty) return Future<void>.value();
    _validateVisemeFrames(frames);
    final sortedFrames = List<VisemeFrame>.from(frames)..sort();
    final sessionId = _requireSpeechSession(VrmSpeechMode.viseme);
    return _bridge.sendCommand('appendSpeechVisemes', {
      'sessionId': sessionId,
      'frames': sortedFrames.map((f) => f.toJson()).toList(),
    });
  }

  /// Appends timestamped amplitude samples to an amplitude speech timeline.
  Future<void> appendSpeechAmplitudes(List<AmplitudeFrame> frames) {
    if (frames.isEmpty) return Future<void>.value();
    _validateAmplitudeFrames(frames);
    final sortedFrames = List<AmplitudeFrame>.from(frames)..sort();
    final sessionId = _requireSpeechSession(VrmSpeechMode.amplitude);
    return _bridge.sendCommand('appendSpeechAmplitudes', {
      'sessionId': sessionId,
      'frames': sortedFrames.map((frame) => frame.toJson()).toList(),
    });
  }

  /// Marks a streaming speech timeline as complete.
  Future<void> finishSpeech(Duration audioDuration) async {
    if (audioDuration.isNegative) {
      throw ArgumentError.value(
        audioDuration,
        'audioDuration',
        'Must not be negative.',
      );
    }
    final sessionId = _requireSpeechSession();
    _speechIsFinishing = true;
    try {
      await _bridge.sendCommand('finishSpeech', {
        'sessionId': sessionId,
        'audioDurationMs': audioDuration.inMilliseconds,
      });
    } on Object {
      if (_activeSpeechSessionId == sessionId) {
        _speechIsFinishing = false;
      }
      rethrow;
    }
  }

  /// Fully stops the active speech timeline and closes the mouth layer.
  Future<void> cancelSpeech() {
    _clearDirectSpeechInputs();
    final sessionId = _activeSpeechSessionId;
    _abandonSpeechSession();
    return _bridge.sendCommand('cancelSpeech', {
      'sessionId': ?sessionId,
      'speechRevision': _nextSpeechRevision(),
    });
  }

  String _activateSpeechSession(VrmSpeechMode mode) {
    final sessionId =
        'speech-${DateTime.now().microsecondsSinceEpoch}-${_speechSessionSequence++}';
    _activeSpeechSessionId = sessionId;
    _activeSpeechMode = mode;
    _speechIsFinishing = false;
    return sessionId;
  }

  int _nextSpeechRevision() => ++_speechInputRevision;

  String _requireSpeechSession([VrmSpeechMode? mode]) {
    final sessionId = _activeSpeechSessionId;
    if (sessionId == null) {
      throw StateError('Call beginSpeech() before appending or finishing.');
    }
    if (_speechIsFinishing) {
      throw StateError('The active speech timeline is already finishing.');
    }
    if (mode != null && _activeSpeechMode != mode) {
      throw StateError(
        'The active speech timeline accepts ${_activeSpeechMode?.name} frames, '
        'not ${mode.name} frames.',
      );
    }
    return sessionId;
  }

  void _abandonSpeechSession([String? expectedSessionId]) {
    if (expectedSessionId != null &&
        expectedSessionId != _activeSpeechSessionId) {
      return;
    }
    _activeSpeechSessionId = null;
    _activeSpeechMode = null;
    _speechIsFinishing = false;
  }

  void _clearDirectSpeechInputs() {
    _bridge
      ..clearLatestCommand('lipSyncAmplitude')
      ..clearLatestCommand('directViseme');
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

  // --- LookAt, Touch & Auto-Blink ---

  /// Toggles random auto-blinking generator.
  /// Включает или отключает случайные движения зрачков (саккады).
  void setAutoSaccades({bool enabled = true}) {
    _sendCommand('setAutoSaccades', {'enabled': enabled});
  }

  void setAutoBlink(bool enabled) {
    _sendCommand('setAutoBlink', {'enabled': enabled});
  }

  /// Sets 3D LookAt target point on screen.
  void setLookAtTarget(Offset screenPosition) {
    if (!screenPosition.dx.isFinite || !screenPosition.dy.isFinite) {
      throw ArgumentError.value(
        screenPosition,
        'screenPosition',
        'Coordinates must be finite.',
      );
    }
    _bridge.sendLatestCommand(
      channel: 'lookAtTarget',
      action: 'setLookAtTarget',
      payload: {'x': screenPosition.dx, 'y': screenPosition.dy},
    );
  }

  /// Configures LookAt dead zone X range (default 0.35) and gaze hold duration (default 1.8s).
  void setLookAtConfig({double? deadZoneX, Duration? holdDuration}) {
    _sendCommand('setLookAtConfig', {
      'deadZoneX': ?deadZoneX,
      if (holdDuration != null)
        'holdDurationSec': holdDuration.inMilliseconds / 1000.0,
    });
  }

  // --- Camera & Scene ---

  /// Selects constrained avatar controls or unrestricted orbit controls.
  Future<void> setCameraMode(VrmCameraMode mode) {
    return _bridge.sendCommand('setCameraMode', {
      'mode': switch (mode) {
        VrmCameraMode.constrained => 'constrained',
        VrmCameraMode.free => 'free',
      },
    });
  }

  /// Retrieves the current serializable pan and zoom state of the avatar.
  Future<VrmTransform> getTransform() async {
    final result = await _bridge.requestCommand('getTransform');
    if (result is! Map<String, dynamic>) {
      throw const FormatException('VRM transform response must be an object.');
    }
    final transform = VrmTransform.fromMap(result);
    _lastKnownCameraTransform = transform;
    return transform;
  }

  /// Restores a previously saved pan and zoom state of the avatar.
  Future<void> setTransform(VrmTransform transform) async {
    await _bridge.sendCommand('setTransform', {'transform': transform.toMap()});
    _lastKnownCameraTransform = transform;
    _cameraTransformRevision += 1;
  }

  /// Clears custom pan/zoom and frames the current avatar again.
  Future<void> resetCamera({
    Duration duration = const Duration(milliseconds: 500),
  }) async {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'Must not be negative.');
    }
    await _bridge.sendCommand('resetCamera', {
      'durationMs': duration.inMilliseconds,
    });
    _lastKnownCameraTransform = null;
    _cameraTransformRevision += 1;
  }

  String _colorToHex(Color color) {
    final hex = color.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${hex.substring(2)}';
  }

  /// Configures scene lighting intensity and colors.
  void setLighting({
    Color? ambientColor,
    double? ambientIntensity,
    Color? directionalColor,
    double? directionalIntensity,
  }) {
    _sendCommand('setLighting', {
      if (ambientColor != null) 'ambientColor': _colorToHex(ambientColor),
      'ambientIntensity': ?ambientIntensity,
      if (directionalColor != null)
        'directionalColor': _colorToHex(directionalColor),
      'directionalIntensity': ?directionalIntensity,
    });
  }

  /// Intelligently tints the model's rim and ambient lighting to match the environment/background color.
  /// [color] is the dominant color of the background.
  /// [intensity] (0.0 to 1.0) controls how strongly the ambient light mixes with the background color (default 0.5).
  void setEnvironmentColor(Color color, {double intensity = 0.5}) {
    _sendCommand('setEnvironmentColor', {
      'color': _colorToHex(color),
      'intensity': intensity.clamp(0.0, 1.0),
    });
  }

  /// Enables or disables real-time shadow mapping in WebGL.
  /// Shadows improve visual quality significantly but increase GPU usage.
  void setShadows(bool enabled) {
    _sendCommand('setShadows', {'enabled': enabled});
  }

  /// Adjusts the physics of the model's soft bodies (Spring Bones) like hair and clothes.
  /// [stiffness] - Multiplier for rigidity (1.0 = normal, 0.0 = completely loose).
  /// [gravity] - Multiplier for gravity pull (1.0 = normal, >1.0 = heavy, 0.0 = zero gravity).
  /// [drag] - Multiplier for air resistance/drag.
  void setPhysics({
    double stiffness = 1.0,
    double gravity = 1.0,
    double drag = 1.0,
  }) {
    _sendCommand('setPhysics', {
      'stiffness': stiffness,
      'gravity': gravity,
      'drag': drag,
    });
  }

  /// Enables and configures wind simulation affecting the model's physics.
  void setWind({
    VrmWindType type = VrmWindType.none,
    VrmWindDirection direction = VrmWindDirection.right,
  }) {
    _sendCommand('setWind', {'type': type.name, 'direction': direction.name});
  }

  /// Smoothly fades out the wind effect over a few seconds.
  void stopWind() {
    _sendCommand('stopWind');
  }

  /// Configures the scene background with a color or an optional image.
  ///
  /// Asset images are copied into a WebView-owned Blob before the temporary
  /// local-server URL is released. Public [imageUrl] values are used directly.
  /// Provide at most one image source.
  Future<void> setBackground({
    required Color color,
    bool transparent = false,
    String? imageAssetPath,
    String? imageUrl,
  }) async {
    if (imageAssetPath != null && imageUrl != null) {
      throw ArgumentError(
        'Provide either imageAssetPath or imageUrl, not both.',
      );
    }

    final payload = <String, dynamic>{
      'color': _colorToHex(color),
      'transparent': transparent,
    };
    if (imageAssetPath != null) {
      await _sendHostedResourceCommand(
        expose: (host) => host.exposeAsset(imageAssetPath),
        action: 'setBackground',
        fileName: p.basename(imageAssetPath),
        urlField: 'imageUrl',
        payload: {...payload, 'hostedImage': true},
      );
      return;
    }

    await _bridge.sendCommand('setBackground', {
      ...payload,
      'imageUrl': ?imageUrl,
      'hostedImage': false,
    });
  }

  /// Configures the scene background from a local image file.
  Future<void> setBackgroundFromFile(
    io.File file, {
    required Color color,
    bool transparent = false,
  }) {
    return _sendHostedResourceCommand(
      expose: (host) => host.exposeFile(file),
      action: 'setBackground',
      fileName: p.basename(file.path),
      urlField: 'imageUrl',
      payload: {
        'color': _colorToHex(color),
        'transparent': transparent,
        'hostedImage': true,
      },
    );
  }

  /// Configures the scene background from authenticated image bytes.
  Future<void> setBackgroundFromBytes(
    Uint8List bytes, {
    required String fileName,
    required Color color,
    bool transparent = false,
  }) {
    if (fileName.trim().isEmpty) {
      throw ArgumentError.value(fileName, 'fileName', 'Must not be empty.');
    }
    return _sendHostedResourceCommand(
      expose: (host) => host.exposeBytes(bytes, fileName: fileName),
      action: 'setBackground',
      fileName: fileName,
      urlField: 'imageUrl',
      payload: {
        'color': _colorToHex(color),
        'transparent': transparent,
        'hostedImage': true,
      },
    );
  }

  /// Sets the pixel ratio for WebGL rendering.
  @Deprecated('Use setGraphicsSettings(pixelRatio: value) instead')
  Future<void> setRenderQuality(double pixelRatio) {
    return setGraphicsSettings(pixelRatio: pixelRatio);
  }

  /// Applies a curated renderer profile.
  Future<void> setGraphicsPreset(VrmGraphicsPreset preset) {
    return _bridge.sendCommand('setGraphicsPreset', {'preset': preset.name});
  }

  /// Enables or configures automatic render-resolution adaptation.
  Future<void> setAdaptiveQuality(VrmAdaptiveQualitySettings settings) {
    return _bridge.sendCommand('setAdaptiveQuality', {
      'settings': settings.toJson(),
    });
  }

  /// Returns the latest renderer workload measurement.
  Future<VrmPerformanceSnapshot> getPerformanceSnapshot() async {
    final result = await _bridge.requestCommand('getPerformanceSnapshot');
    return VrmPerformanceSnapshot.fromJson(result);
  }

  /// Sets individual graphics and performance controls.
  ///
  /// [fpsCap] accepts 0 for display-vsync or 1–120. [pixelRatio] is clamped
  /// by the runtime to 0.5–3.0 as a protection against accidental GPU loads.
  Future<void> setGraphicsSettings({
    double? pixelRatio,
    bool? antialias,
    bool? enablePhysics,
    int? fpsCap,
  }) {
    final settings = <String, dynamic>{};
    if (pixelRatio != null) settings['pixelRatio'] = pixelRatio;
    if (antialias != null) settings['antialias'] = antialias;
    if (enablePhysics != null) settings['enablePhysics'] = enablePhysics;
    if (fpsCap != null) settings['fpsCap'] = fpsCap;

    return _bridge.sendCommand('setGraphicsSettings', {'settings': settings});
  }
  // --- Event Stream Getters ---

  Stream<VrmModelLoadedEvent> get onModelLoaded => _bridge.eventStream
      .where((e) => e is VrmModelLoadedEvent)
      .cast<VrmModelLoadedEvent>();

  /// Emitted repeatedly while a model is downloading, with [percent] 0–100.
  /// Useful for showing a progress indicator during model load.
  Stream<VrmModelLoadProgressEvent> get onModelLoadProgress => _bridge
      .eventStream
      .where((e) => e is VrmModelLoadProgressEvent)
      .cast<VrmModelLoadProgressEvent>();

  Stream<VrmModelReportEvent> get onModelReport => _bridge.eventStream
      .where((event) => event is VrmModelReportEvent)
      .cast<VrmModelReportEvent>();

  /// Model complexity assessments produced by the attached [VrmView].
  Stream<VrmModelAssessmentEvent> get onModelAssessment => _bridge.eventStream
      .where((event) => event is VrmModelAssessmentEvent)
      .cast<VrmModelAssessmentEvent>();

  Stream<VrmModelUnloadedEvent> get onModelUnloaded => _bridge.eventStream
      .where((e) => e is VrmModelUnloadedEvent)
      .cast<VrmModelUnloadedEvent>();

  Stream<VrmAnimationStartedEvent> get onAnimationStarted => _bridge.eventStream
      .where((e) => e is VrmAnimationStartedEvent)
      .cast<VrmAnimationStartedEvent>();

  Stream<VrmAnimationFinishedEvent> get onAnimationFinished => _bridge
      .eventStream
      .where((e) => e is VrmAnimationFinishedEvent)
      .cast<VrmAnimationFinishedEvent>();

  Stream<VrmExpressionChangedEvent> get onExpressionChanged => _bridge
      .eventStream
      .where((e) => e is VrmExpressionChangedEvent)
      .cast<VrmExpressionChangedEvent>();

  Stream<VrmSpeechFinishedEvent> get onSpeechFinished => _bridge.eventStream
      .where((e) => e is VrmSpeechFinishedEvent)
      .cast<VrmSpeechFinishedEvent>();

  Stream<VrmErrorEvent> get onError => _bridge.eventStream
      .where((e) => e is VrmErrorEvent)
      .cast<VrmErrorEvent>();

  Stream<VrmStateChangedEvent> get onStateChanged => _bridge.eventStream
      .where((e) => e is VrmStateChangedEvent)
      .cast<VrmStateChangedEvent>();

  Stream<VrmPerformanceEvent> get onPerformance => _bridge.eventStream
      .where((event) => event is VrmPerformanceEvent)
      .cast<VrmPerformanceEvent>();

  Stream<VrmWebGlContextEvent> get onWebGlContextChanged => _bridge.eventStream
      .where((event) => event is VrmWebGlContextEvent)
      .cast<VrmWebGlContextEvent>();

  Stream<VrmCameraChangedEvent> get onCameraChanged => _bridge.eventStream
      .where((e) => e is VrmCameraChangedEvent)
      .cast<VrmCameraChangedEvent>();

  Stream<VrmTapEvent> get onTap =>
      _bridge.eventStream.where((e) => e is VrmTapEvent).cast<VrmTapEvent>();
}
