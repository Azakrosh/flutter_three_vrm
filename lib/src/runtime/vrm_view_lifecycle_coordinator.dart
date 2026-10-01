import 'dart:async';

/// Serializes one VrmView initialization with its terminal resource cleanup.
///
/// Flutter State.dispose cannot await asynchronous work. This owner lets the
/// State mark its session disposed synchronously while ensuring that the native
/// adapter cleanup starts only after an already-running initialization settles.
final class VrmViewLifecycleCoordinator {
  VrmViewLifecycleCoordinator({required Future<void> Function() initialize})
    : _initialization = Future<void>.sync(initialize);

  final Future<void> _initialization;
  Future<void>? _disposeFuture;

  /// Waits for initialization and invokes [cleanup] exactly once.
  ///
  /// Cleanup also runs when initialization fails. Repeated calls return the
  /// same terminal future and ignore later cleanup callbacks.
  Future<void> dispose(Future<void> Function() cleanup) {
    return _disposeFuture ??= _dispose(cleanup);
  }

  Future<void> _dispose(Future<void> Function() cleanup) async {
    try {
      await _initialization;
    } finally {
      await cleanup();
    }
  }
}
