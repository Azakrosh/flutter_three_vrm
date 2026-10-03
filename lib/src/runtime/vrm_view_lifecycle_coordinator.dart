import 'dart:async';

typedef VrmViewLifecycleErrorReporter =
    void Function(Object error, StackTrace stackTrace);

/// Observes the terminal Future started by synchronous Flutter State.dispose.
///
/// The reporter receives the original error and stack trace. Its successful
/// return handles the failed Future so the error is not also emitted to the
/// current Zone as an unhandled asynchronous error.
void observeVrmViewLifecycleDisposal(
  Future<void> disposal, {
  required VrmViewLifecycleErrorReporter reportError,
}) {
  unawaited(
    disposal.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        reportError(error, stackTrace);
      },
    ),
  );
}

/// Serializes one VrmView initialization with its terminal resource cleanup.
///
/// Flutter State.dispose cannot await asynchronous work. This owner lets the
/// State mark its session disposed synchronously while ensuring that active
/// work settles and native cleanup starts only after initialization finishes.
final class VrmViewLifecycleCoordinator {
  VrmViewLifecycleCoordinator({required Future<void> Function() initialize})
    : _initialization = Future<void>.sync(initialize);

  final Future<void> _initialization;
  Future<void>? _disposeFuture;

  /// Waits for initialization and optional active work, then invokes [cleanup]
  /// exactly once.
  ///
  /// Every phase runs even when an earlier phase fails. The first failure is
  /// rethrown after cleanup. Repeated calls return the same terminal future and
  /// ignore later callbacks.
  Future<void> dispose({
    Future<void> Function()? settleBeforeCleanup,
    required Future<void> Function() cleanup,
  }) {
    return _disposeFuture ??= _dispose(settleBeforeCleanup, cleanup);
  }

  Future<void> _dispose(
    Future<void> Function()? settleBeforeCleanup,
    Future<void> Function() cleanup,
  ) async {
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> runPhase(Future<void> Function() phase) async {
      try {
        await phase();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    await runPhase(() => _initialization);
    if (settleBeforeCleanup != null) {
      await runPhase(settleBeforeCleanup);
    }
    await runPhase(cleanup);

    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }
}
