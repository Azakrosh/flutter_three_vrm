import 'dart:async';

import 'package:flutter/widgets.dart';

import '../content/vrm_content_host.dart';
import '../lifecycle/vrm_render_lifecycle_coordinator.dart';
import '../models/vrm_render_lifecycle_policy.dart';
import '../models/vrm_runtime_health.dart';
import '../models/vrm_transform.dart';
import '../recovery/vrm_runtime_replay_coordinator.dart';
import 'vrm_runtime_controller_binding.dart';
import 'vrm_runtime_transition.dart';

typedef VrmRuntimeSessionErrorReporter =
    void Function(Object error, StackTrace stackTrace);

/// Durable application-owned state that must be replayed for a new document.
final class VrmRuntimeSessionReplayPlan {
  const VrmRuntimeSessionReplayPlan({
    required this.applyGraphics,
    required this.applyBackground,
    this.loadPackageModel,
    required this.applyApplicationState,
  });

  final VrmRuntimeReplayAction applyGraphics;
  final VrmRuntimeReplayAction applyBackground;
  final VrmRuntimeReplayAction? loadPackageModel;
  final VrmRuntimeReplayAction applyApplicationState;
}

/// Owns the state machine for one embedded VRM runtime document.
///
/// This class deliberately has no dependency on [State] or [BuildContext].
/// The widget owns presentation while this coordinator owns runtime
/// generations, ordered replay, lifecycle synchronization, bounded recovery,
/// and the camera snapshot carried across a document reload.
final class VrmRuntimeSessionCoordinator {
  factory VrmRuntimeSessionCoordinator({
    required TargetPlatform platform,
    required AppLifecycleState? initialLifecycleState,
    required bool renderingEnabled,
    required VrmRenderLifecyclePolicy lifecyclePolicy,
    required VrmRuntimeRecoveryPolicy recoveryPolicy,
    required VrmRenderPauseDispatch dispatchRenderingPaused,
    required Future<void> Function() reloadRuntimeDocument,
    required void Function(Object reason) markRuntimeUnavailable,
    required VrmRuntimeSessionErrorReporter reportAsyncError,
    required void Function() onChanged,
    required VrmTransform? Function() readCameraTransform,
    required int Function() readCameraRevision,
    required bool Function() isModelLoaded,
    required Future<void> Function(VrmTransform transform) applyCameraTransform,
  }) => VrmRuntimeSessionCoordinator._(
    platform,
    initialLifecycleState,
    renderingEnabled,
    lifecyclePolicy,
    recoveryPolicy,
    dispatchRenderingPaused,
    reloadRuntimeDocument,
    markRuntimeUnavailable,
    reportAsyncError,
    onChanged,
    readCameraTransform,
    readCameraRevision,
    isModelLoaded,
    applyCameraTransform,
  );

  VrmRuntimeSessionCoordinator._(
    TargetPlatform platform,
    AppLifecycleState? initialLifecycleState,
    bool renderingEnabled,
    VrmRenderLifecyclePolicy lifecyclePolicy,
    VrmRuntimeRecoveryPolicy recoveryPolicy,
    VrmRenderPauseDispatch dispatchRenderingPaused,
    this._reloadRuntimeDocument,
    this._markRuntimeUnavailable,
    this._reportAsyncError,
    this._onChanged,
    this._readCameraTransform,
    this._readCameraRevision,
    this._isModelLoaded,
    this._applyCameraTransform,
  ) : _recoveryPolicy = recoveryPolicy {
    recoveryPolicy.validate();
    _lifecycle = VrmRenderLifecycleCoordinator(
      platform: platform,
      initialLifecycleState: initialLifecycleState,
      renderingEnabled: renderingEnabled,
      policy: lifecyclePolicy,
      dispatch: dispatchRenderingPaused,
      onError: (error, stackTrace) {
        if (!_disposed && _runtimeReady) {
          _reportAsyncError(error, stackTrace);
        }
      },
    );
  }

  final VrmRuntimeReplayCoordinator _replay = VrmRuntimeReplayCoordinator();
  late final VrmRenderLifecycleCoordinator _lifecycle;
  VrmRuntimeControllerBinding? _controllerBinding;
  final Future<void> Function() _reloadRuntimeDocument;
  final void Function(Object reason) _markRuntimeUnavailable;
  final VrmRuntimeSessionErrorReporter _reportAsyncError;
  final void Function() _onChanged;
  final VrmTransform? Function() _readCameraTransform;
  final int Function() _readCameraRevision;
  final bool Function() _isModelLoaded;
  final Future<void> Function(VrmTransform transform) _applyCameraTransform;

