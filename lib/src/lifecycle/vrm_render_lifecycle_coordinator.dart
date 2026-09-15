import 'package:flutter/widgets.dart';

import '../bridge/latest_value_dispatcher.dart';
import '../models/vrm_render_lifecycle_policy.dart';

typedef VrmRenderPauseDispatch = Future<void> Function(bool paused);

bool shouldPauseVrmRendering({
  required VrmRenderLifecyclePolicy policy,
  required TargetPlatform platform,
  required AppLifecycleState? lifecycleState,
  required bool renderingEnabled,
}) {
  if (!renderingEnabled) return true;
  return switch (lifecycleState) {
    null || AppLifecycleState.resumed => false,
    AppLifecycleState.hidden ||
    AppLifecycleState.paused ||
    AppLifecycleState.detached => true,
    AppLifecycleState.inactive => switch (policy) {
      VrmRenderLifecyclePolicy.pauseWhenHidden => false,
      VrmRenderLifecyclePolicy.pauseWhenUnfocused => true,
      VrmRenderLifecyclePolicy.platformDefault =>
        platform != TargetPlatform.windows,
    },
  };
}

/// Owns serialized, latest-value render-loop synchronization for one runtime.
final class VrmRenderLifecycleCoordinator {
  factory VrmRenderLifecycleCoordinator({
    required TargetPlatform platform,
    required AppLifecycleState? initialLifecycleState,
    required bool renderingEnabled,
    required VrmRenderLifecyclePolicy policy,
    required VrmRenderPauseDispatch dispatch,
    required LatestValueDispatchError onError,
  }) => VrmRenderLifecycleCoordinator._(
    platform,
    initialLifecycleState,
    renderingEnabled,
    policy,
    dispatch,
    onError,
  );

  VrmRenderLifecycleCoordinator._(
    this.platform,
    this._lifecycleState,
    this._renderingEnabled,
    this._policy,
    VrmRenderPauseDispatch dispatch,
    LatestValueDispatchError onError,
  ) {
    _dispatcher = LatestValueDispatcher<bool>(
      dispatch: dispatch,
      onError: (error, stackTrace) {
        _lastRequestedPause = null;
        if (!_isDisposed && _runtimeAttached) {
          onError(error, stackTrace);
        }
      },
    );
  }

  final TargetPlatform platform;
  late final LatestValueDispatcher<bool> _dispatcher;

  AppLifecycleState? _lifecycleState;
  bool _renderingEnabled;
  VrmRenderLifecyclePolicy _policy;
  bool _runtimeAttached = false;
  bool _isDisposed = false;
  bool? _lastRequestedPause;

  bool get shouldPause => shouldPauseVrmRendering(
    policy: _policy,
    platform: platform,
    lifecycleState: _lifecycleState,
    renderingEnabled: _renderingEnabled,
  );

  Future<void> get idle => _dispatcher.idle;

  Future<void> attachRuntime() async {
    if (_isDisposed) return;
    _runtimeAttached = true;
    _lastRequestedPause = null;
    _scheduleSynchronization();
    await idle;
  }

  void detachRuntime() {
    if (_isDisposed) return;
    _runtimeAttached = false;
    _lastRequestedPause = null;
    _dispatcher.clear();
  }

  void updateLifecycleState(AppLifecycleState state) {
    if (_isDisposed) return;
    _lifecycleState = state;
    _scheduleSynchronization();
  }

  void updateConfiguration({
    required bool renderingEnabled,
    required VrmRenderLifecyclePolicy policy,
  }) {
    if (_isDisposed) return;
    _renderingEnabled = renderingEnabled;
    _policy = policy;
    _scheduleSynchronization();
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _runtimeAttached = false;
    _lastRequestedPause = null;
    _dispatcher.close();
  }

  void _scheduleSynchronization() {
    if (!_runtimeAttached || _isDisposed) return;
    final pause = shouldPause;
    if (_lastRequestedPause == pause) return;
    _lastRequestedPause = pause;
    _dispatcher.add(pause);
  }
}
