part of 'vrm_runtime.dart';

/// Primary controller for loading, animating, and interacting with one VRM model.
class VrmController {
  final _VrmBridge _bridge = _VrmBridge();
  late final VrmHostResourceMonitor _hostResourceMonitor;
  late final VrmPlatformThermalMonitor _platformThermalMonitor;
  late final VrmHostedResourceDispatcher _hostedResources;
  late final VrmAnimationDispatcher _animations;
  late final VrmModelDispatcher _models;
  late final VrmSpeechDispatcher _speech;
  late final VrmSceneDispatcher _scene;
  late final VrmGraphicsDispatcher _graphics;
  late final VrmAvatarControlDispatcher _avatar;
  late final StreamSubscription<VrmEvent> _stateSubscription;
  bool _isDisposed = false;
  VrmTransform? _lastKnownCameraTransform;
  int _cameraTransformRevision = 0;
  int _hostResourceMonitoringClients = 0;

  VrmController() {
    _hostedResources = VrmHostedResourceDispatcher(
      _ensureNotDisposed,
      _bridge.sendCommand,
    );
    _animations = VrmAnimationDispatcher(_hostedResources, _bridge.sendCommand);
    _models = VrmModelDispatcher(_hostedResources, _bridge.sendCommand);
    _speech = VrmSpeechDispatcher(
      _ensureNotDisposed,
      _bridge.sendCommand,
      _bridge.sendLatestCommand,
      _bridge.clearLatestCommand,
    );
    _scene = VrmSceneDispatcher(
      _hostedResources,
      _bridge.sendCommand,
      _sendCommand,
    );
    _graphics = VrmGraphicsDispatcher(
      _bridge.sendCommand,
      _bridge.requestCommand,
    );
    _avatar = VrmAvatarControlDispatcher(
      _ensureNotDisposed,
      _bridge.sendCommand,
      _bridge.requestCommand,
      _sendCommand,
      _bridge.sendLatestCommand,
      _speech,
    );
    _platformThermalMonitor = VrmPlatformThermalMonitor(
      onStatusChanged: _publishThermalStatus,
    );
    _hostResourceMonitor = VrmHostResourceMonitor(
      thermalStatusReader: () => _platformThermalMonitor.status,
    );
    _stateSubscription = _bridge.eventStream.listen((event) {
      switch (event) {
        case VrmModelLoadedEvent():
          _models.restoreLoaded(true);
        case VrmModelUnloadedEvent():
          _models.restoreLoaded(false);
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
          _speech.handleFinished(sessionId);
        default:
          break;
      }
    });
  }

  /// True while a model is being transferred and parsed by the runtime.
  bool get isLoadingModel => _models.isLoading;

  /// Whether the currently attached runtime contains an avatar.
  bool get isModelLoaded => _models.isLoaded;

  /// Whether the JavaScript runtime completed protocol initialization.
  bool get isRuntimeReady => _bridge.isRuntimeReady;

  /// Whether a speech timeline is active or waiting for its declared end.
  bool get isSpeechActive => _speech.hasActiveSession;

