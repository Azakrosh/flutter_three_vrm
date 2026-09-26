part of 'vrm_runtime.dart';

/// Primary controller for loading, animating, and interacting with one VRM model.
class VrmController {
  final _VrmBridge _bridge = _VrmBridge();
  late final VrmHostResourceMonitor _hostResourceMonitor;
  late final VrmPlatformThermalMonitor _platformThermalMonitor;
  final VrmModelSessionState _modelState = VrmModelSessionState();
  final VrmSpeechSessionState _speechState = VrmSpeechSessionState();
  late final StreamSubscription<VrmEvent> _stateSubscription;
  bool _isDisposed = false;
  int _animationPlaybackSequence = 0;
  VrmTransform? _lastKnownCameraTransform;
  int _cameraTransformRevision = 0;
  VrmContentHost? _contentHost;
  int _hostResourceMonitoringClients = 0;

  VrmController() {
    _platformThermalMonitor = VrmPlatformThermalMonitor(
      onStatusChanged: _publishThermalStatus,
    );
    _hostResourceMonitor = VrmHostResourceMonitor(
      thermalStatusReader: () => _platformThermalMonitor.status,
    );
    _stateSubscription = _bridge.eventStream.listen((event) {
      switch (event) {
        case VrmModelLoadedEvent():
          _modelState.setLoaded(true);
        case VrmModelUnloadedEvent():
          _modelState.setLoaded(false);
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
  bool get isLoadingModel => _modelState.isLoading;

  /// Whether the currently attached runtime contains an avatar.
  bool get isModelLoaded => _modelState.isLoaded;

  /// Whether the JavaScript runtime completed protocol initialization.
  bool get isRuntimeReady => _bridge.isRuntimeReady;

  /// Whether a speech timeline is active or waiting for its declared end.
  bool get isSpeechActive => _speechState.hasActiveSession;

  /// Input type accepted by the current speech timeline.
  VrmSpeechMode? get speechMode => _speechState.activeMode;

  /// Captures current resource diagnostics for the Flutter host process.
  ///
  /// RSS accounting is platform dependent and includes the whole application,
  /// not only the avatar runtime. Use it to compare trends between equivalent
  /// soak runs rather than as an absolute memory limit.
  VrmHostResourceSnapshot captureHostResourceSnapshot() {
    _ensureNotDisposed();
    return _hostResourceMonitor.capture();
  }

  void _recordHostMemoryPressure() {
    if (_isDisposed) return;
    _bridge.publishEvent(
      VrmHostMemoryPressureEvent(
        snapshot: _hostResourceMonitor.recordMemoryPressure(),
      ),
    );
  }

  void _attachHostResourceMonitoring() {
    _ensureNotDisposed();
    _hostResourceMonitoringClients += 1;
    if (_hostResourceMonitoringClients == 1) {
      _platformThermalMonitor.start();
    }
  }

  void _detachHostResourceMonitoring() {
    if (_hostResourceMonitoringClients == 0) return;
    _hostResourceMonitoringClients -= 1;
    if (_hostResourceMonitoringClients == 0) {
      unawaited(_platformThermalMonitor.stop());
    }
  }

  void _publishThermalStatus(VrmThermalStatus status) {
    if (_isDisposed) return;
    _bridge.publishEvent(
      VrmHostThermalStatusChangedEvent(
        snapshot: _hostResourceMonitor.capture(),
      ),
    );
  }

  void _attachContentHost(VrmContentHost contentHost) {
    _contentHost = contentHost;
  }

  void _detachContentHost(VrmContentHost contentHost) {
    if (identical(_contentHost, contentHost)) {
      _contentHost = null;
      _modelState.invalidateRuntime();
    }
  }

  VrmContentHost get _requiredContentHost {
    _ensureNotDisposed();
    final contentHost = _contentHost;
    if (contentHost == null || !contentHost.isStarted) {
      throw StateError(
        'VrmView is not ready. Wait for VrmView.onCreated before loading '
        'assets or local files.',
      );
    }
    return contentHost;
  }

  void _sendCommand(
    VrmProtocolCommand action, [
    Map<String, dynamic>? payload,
  ]) {
    _ensureNotDisposed();
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
    required VrmProtocolCommand action,
    required String fileName,
    String urlField = 'url',
    Map<String, dynamic>? payload,
  }) async {
    _ensureNotDisposed();
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
    final loadGeneration = _modelState.beginLoad();
    try {
      await _sendHostedResourceCommand(
        expose: (host) => host.exposeAsset('$folderPath$fileName'),
        action: VrmProtocolCommand.loadModelFromUrl,
        fileName: fileName,
      );
      _modelState.completeLoad(loadGeneration);
    } finally {
      _modelState.finishLoad(loadGeneration);
    }
  }

  /// Loads a VRM model from a local file.
  Future<void> loadModelFromFile(io.File file) async {
    final loadGeneration = _modelState.beginLoad();
    try {
      await _sendHostedResourceCommand(
        expose: (host) => host.exposeFile(file),
        action: VrmProtocolCommand.loadModelFromUrl,
        fileName: p.basename(file.path),
      );
      _modelState.completeLoad(loadGeneration);
    } finally {
      _modelState.finishLoad(loadGeneration);
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
    final loadGeneration = _modelState.beginLoad();
    try {
      await _sendHostedResourceCommand(
        expose: (host) => host.exposeBytes(bytes, fileName: fileName),
        action: VrmProtocolCommand.loadModelFromUrl,
        fileName: fileName,
      );
      _modelState.completeLoad(loadGeneration);
    } finally {
      _modelState.finishLoad(loadGeneration);
    }
  }

  /// Loads a public URL directly in WebView.
  ///
  /// Prefer [loadModelFromFile] or [loadModelFromBytes] for authenticated URLs.
  Future<void> loadModelFromUrl(String url) async {
    final loadGeneration = _modelState.beginLoad();
    try {
      await _bridge.sendCommand(VrmProtocolCommand.loadModelFromUrl, {
        'url': url,
        'fileName': Uri.parse(url).pathSegments.lastOrNull ?? 'avatar.vrm',
      });
      _modelState.completeLoad(loadGeneration);
    } finally {
      _modelState.finishLoad(loadGeneration);
    }
  }

  /// Cancels the active model transfer or parse operation.
  ///
  /// The previously displayed avatar remains active. The canceled load Future
  /// completes with `VrmRuntimeException(code: 'canceled')`.
  Future<void> cancelModelLoad() async {
    _modelState.cancelLoad();
    await _bridge.sendCommand(VrmProtocolCommand.cancelModelLoad);
  }

  /// Returns the diagnostic report for the current avatar.
  Future<VrmModelReport> getModelReport() async {
    final result = await _bridge.requestCommand(
      VrmProtocolCommand.getModelReport,
    );
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
    final result = await _bridge.requestCommand(
      VrmProtocolCommand.getRuntimeHealth,
    );
    final health = VrmRuntimeHealth.fromJson(result);
    _modelState.setLoaded(health.modelLoaded);
    return health;
  }

  /// Reloads the embedded runtime. [VrmView.onCreated] runs again afterwards.
  Future<void> reloadRuntime() async {
    _ensureNotDisposed();
    _invalidateTransientRuntimeState();
    await _bridge.reloadRuntime();
  }

  void _markRuntimeUnavailable(Object error) {
    _invalidateTransientRuntimeState();
    _bridge.publishEvent(VrmRuntimeUnavailableEvent(reason: error.toString()));
    _bridge.markRuntimeUnavailable(error);
  }

  void _invalidateTransientRuntimeState() {
    _modelState.invalidateRuntime();
    _speechState.invalidateRuntime();
    _clearDirectSpeechInputs();
  }

  void _publishModelAssessment(VrmModelAssessment assessment) {
    _bridge.publishEvent(VrmModelAssessmentEvent(assessment: assessment));
  }

  /// Unloads the model and releases its GPU resources.
  Future<void> unloadModel() async {
    _modelState.cancelLoad();
    _abandonSpeechSession();
    _clearDirectSpeechInputs();
    await _bridge.sendCommand(VrmProtocolCommand.unloadModel, {
      'speechRevision': _nextSpeechRevision(),
    });
    _modelState.setLoaded(false);
    _lastKnownCameraTransform = null;
    _cameraTransformRevision += 1;
  }

  /// Disposes this controller and its event streams.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _hostResourceMonitoringClients = 0;
    _invalidateTransientRuntimeState();
    await _platformThermalMonitor.stop();
    await _stateSubscription.cancel();
    await _bridge.dispose();
  }

  Future<void> _setRenderingPaused(bool paused) => _bridge.sendCommand(
    paused
        ? VrmProtocolCommand.pauseRendering
        : VrmProtocolCommand.resumeRendering,
  );

  // --- Animation control ---

  /// Plays a VRMA animation from Flutter assets.
  Future<VrmAnimationPlayback> playAnimation(
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
  Future<VrmAnimationPlayback> playAnimationFromFile(
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
  Future<VrmAnimationPlayback> playAnimationFromBytes(
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
  Future<VrmAnimationPlayback> playAnimationFromFileBundle(
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
  Future<VrmAnimationPlayback> playAnimationFromBytesBundle(
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

  Future<VrmAnimationPlayback> _playHostedAnimation({
    required Uri Function(VrmContentHost host) expose,
    required String fileName,
    required bool loop,
    required double speed,
    required double fadeDuration,
    required VrmRootMotion rootMotion,
    required String? clipName,
  }) {
    _validateAnimationPlayback(
      fileName: fileName,
      speed: speed,
      fadeDuration: fadeDuration,
      clipName: clipName,
    );
    final options = VrmAnimationOptions(
      loop: loop,
      speed: speed,
      fadeDuration: fadeDuration,
      rootMotion: rootMotion,
      clipName: clipName,
    );
    final playback = _createAnimationPlayback();
    return _sendHostedResourceCommand(
      expose: expose,
      action: VrmProtocolCommand.playAnimationFromUrl,
      fileName: fileName,
      payload: {
        'options': {...options.toJson(), 'playbackId': playback.id},
      },
    ).then((_) => playback);
  }

  VrmAnimationPlayback _createAnimationPlayback() {
    final id =
        'animation-${DateTime.now().microsecondsSinceEpoch}-'
        '${_animationPlaybackSequence++}';
    return VrmAnimationPlayback(id: id);
  }

  /// Plays a VRMA or glTF animation from a public URL.
  Future<VrmAnimationPlayback> playAnimationFromUrl(
    String url, {
    bool loop = true,
    double speed = 1,
    double fadeDuration = 0.5,
    VrmRootMotion rootMotion = VrmRootMotion.inPlace,
    String? clipName,
  }) {
    _requireNonEmpty(url, 'url');
    _validateAnimationPlayback(
      fileName: Uri.parse(url).pathSegments.lastOrNull ?? 'animation.vrma',
      speed: speed,
      fadeDuration: fadeDuration,
      clipName: clipName,
    );
    final options = VrmAnimationOptions(
      loop: loop,
      speed: speed,
      fadeDuration: fadeDuration,
      rootMotion: rootMotion,
      clipName: clipName,
    );
    final playback = _createAnimationPlayback();
    return _bridge
        .sendCommand(VrmProtocolCommand.playAnimationFromUrl, {
          'url': url,
          'fileName':
              Uri.parse(url).pathSegments.lastOrNull ?? 'animation.vrma',
          'options': {...options.toJson(), 'playbackId': playback.id},
        })
        .then((_) => playback);
  }

  /// Pauses animation clip playback.
  Future<void> pauseAnimation() async {
    await _bridge.sendCommand(VrmProtocolCommand.pauseAnimation);
  }

  /// Resumes animation clip playback.
  Future<void> resumeAnimation({double speed = 1.0}) {
    _requirePositiveFinite(speed, 'speed');
    return _bridge.sendCommand(VrmProtocolCommand.resumeAnimation, {
      'speed': speed,
    });
  }

  /// Cancels an animation transfer without stopping the current action.
  Future<void> cancelAnimationLoad() {
    return _bridge.sendCommand(VrmProtocolCommand.cancelAnimationLoad);
  }

  /// Stops the current action and cancels an in-flight animation load.
  Future<void> stopAnimation({double fadeDuration = 0.5}) {
    _requireNonNegativeFinite(fadeDuration, 'fadeDuration');
    return _bridge.sendCommand(VrmProtocolCommand.stopAnimation, {
      'fadeDuration': fadeDuration,
    });
  }

  /// Sets playback speed multiplier for current animation.
  Future<void> setAnimationSpeed(double speed) {
    _requirePositiveFinite(speed, 'speed');
    return _bridge.sendCommand(VrmProtocolCommand.setAnimationSpeed, {
      'speed': speed,
    });
  }

  // --- Humanoid pose ---

  /// Returns the model's normalized humanoid pose.
  ///
  /// Bone transforms are relative to the normalized rest pose defined by
  /// `@pixiv/three-vrm`, so the result can be stored and applied to another
  /// compatible VRM avatar.
  Future<VrmPose> getPose() async {
    final result = await _bridge.requestCommand(VrmProtocolCommand.getPose);
    return VrmPose.fromJson(result);
  }

  /// Applies a normalized humanoid [pose].
  ///
  /// Pose and clip playback share one mixer, so switching from either source
  /// crossfades without snapping through the rest pose.
  Future<void> setPose(VrmPose pose, {double fadeDuration = 0.5}) {
    _requireNonNegativeFinite(fadeDuration, 'fadeDuration');
    return _bridge.sendCommand(VrmProtocolCommand.setPose, {
      'pose': pose.toJson(),
      'fadeDuration': fadeDuration,
    });
  }

  /// Smoothly restores all normalized humanoid bones to their rest transforms.
  Future<void> resetPose({double fadeDuration = 0.5}) {
    _requireNonNegativeFinite(fadeDuration, 'fadeDuration');
    return _bridge.sendCommand(VrmProtocolCommand.resetPose, {
      'fadeDuration': fadeDuration,
    });
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
    _validateMood(mood);

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
    _requireUnitInterval(weight, 'weight');
    _requireNonNegativeDuration(duration, 'duration');
    final resolvedLayer = layer ?? expression.defaultLayer;
    int? speechRevision;
    if (resolvedLayer == ExpressionLayer.mouth) {
      _abandonSpeechSession();
      _clearDirectSpeechInputs();
      speechRevision = _nextSpeechRevision();
    }
    _sendCommand(VrmProtocolCommand.setExpression, {
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
    _sendCommand(VrmProtocolCommand.clearExpressionLayer, {
      'layer': layer.name,
      'speechRevision': ?speechRevision,
    });
  }

  /// Clears all active facial expressions, blendshapes, and visemes.
  void clearAllExpressions() {
    _abandonSpeechSession();
    _clearDirectSpeechInputs();
    _sendCommand(VrmProtocolCommand.clearAllExpressions, {
      'speechRevision': _nextSpeechRevision(),
    });
  }

  /// Sets a custom blendshape key by name and weight (0.0 to 1.0).
  void setCustomBlendShape(String name, double weight) {
    _requireNonEmpty(name, 'name');
    _requireUnitInterval(weight, 'weight');
    _sendCommand(VrmProtocolCommand.setCustomBlendShape, {
      'name': name,
      'weight': weight,
    });
  }

  // --- Lip Sync (ElevenLabs & Amplitude) ---

  /// Sets real-time audio volume amplitude (0.0 to 1.0) for smooth speech mouth opening.
  void setLipSyncAmplitude(double amplitude) {
    _ensureNotDisposed();
    if (!amplitude.isFinite) {
      throw ArgumentError.value(amplitude, 'amplitude', 'Must be finite.');
    }
    _abandonSpeechSession();
    final speechRevision = _nextSpeechRevision();
    _bridge
      ..clearLatestCommand('directViseme')
      ..sendLatestCommand(
        channel: 'lipSyncAmplitude',
        action: VrmProtocolCommand.setLipSyncAmplitude,
        payload: {
          'amplitude': amplitude.clamp(0.0, 1.0),
          'speechRevision': speechRevision,
        },
      );
  }

  /// Sets the latest direct viseme state without queueing stale bridge updates.
  void setViseme(VrmViseme viseme, {double weight = 1.0}) {
    _ensureNotDisposed();
    if (!weight.isFinite) {
      throw ArgumentError.value(weight, 'weight', 'Must be finite.');
    }
    _abandonSpeechSession();
    final speechRevision = _nextSpeechRevision();
    _bridge
      ..clearLatestCommand('lipSyncAmplitude')
      ..sendLatestCommand(
        channel: 'directViseme',
        action: VrmProtocolCommand.setViseme,
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
    _speechState.markFinishing(sessionId);
    final timelineOriginEpochMs = DateTime.now().millisecondsSinceEpoch;
    try {
      await _bridge.sendCommand(VrmProtocolCommand.enqueueSpeechVisemes, {
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
    _speechState.markFinishing(sessionId);
    final timelineOriginEpochMs = DateTime.now().millisecondsSinceEpoch;
    try {
      await _bridge.sendCommand(VrmProtocolCommand.enqueueSpeechAmplitudes, {
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
  Future<VrmSpeechSession> beginSpeech({
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
      await _bridge.sendCommand(VrmProtocolCommand.beginSpeech, {
        'sessionId': sessionId,
        'mode': mode.name,
        'timelineOriginEpochMs': timelineOriginEpochMs,
        'speechRevision': speechRevision,
      });
      return VrmSpeechSession._(this, sessionId, mode);
    } on Object {
      _abandonSpeechSession(sessionId);
      rethrow;
    }
  }

  Future<bool> _appendSpeechVisemes(
    String sessionId,
    List<VisemeFrame> frames,
  ) async {
    if (!_canUseSpeechSession(sessionId)) return false;
    _validateVisemeFrames(frames);
    if (frames.isEmpty) return true;
    final sortedFrames = List<VisemeFrame>.from(frames)..sort();
    await _bridge.sendCommand(VrmProtocolCommand.appendSpeechVisemes, {
      'sessionId': sessionId,
      'frames': sortedFrames.map((f) => f.toJson()).toList(),
    });
    return true;
  }

  Future<bool> _appendSpeechAmplitudes(
    String sessionId,
    List<AmplitudeFrame> frames,
  ) async {
    if (!_canUseSpeechSession(sessionId)) return false;
    _validateAmplitudeFrames(frames);
    if (frames.isEmpty) return true;
    final sortedFrames = List<AmplitudeFrame>.from(frames)..sort();
    await _bridge.sendCommand(VrmProtocolCommand.appendSpeechAmplitudes, {
      'sessionId': sessionId,
      'frames': sortedFrames.map((frame) => frame.toJson()).toList(),
    });
    return true;
  }

  Future<bool> _finishSpeech(String sessionId, Duration audioDuration) async {
    if (!_canUseSpeechSession(sessionId)) return false;
    if (audioDuration.isNegative) {
      throw ArgumentError.value(
        audioDuration,
        'audioDuration',
        'Must not be negative.',
      );
    }
    _speechState.markFinishing(sessionId);
    try {
      await _bridge.sendCommand(VrmProtocolCommand.finishSpeech, {
        'sessionId': sessionId,
        'audioDurationMs': audioDuration.inMilliseconds,
      });
    } on Object {
      _speechState.clearFinishing(sessionId);
      rethrow;
    }
    return true;
  }

  /// Fully stops the active speech timeline and closes the mouth layer.
  Future<void> cancelSpeech() {
    _clearDirectSpeechInputs();
    final sessionId = _speechState.activeSessionId;
    _abandonSpeechSession();
    return _bridge.sendCommand(VrmProtocolCommand.cancelSpeech, {
      'sessionId': ?sessionId,
      'speechRevision': _nextSpeechRevision(),
    });
  }

  Future<bool> _cancelSpeechSession(String sessionId) async {
    if (!_speechState.isActive(sessionId)) return false;
    _clearDirectSpeechInputs();
    _abandonSpeechSession(sessionId);
    await _bridge.sendCommand(VrmProtocolCommand.cancelSpeech, {
      'sessionId': sessionId,
      'speechRevision': _nextSpeechRevision(),
    });
    return true;
  }

  String _activateSpeechSession(VrmSpeechMode mode) {
    return _speechState.activate(mode);
  }

  int _nextSpeechRevision() => _speechState.nextInputRevision();

  bool _canUseSpeechSession(String sessionId) =>
      _speechState.canAppend(sessionId);

  void _abandonSpeechSession([String? expectedSessionId]) {
    _speechState.abandon(expectedSessionId);
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

  // --- Programmatic gaze & Auto-Blink ---

  /// Toggles random auto-blinking generator.
  /// Включает или отключает случайные движения зрачков (саккады).
  void setAutoSaccades({bool enabled = true}) {
    _sendCommand(VrmProtocolCommand.setAutoSaccades, {'enabled': enabled});
  }

  void setAutoBlink(bool enabled) {
    _sendCommand(VrmProtocolCommand.setAutoBlink, {'enabled': enabled});
  }

  /// Directs the avatar's eyes to an explicit target; taps do not change gaze.
  void setLookAtTarget(Offset screenPosition) {
    _ensureNotDisposed();
    if (!screenPosition.dx.isFinite || !screenPosition.dy.isFinite) {
      throw ArgumentError.value(
        screenPosition,
        'screenPosition',
        'Coordinates must be finite.',
      );
    }
    _bridge.sendLatestCommand(
      channel: 'lookAtTarget',
      action: VrmProtocolCommand.setLookAtTarget,
      payload: {'x': screenPosition.dx, 'y': screenPosition.dy},
    );
  }

  /// Configures how long an explicit gaze target is held (default 1 second).
  void setLookAtConfig({Duration? holdDuration}) {
    if (holdDuration != null) {
      _requireNonNegativeDuration(holdDuration, 'holdDuration');
    }
    _sendCommand(VrmProtocolCommand.setLookAtConfig, {
      if (holdDuration != null)
        'holdDurationSec': holdDuration.inMilliseconds / 1000.0,
    });
  }

  // --- Camera & Scene ---

  /// Selects constrained avatar controls or unrestricted orbit controls.
  Future<void> setCameraMode(VrmCameraMode mode) {
    return _bridge.sendCommand(VrmProtocolCommand.setCameraMode, {
      'mode': switch (mode) {
        VrmCameraMode.constrained => 'constrained',
        VrmCameraMode.free => 'free',
      },
    });
  }

  /// Retrieves the current serializable pan and zoom state of the avatar.
  Future<VrmTransform> getTransform() async {
    final result = await _bridge.requestCommand(
      VrmProtocolCommand.getTransform,
    );
    if (result is! Map<String, dynamic>) {
      throw const FormatException('VRM transform response must be an object.');
    }
    final transform = VrmTransform.fromMap(result);
    _lastKnownCameraTransform = transform;
    return transform;
  }

  /// Restores a previously saved pan and zoom state of the avatar.
  Future<void> setTransform(VrmTransform transform) async {
    await _bridge.sendCommand(VrmProtocolCommand.setTransform, {
      'transform': transform.toMap(),
    });
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
    await _bridge.sendCommand(VrmProtocolCommand.resetCamera, {
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
    if (ambientIntensity != null) {
      _requireNonNegativeFinite(ambientIntensity, 'ambientIntensity');
    }
    if (directionalIntensity != null) {
      _requireNonNegativeFinite(directionalIntensity, 'directionalIntensity');
    }
    _sendCommand(VrmProtocolCommand.setLighting, {
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
    _requireUnitInterval(intensity, 'intensity');
    _sendCommand(VrmProtocolCommand.setEnvironmentColor, {
      'color': _colorToHex(color),
      'intensity': intensity,
    });
  }

  /// Enables or disables real-time shadow mapping in WebGL.
  /// Shadows improve visual quality significantly but increase GPU usage.
  void setShadows(bool enabled) {
    _sendCommand(VrmProtocolCommand.setShadows, {'enabled': enabled});
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
    _validatePhysics(stiffness: stiffness, gravity: gravity, drag: drag);
    _sendCommand(VrmProtocolCommand.setPhysics, {
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
    _sendCommand(VrmProtocolCommand.setWind, {
      'type': type.name,
      'direction': direction.name,
    });
  }

  /// Smoothly fades out the wind effect over a few seconds.
  void stopWind() {
    _sendCommand(VrmProtocolCommand.stopWind);
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
        action: VrmProtocolCommand.setBackground,
        fileName: p.basename(imageAssetPath),
        urlField: 'imageUrl',
        payload: {...payload, 'hostedImage': true},
      );
      return;
    }

    await _bridge.sendCommand(VrmProtocolCommand.setBackground, {
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
      action: VrmProtocolCommand.setBackground,
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
      action: VrmProtocolCommand.setBackground,
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
    return _bridge.sendCommand(VrmProtocolCommand.setGraphicsPreset, {
      'preset': preset.name,
    });
  }

  /// Enables or configures automatic render-resolution adaptation.
  Future<void> setAdaptiveQuality(VrmAdaptiveQualitySettings settings) {
    return _bridge.sendCommand(VrmProtocolCommand.setAdaptiveQuality, {
      'settings': settings.toJson(),
    });
  }

  /// Returns the latest renderer workload measurement.
  Future<VrmPerformanceSnapshot> getPerformanceSnapshot() async {
    final result = await _bridge.requestCommand(
      VrmProtocolCommand.getPerformanceSnapshot,
    );
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
    if (pixelRatio != null) {
      _requirePositiveFinite(pixelRatio, 'pixelRatio');
    }
    if (fpsCap != null && (fpsCap < 0 || fpsCap > 120)) {
      throw ArgumentError.value(
        fpsCap,
        'fpsCap',
        'Must be zero or between 1 and 120.',
      );
    }
    final settings = <String, dynamic>{};
    if (pixelRatio != null) settings['pixelRatio'] = pixelRatio;
    if (antialias != null) settings['antialias'] = antialias;
    if (enablePhysics != null) settings['enablePhysics'] = enablePhysics;
    if (fpsCap != null) settings['fpsCap'] = fpsCap;

    return _bridge.sendCommand(VrmProtocolCommand.setGraphicsSettings, {
      'settings': settings,
    });
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

  /// Emitted when the current WebView document is lost or starts reloading.
  Stream<VrmRuntimeUnavailableEvent> get onRuntimeUnavailable => _bridge
      .eventStream
      .where((event) => event is VrmRuntimeUnavailableEvent)
      .cast<VrmRuntimeUnavailableEvent>();

  /// Low-memory notifications observed by the attached [VrmView].
  Stream<VrmHostMemoryPressureEvent> get onHostMemoryPressure => _bridge
      .eventStream
      .where((event) => event is VrmHostMemoryPressureEvent)
      .cast<VrmHostMemoryPressureEvent>();

  /// Android thermal-state changes; unavailable on unsupported platforms.
  Stream<VrmHostThermalStatusChangedEvent> get onHostThermalStatusChanged =>
      _bridge.eventStream
          .where((event) => event is VrmHostThermalStatusChangedEvent)
          .cast<VrmHostThermalStatusChangedEvent>();

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

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('VrmController has already been disposed.');
    }
  }
}

void _validateAnimationPlayback({
  required String fileName,
  required double speed,
  required double fadeDuration,
  required String? clipName,
}) {
  _requireNonEmpty(fileName, 'fileName');
  _requirePositiveFinite(speed, 'speed');
  _requireNonNegativeFinite(fadeDuration, 'fadeDuration');
  if (clipName != null) {
    _requireNonEmpty(clipName, 'clipName');
  }
}

void _validateMood(VrmMood mood) {
  if (mood.expression != null) {
    _requireUnitInterval(mood.expressionWeight, 'mood.expressionWeight');
  }
  if (mood.browExpression != null) {
    _requireUnitInterval(mood.browWeight, 'mood.browWeight');
  }
  final physics = mood.physics;
  if (physics != null) {
    _validatePhysics(
      stiffness: physics.stiffness,
      gravity: physics.gravity,
      drag: physics.drag,
    );
  }
}

void _validatePhysics({
  required double stiffness,
  required double gravity,
  required double drag,
}) {
  _requireNonNegativeFinite(stiffness, 'stiffness');
  _requireNonNegativeFinite(gravity, 'gravity');
  _requireNonNegativeFinite(drag, 'drag');
}

void _requireNonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
}

void _requirePositiveFinite(double value, String name) {
  if (!value.isFinite || value <= 0) {
    throw ArgumentError.value(value, name, 'Must be positive and finite.');
  }
}

void _requireNonNegativeFinite(double value, String name) {
  if (!value.isFinite || value < 0) {
    throw ArgumentError.value(value, name, 'Must be non-negative and finite.');
  }
}

void _requireUnitInterval(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(
      value,
      name,
      'Must be finite and between 0 and 1.',
    );
  }
}

void _requireNonNegativeDuration(Duration value, String name) {
  if (value.isNegative) {
    throw ArgumentError.value(value, name, 'Must not be negative.');
  }
}

/// A high-level handle bound to one real-time audio message.
///
/// Late callbacks can safely keep their original handle: once another session
/// starts, append, finish, and cancel return `false` without touching it.
final class VrmSpeechSession {
  const VrmSpeechSession._(this._controller, this.id, this.mode);

  final VrmController _controller;

  /// Opaque identifier also reported by [VrmSpeechFinishedEvent].
  final String id;

  final VrmSpeechMode mode;

  bool get isActive => _controller._speechState.isActive(id);

  /// Appends visemes when this is the active viseme session.
  Future<bool> appendVisemes(List<VisemeFrame> frames) {
    if (mode != VrmSpeechMode.viseme) {
      throw StateError('This speech session accepts amplitude frames.');
    }
    return _controller._appendSpeechVisemes(id, frames);
  }

  /// Appends amplitudes when this is the active amplitude session.
  Future<bool> appendAmplitudes(List<AmplitudeFrame> frames) {
    if (mode != VrmSpeechMode.amplitude) {
      throw StateError('This speech session accepts viseme frames.');
    }
    return _controller._appendSpeechAmplitudes(id, frames);
  }

  /// Declares the final audio duration and schedules neutral mouth state.
  Future<bool> finish(Duration audioDuration) {
    return _controller._finishSpeech(id, audioDuration);
  }

  /// Cancels this session only if it is still active.
  Future<bool> cancel() => _controller._cancelSpeechSession(id);
}
