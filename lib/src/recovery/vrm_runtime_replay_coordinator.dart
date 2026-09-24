import '../models/vrm_transform.dart';

typedef VrmRuntimeReplayAction = Future<void> Function();
typedef VrmCameraRestoreAction = Future<void> Function(VrmTransform transform);

/// Ordered state groups restored after a WebView runtime is created again.
enum VrmRuntimeReplayPhase {
  lifecycle,
  graphics,
  background,
  packageModel,
  applicationState,
  camera,
}

/// One idempotent step in a runtime state replay.
final class VrmRuntimeReplayStep {
  const VrmRuntimeReplayStep(this.phase, this.run);

  final VrmRuntimeReplayPhase phase;
  final VrmRuntimeReplayAction run;
}

enum VrmRuntimeReplayResult { completed, superseded }

/// Owns runtime generations and the deterministic replay of durable state.
///
/// A new runtime generation supersedes every older replay. This prevents an
/// asynchronous model load or application callback from continuing to apply
/// state to a replacement WebView document.
final class VrmRuntimeReplayCoordinator {
  int _generation = 0;
  bool _disposed = false;
  VrmTransform? _pendingCameraTransform;
  int? _pendingCameraRevision;
  bool _cameraRestoreInProgress = false;

  int? get activeGeneration =>
      _disposed || _generation == 0 ? null : _generation;

  int beginRuntime() {
    if (_disposed) {
      throw StateError('VrmRuntimeReplayCoordinator has been disposed.');
    }
    return ++_generation;
  }

  void invalidateRuntime() {
    if (_disposed) return;
    _generation += 1;
  }

  bool isCurrent(int generation) => !_disposed && generation == _generation;

  Future<VrmRuntimeReplayResult> replay({
    required int generation,
    required List<VrmRuntimeReplayStep> steps,
  }) async {
    if (!isCurrent(generation)) {
      return VrmRuntimeReplayResult.superseded;
    }
    for (final step in steps) {
      await step.run();
      if (!isCurrent(generation)) {
        return VrmRuntimeReplayResult.superseded;
      }
    }
    return VrmRuntimeReplayResult.completed;
  }

  /// Captures the last user camera transform once for the next runtime.
  void captureCamera(VrmTransform? transform, int revision) {
    if (_disposed || transform == null || _pendingCameraTransform != null) {
      return;
    }
    _pendingCameraTransform = transform;
    _pendingCameraRevision = revision;
  }

  void clearCamera() {
    _pendingCameraTransform = null;
    _pendingCameraRevision = null;
    _cameraRestoreInProgress = false;
  }

  Future<void> restoreCamera({
    required int generation,
    required bool modelLoaded,
    required int currentRevision,
    required VrmCameraRestoreAction apply,
  }) async {
    final transform = _pendingCameraTransform;
    final revision = _pendingCameraRevision;
    if (!isCurrent(generation) ||
        transform == null ||
        revision == null ||
        _cameraRestoreInProgress ||
        !modelLoaded) {
      return;
    }
    if (currentRevision != revision) {
      clearCamera();
      return;
    }

    _cameraRestoreInProgress = true;
    try {
      await apply(transform);
      if (isCurrent(generation) && currentRevision == revision) {
        _pendingCameraTransform = null;
        _pendingCameraRevision = null;
      }
    } finally {
      _cameraRestoreInProgress = false;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    clearCamera();
  }
}