  /// Input type accepted by the current speech timeline.
  VrmSpeechMode? get speechMode => _speech.activeMode;

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
    _hostedResources.attach(contentHost);
  }

  void _detachContentHost(VrmContentHost contentHost) {
    if (_hostedResources.detach(contentHost)) {
      _models.invalidateRuntime();
    }
  }

  VrmRuntimeControllerEndpoint _createRuntimeEndpoint() {
    return VrmRuntimeControllerEndpoint(
      identity: this,
      states: onStateChanged,
      errors: onError,
      modelLoadedEvents: onModelLoaded,
      modelReports: onModelReport,
      modelUnloadedEvents: onModelUnloaded,
      readModelLoaded: () => isModelLoaded,
      restoreModelLoaded: _models.restoreLoaded,
      handleRuntimeMessage: _bridge.handleJsMessage,
      attachTransport:
          ({
            required owner,
            required runJavaScript,
            required reloadRuntime,
            required runtimeReady,
          }) {
            _bridge.attachTransport(
              owner: owner,
              runJavaScript: runJavaScript,
              reloadRuntime: reloadRuntime,
              runtimeReady: runtimeReady,
            );
          },
      detachTransport: _bridge.detachTransport,
      attachContentHost: _attachContentHost,
      detachContentHost: _detachContentHost,
      attachHostResourceMonitoring: _attachHostResourceMonitoring,
      detachHostResourceMonitoring: _detachHostResourceMonitoring,
      recordHostMemoryPressure: _recordHostMemoryPressure,
      reportAsyncError: _bridge.reportAsyncError,
    );
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

  // --- Model lifecycle ---

  /// Loads a VRM model from Flutter assets.
  Future<void> loadModel(String folderPath, String fileName) {
    return _models.loadHosted(
      expose: (host) => host.exposeAsset('$folderPath$fileName'),
      fileName: fileName,
    );
  }

  /// Loads a VRM model from a local file.
  Future<void> loadModelFromFile(io.File file) {
    return _models.loadHosted(
      expose: (host) => host.exposeFile(file),
      fileName: p.basename(file.path),
    );
  }

  /// Loads VRM bytes obtained by an authenticated Flutter API client.
  ///
  /// For very large models prefer [loadModelFromFile] to avoid retaining the
  /// complete file in Dart memory.
  Future<void> loadModelFromBytes(Uint8List bytes, {required String fileName}) {
    return _models.loadHosted(
      expose: (host) => host.exposeBytes(bytes, fileName: fileName),
      fileName: fileName,
    );
  }

  /// Loads a public URL directly in WebView.
  ///
  /// Prefer [loadModelFromFile] or [loadModelFromBytes] for authenticated URLs.
  Future<void> loadModelFromUrl(String url) => _models.loadUrl(url);

  /// Cancels the active model transfer or parse operation.
  ///
  /// The previously displayed avatar remains active. The canceled load Future
  /// completes with `VrmRuntimeException(code: 'canceled')`.
  Future<void> cancelModelLoad() => _models.cancelLoad();

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
    _models.restoreLoaded(health.modelLoaded);
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
    _models.invalidateRuntime();
    _speech.invalidateRuntime();
  }

  void _publishModelAssessment(VrmModelAssessment assessment) {
    _bridge.publishEvent(VrmModelAssessmentEvent(assessment: assessment));
  }

  /// Unloads the model and releases its GPU resources.
  Future<void> unloadModel() async {
    await _models.unload(speechRevision: _speech.takeMouthControl());
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
    return _animations.playHosted(
      expose: expose,
      fileName: fileName,
      loop: loop,
      speed: speed,
      fadeDuration: fadeDuration,
      rootMotion: rootMotion,
      clipName: clipName,
    );
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
    return _animations.playUrl(
      url,
      loop: loop,
      speed: speed,
      fadeDuration: fadeDuration,
      rootMotion: rootMotion,
      clipName: clipName,
    );
  }

  /// Pauses animation clip playback.
  Future<void> pauseAnimation() => _animations.pause();

  /// Resumes animation clip playback.
  Future<void> resumeAnimation({double speed = 1.0}) {
    return _animations.resume(speed: speed);
  }

  /// Cancels an animation transfer without stopping the current action.
  Future<void> cancelAnimationLoad() => _animations.cancelLoad();

  /// Stops the current action and cancels an in-flight animation load.
  Future<void> stopAnimation({double fadeDuration = 0.5}) {
    return _animations.stop(fadeDuration: fadeDuration);
  }

  /// Sets playback speed multiplier for current animation.
  Future<void> setAnimationSpeed(double speed) {
    return _animations.setSpeed(speed);
  }

  // --- Humanoid pose ---

  /// Returns the model's normalized humanoid pose.
  ///
  /// Bone transforms are relative to the normalized rest pose defined by
  /// `@pixiv/three-vrm`, so the result can be stored and applied to another
  /// compatible VRM avatar.
  Future<VrmPose> getPose() => _avatar.getPose();

  /// Applies a normalized humanoid [pose].
  ///
  /// Pose and clip playback share one mixer, so switching from either source
  /// crossfades without snapping through the rest pose.
  Future<void> setPose(VrmPose pose, {double fadeDuration = 0.5}) {
    return _avatar.setPose(pose, fadeDuration: fadeDuration);
  }

  /// Smoothly restores all normalized humanoid bones to their rest transforms.
  Future<void> resetPose({double fadeDuration = 0.5}) {
    return _avatar.resetPose(fadeDuration: fadeDuration);
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
    _avatar.setExpression(
      expression,
      layer: layer,
      weight: weight,
      duration: duration,
      disableAutoBlink: disableAutoBlink,
    );
  }

  /// Clears active expression from a layer.
  void clearExpressionLayer(ExpressionLayer layer) {
    _avatar.clearExpressionLayer(layer);
  }

  /// Clears all active facial expressions, blendshapes, and visemes.
  void clearAllExpressions() {
    _avatar.clearAllExpressions();
  }

  /// Sets a custom blendshape key by name and weight (0.0 to 1.0).
  void setCustomBlendShape(String name, double weight) {
    _avatar.setCustomBlendShape(name, weight);
  }
  // --- Lip Sync (ElevenLabs & Amplitude) ---

  /// Sets real-time audio volume amplitude (0.0 to 1.0) for smooth speech mouth opening.
  void setLipSyncAmplitude(double amplitude) {
    _speech.setAmplitude(amplitude);
  }

  /// Sets the latest direct viseme state without queueing stale bridge updates.
  void setViseme(VrmViseme viseme, {double weight = 1.0}) {
    _speech.setViseme(viseme, weight: weight);
  }

  /// Enqueues a list of timed speech viseme frames for TTS playback.
  Future<void> enqueueSpeechVisemes(List<VisemeFrame> frames) {
    return _speech.enqueueVisemes(frames);
  }

  /// Enqueues a complete timestamped amplitude timeline in one command.
  Future<void> enqueueSpeechAmplitudes(List<AmplitudeFrame> frames) {
    return _speech.enqueueAmplitudes(frames);
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
    final token = await _speech.begin(mode: mode, startDelay: startDelay);
    return VrmSpeechSession._(_speech, token.id, token.mode);
  }

  /// Fully stops the active speech timeline and closes the mouth layer.
  Future<void> cancelSpeech() => _speech.cancel();

  // --- Programmatic gaze & Auto-Blink ---

  /// Toggles random eye saccades.
  void setAutoSaccades({bool enabled = true}) {
    _avatar.setAutoSaccades(enabled: enabled);
  }

  /// Toggles automatic blinking.
  void setAutoBlink(bool enabled) {
    _avatar.setAutoBlink(enabled);
  }

  /// Directs the avatar's eyes to an explicit target; taps do not change gaze.
  void setLookAtTarget(Offset screenPosition) {
    _avatar.setLookAtTarget(screenPosition);
  }

  /// Configures how long an explicit gaze target is held (default 1 second).
  void setLookAtConfig({Duration? holdDuration}) {
    _avatar.setLookAtConfig(holdDuration: holdDuration);
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

  /// Configures scene lighting intensity and colors.
  void setLighting({
    Color? ambientColor,
    double? ambientIntensity,
    Color? directionalColor,
    double? directionalIntensity,
  }) {
    _scene.setLighting(
      ambientColor: ambientColor,
      ambientIntensity: ambientIntensity,
      directionalColor: directionalColor,
      directionalIntensity: directionalIntensity,
    );
  }

  /// Intelligently tints the model's rim and ambient lighting to match the environment/background color.
  /// [color] is the dominant color of the background.
  /// [intensity] (0.0 to 1.0) controls how strongly the ambient light mixes with the background color (default 0.5).
  void setEnvironmentColor(Color color, {double intensity = 0.5}) {
    _scene.setEnvironmentColor(color, intensity: intensity);
  }

  /// Enables or disables real-time shadow mapping in WebGL.
  /// Shadows improve visual quality significantly but increase GPU usage.
  void setShadows(bool enabled) {
    _scene.setShadows(enabled);
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
    _scene.setPhysics(stiffness: stiffness, gravity: gravity, drag: drag);
  }

  /// Enables and configures wind simulation affecting the model's physics.
  void setWind({
    VrmWindType type = VrmWindType.none,
    VrmWindDirection direction = VrmWindDirection.right,
  }) {
    _scene.setWind(type: type, direction: direction);
  }

  /// Smoothly fades out the wind effect over a few seconds.
  void stopWind() {
    _scene.stopWind();
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
  }) {
    return _scene.setBackground(
      color: color,
      transparent: transparent,
      imageAssetPath: imageAssetPath,
      imageUrl: imageUrl,
    );
  }

  /// Configures the scene background from a local image file.
  Future<void> setBackgroundFromFile(
    io.File file, {
    required Color color,
    bool transparent = false,
  }) {
    return _scene.setBackgroundFromFile(
      file,
      color: color,
      transparent: transparent,
    );
  }

  /// Configures the scene background from authenticated image bytes.
  Future<void> setBackgroundFromBytes(
    Uint8List bytes, {
    required String fileName,
    required Color color,
    bool transparent = false,
  }) {
    return _scene.setBackgroundFromBytes(
      bytes,
      fileName: fileName,
      color: color,
      transparent: transparent,
    );
  }

  /// Sets the pixel ratio for WebGL rendering.
  @Deprecated('Use setGraphicsSettings(pixelRatio: value) instead')
  Future<void> setRenderQuality(double pixelRatio) {
    return _graphics.setSettings(pixelRatio: pixelRatio);
  }

  /// Applies a curated renderer profile.
  Future<void> setGraphicsPreset(VrmGraphicsPreset preset) {
    return _graphics.setPreset(preset);
  }

  /// Enables or configures automatic render-resolution adaptation.
  Future<void> setAdaptiveQuality(VrmAdaptiveQualitySettings settings) {
    return _graphics.setAdaptiveQuality(settings);
  }

  /// Returns the latest renderer workload measurement.
  Future<VrmPerformanceSnapshot> getPerformanceSnapshot() {
    return _graphics.getPerformanceSnapshot();
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
    return _graphics.setSettings(
      pixelRatio: pixelRatio,
      antialias: antialias,
      enablePhysics: enablePhysics,
      fpsCap: fpsCap,
    );
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

/// A high-level handle bound to one real-time audio message.
///
/// Late callbacks can safely keep their original handle: once another session
/// starts, append, finish, and cancel return `false` without touching it.
final class VrmSpeechSession {
  const VrmSpeechSession._(this._dispatcher, this.id, this.mode);

  final VrmSpeechDispatcher _dispatcher;

  /// Opaque identifier also reported by [VrmSpeechFinishedEvent].
  final String id;

  final VrmSpeechMode mode;

  bool get isActive => _dispatcher.isActive(id);

  /// Appends visemes when this is the active viseme session.
  Future<bool> appendVisemes(List<VisemeFrame> frames) {
    if (mode != VrmSpeechMode.viseme) {
      throw StateError('This speech session accepts amplitude frames.');
    }
    return _dispatcher.appendVisemes(id, frames);
  }

  /// Appends amplitudes when this is the active amplitude session.
  Future<bool> appendAmplitudes(List<AmplitudeFrame> frames) {
    if (mode != VrmSpeechMode.amplitude) {
      throw StateError('This speech session accepts viseme frames.');
    }
    return _dispatcher.appendAmplitudes(id, frames);
  }

  /// Declares the final audio duration and schedules neutral mouth state.
  Future<bool> finish(Duration audioDuration) {
    return _dispatcher.finish(id, audioDuration);
  }

  /// Cancels this session only if it is still active.
  Future<bool> cancel() => _dispatcher.cancelSession(id);
}
