import 'dart:async';

import '../runtime/vrm_cleanup.dart';

/// Internal lifecycle coordinator shared by platform WebView adapters.
final class VrmWebViewAdapterLifecycle {
  Future<void>? _initializationFuture;
  Future<void>? _disposeFuture;
  final Set<Future<Object?>> _operations = <Future<Object?>>{};
  bool _disposeStarted = false;
  bool _initialized = false;

  Future<void> initialize(Future<void> Function() action) {
    _ensureActive();
    return _initializationFuture ??= Future<void>.sync(action).then<void>((_) {
      _initialized = true;
    });
  }

  Future<T> runOperation<T>(Future<T> Function() action) {
    _ensureActive();
    final initialization = _initializationFuture;
    if (initialization == null) {
      throw StateError('The VRM WebView adapter has not been initialized.');
    }

    final operation = _initialized
        ? Future<T>.sync(action)
        : initialization.then<T>((_) {
            _ensureActive();
            return action();
          });
    late final Future<T> tracked;
    tracked = operation.whenComplete(() => _operations.remove(tracked));
    _operations.add(tracked);
    return tracked;
  }

  void ensureActive() => _ensureActive();

  Future<void> dispose(Iterable<VrmCleanupPhase> cleanupPhases) {
    final existing = _disposeFuture;
    if (existing != null) return existing;
    _disposeStarted = true;
    return _disposeFuture = _dispose(List<VrmCleanupPhase>.of(cleanupPhases));
  }

  Future<void> _dispose(List<VrmCleanupPhase> cleanupPhases) async {
    await runVrmCleanupPhases([
      if (_initializationFuture case final initialization?)
        () => initialization,
      _waitForOperations,
      ...cleanupPhases,
    ]);
  }

  Future<void> _waitForOperations() async {
    while (_operations.isNotEmpty) {
      await Future.wait<Object?>(List<Future<Object?>>.of(_operations));
    }
  }

  void _ensureActive() {
    if (_disposeStarted) {
      throw StateError('The VRM WebView adapter has already been disposed.');
    }
  }
}
