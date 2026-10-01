import 'dart:async';

typedef VrmLatestTask<T> = Future<void> Function(T value);

/// Serializes asynchronous configuration while retaining only the latest
/// value that has not started yet.
///
/// Every [submit] returns a terminal future. If several queued values are
/// superseded, their futures share the outcome of the newest dispatched value.
final class VrmLatestTaskDispatcher<T> {
  VrmLatestTaskDispatcher({required this.dispatch});

  final VrmLatestTask<T> dispatch;

  T? _pendingValue;
  final List<Completer<void>> _pendingCompleters = [];
  bool _hasPendingValue = false;
  bool _isRunning = false;
  bool _isClosed = false;
  Completer<void> _idleCompleter = Completer<void>()..complete();

  Future<void> get idle => _idleCompleter.future;

  Future<void> submit(T value) {
    if (_isClosed) {
      return Future<void>.error(
        StateError('VrmLatestTaskDispatcher is closed.'),
      );
    }

    final completer = Completer<void>();
    if (_isRunning) {
      _pendingValue = value;
      _hasPendingValue = true;
      _pendingCompleters.add(completer);
      return completer.future;
    }

    _isRunning = true;
    if (_idleCompleter.isCompleted) {
      _idleCompleter = Completer<void>();
    }
    unawaited(
      Future<void>.microtask(() => _drain(value, <Completer<void>>[completer])),
    );
    return completer.future;
  }

  void close() {
    if (_isClosed) return;
    _isClosed = true;
    _pendingValue = null;
    _hasPendingValue = false;
    final error = StateError('VrmLatestTaskDispatcher was closed.');
    for (final completer in _pendingCompleters) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pendingCompleters.clear();
    if (!_isRunning && !_idleCompleter.isCompleted) {
      _idleCompleter.complete();
    }
  }

  Future<void> _drain(
    T currentValue,
    List<Completer<void>> currentCompleters,
  ) async {
    try {
      while (true) {
        try {
          await dispatch(currentValue);
          for (final completer in currentCompleters) {
            if (!completer.isCompleted) completer.complete();
          }
        } on Object catch (error, stackTrace) {
          for (final completer in currentCompleters) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          }
        }

        if (_isClosed || !_hasPendingValue) break;
        currentValue = _pendingValue as T;
        currentCompleters = List<Completer<void>>.of(_pendingCompleters);
        _pendingValue = null;
        _hasPendingValue = false;
        _pendingCompleters.clear();
      }
    } finally {
      _isRunning = false;
      if (!_idleCompleter.isCompleted) _idleCompleter.complete();
    }
  }
}