  VrmRuntimeRecoveryPolicy _recoveryPolicy;
  bool _runtimeReady = false;
  bool _disposed = false;
  String? _errorMessage;
  int _recoveryAttempts = 0;
  bool _recoveryInProgress = false;
  bool _recoveryRequested = false;
  Future<void>? _recoveryTask;
  Completer<void>? _recoveryDelayCancellation;
  Future<void>? _disposeFuture;

  bool get isRuntimeReady => !_disposed && _runtimeReady;
  bool get isTransportAttached =>
      !_disposed && (_controllerBinding?.isTransportAttached ?? false);
  VrmContentHost? get contentHost => _controllerBinding?.contentHost;
  String? get errorMessage => _errorMessage;
  int get recoveryAttempts => _recoveryAttempts;
  bool get recoveryInProgress => _recoveryInProgress;
  Future<void> get recoveryIdle => _recoveryTask ?? Future<void>.value();

  /// Transfers controller/WebView resource ownership to this session.
  void attachControllerBinding(VrmRuntimeControllerBinding binding) {
    if (_disposed) {
      throw StateError('VRM runtime session has already been disposed.');
    }
    if (_controllerBinding != null) {
      throw StateError('A runtime controller binding is already attached.');
    }
    _controllerBinding = binding;
  }

  void attachTransport() {
    _requireControllerBinding.attachTransport();
  }

  void attachContentHost(VrmContentHost contentHost) {
    _requireControllerBinding.attachContentHost(contentHost);
  }

  void rebindController(VrmRuntimeControllerEndpoint endpoint) {
    _requireControllerBinding.rebind(endpoint);
    controllerRebound();
  }

  void recordHostMemoryPressure() {
    if (!_disposed) {
      _controllerBinding?.recordHostMemoryPressure();
    }
  }

  void updateConfiguration({
    required bool renderingEnabled,
    required VrmRenderLifecyclePolicy lifecyclePolicy,
    required VrmRuntimeRecoveryPolicy recoveryPolicy,
  }) {
    if (_disposed) return;
    recoveryPolicy.validate();
    _recoveryPolicy = recoveryPolicy;
    if (!recoveryPolicy.enabled) {
      _recoveryRequested = false;
      _cancelRecoveryDelay();
    }
    _lifecycle.updateConfiguration(
      renderingEnabled: renderingEnabled,
      policy: lifecyclePolicy,
    );
  }

  void updateLifecycleState(AppLifecycleState state) {
    _lifecycle.updateLifecycleState(state);
  }

  /// Re-synchronizes lifecycle state after the attached controller changes.
  void controllerRebound() {
    if (_disposed) return;
    _lifecycle.detachRuntime();
    _replay.clearCamera();
    if (_runtimeReady) {
      unawaited(_lifecycle.attachRuntime());
    }
  }

  Future<void> activateRuntime(VrmRuntimeSessionReplayPlan plan) async {
    if (_disposed || _runtimeReady) return;

    final generation = _replay.beginRuntime();
    _runtimeReady = true;
    _errorMessage = null;
    _recoveryAttempts = 0;
    _recoveryRequested = false;
    _cancelRecoveryDelay();
    _notifyChanged();

    try {
      await _replay.replay(
        generation: generation,
        steps: [
          VrmRuntimeReplayStep(
            VrmRuntimeReplayPhase.lifecycle,
            _lifecycle.attachRuntime,
          ),
          VrmRuntimeReplayStep(
            VrmRuntimeReplayPhase.graphics,
            plan.applyGraphics,
          ),
          VrmRuntimeReplayStep(
            VrmRuntimeReplayPhase.background,
            plan.applyBackground,
          ),
          if (plan.loadPackageModel case final loadPackageModel?)
            VrmRuntimeReplayStep(
              VrmRuntimeReplayPhase.packageModel,
              loadPackageModel,
            ),
          VrmRuntimeReplayStep(
            VrmRuntimeReplayPhase.applicationState,
            plan.applyApplicationState,
          ),
          VrmRuntimeReplayStep(
            VrmRuntimeReplayPhase.camera,
            () => _restoreCamera(generation),
          ),
        ],
      );
    } on Object catch (error, stackTrace) {
      if (!isCurrentRuntime(generation)) return;
      _reportAsyncError(error, stackTrace);
      showError('Failed to configure restored VRM runtime: $error');
    }
  }

  bool isCurrentRuntime(int generation) =>
      !_disposed && _runtimeReady && _replay.isCurrent(generation);

  void showError(String message) {
    if (_disposed || _errorMessage == message) return;
    _errorMessage = message;
    _notifyChanged();
  }

  void handleRuntimeResourceError(String message) {
    if (_disposed) return;
    final error = StateError('WebView runtime resource error: $message');
    _setRuntimeUnavailable(error, errorMessage: message);
    _recoveryRequested = true;
    _startRecoveryIfNeeded();
  }

  /// Reloads the current runtime document while preserving its camera state.
  Future<void> reloadRuntime() async {
    if (_disposed) {
      throw StateError('VRM runtime session has already been disposed.');
    }
    _replay.captureCamera(_readCameraTransform(), _readCameraRevision());
    _setRuntimeUnavailable(
      vrmRuntimeTransitionCancellation,
      errorMessage: null,
    );
    await _reloadRuntimeDocument();
  }

  Future<void> restoreCameraAfterModelLoad() async {
    final generation = _replay.activeGeneration;
    if (generation == null) return;
    await _restoreCamera(generation);
  }

  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) return existing;

    _disposed = true;
    final controllerBinding = _controllerBinding;
    _controllerBinding = null;
    _runtimeReady = false;
    _recoveryRequested = false;
    _replay.dispose();
    final lifecycleDisposal = _lifecycle.dispose();
    _cancelRecoveryDelay();

    final pending = <Future<void>>[
      lifecycleDisposal,
      ?controllerBinding?.dispose(),
      ?_recoveryTask,
    ];
    final disposal = Future.wait<void>(pending).then<void>((_) {});
    _disposeFuture = disposal;
    return disposal;
  }

  void _setRuntimeUnavailable(Object reason, {required String? errorMessage}) {
    _replay.invalidateRuntime();
    _lifecycle.detachRuntime();
    _runtimeReady = false;
    _errorMessage = errorMessage;
    _markRuntimeUnavailable(reason);
    _notifyChanged();
  }

  void _startRecoveryIfNeeded() {
    if (_disposed || _recoveryInProgress) return;
    _recoveryTask = _runRecoveryLoop();
  }

  Future<void> _runRecoveryLoop() async {
    _recoveryInProgress = true;
    try {
      while (_recoveryRequested &&
          !_disposed &&
          _recoveryPolicy.enabled &&
          _recoveryAttempts < _recoveryPolicy.maxAttempts) {
        _recoveryRequested = false;
        _recoveryAttempts += 1;
        await _waitForRecoveryDelay(
          _recoveryPolicy.delayForAttempt(_recoveryAttempts),
        );
        if (_disposed || _runtimeReady) return;
        try {
          await reloadRuntime();
        } on Object catch (error, stackTrace) {
          if (_disposed) return;
          _recoveryRequested = true;
          _reportAsyncError(error, stackTrace);
          showError('Failed to recover VRM runtime: $error');
        }
      }
    } finally {
      _recoveryInProgress = false;
      _recoveryTask = null;
    }
  }

  Future<void> _waitForRecoveryDelay(Duration duration) async {
    final cancellation = Completer<void>();
    _recoveryDelayCancellation = cancellation;
    try {
      await Future.any<void>([
        Future<void>.delayed(duration),
        cancellation.future,
      ]);
    } finally {
      if (identical(_recoveryDelayCancellation, cancellation)) {
        _recoveryDelayCancellation = null;
      }
    }
  }

  void _cancelRecoveryDelay() {
    final cancellation = _recoveryDelayCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
  }

  Future<void> _restoreCamera(int generation) {
    return _replay.restoreCamera(
      generation: generation,
      modelLoaded: _isModelLoaded(),
      currentRevision: _readCameraRevision(),
      apply: _applyCameraTransform,
    );
  }

  void _notifyChanged() {
    if (!_disposed) {
      _onChanged();
    }
  }

  VrmRuntimeControllerBinding get _requireControllerBinding {
    if (_disposed) {
      throw StateError('VRM runtime session has already been disposed.');
    }
    return _controllerBinding ??
        (throw StateError('Runtime controller binding is not attached.'));
  }
}
