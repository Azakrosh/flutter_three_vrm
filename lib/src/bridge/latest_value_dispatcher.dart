import 'dart:async';

typedef LatestValueDispatch<T> = Future<void> Function(T value);
typedef LatestValueDispatchError =
    void Function(Object error, StackTrace stackTrace);

/// Serializes an asynchronous sink while retaining only its newest queued value.
///
/// This is intentionally internal to the package. It bounds bridge work for
/// realtime controls where stale intermediate samples have no value.
final class LatestValueDispatcher<T> {
  LatestValueDispatcher({required this.dispatch, required this.onError});

  final LatestValueDispatch<T> dispatch;
  final LatestValueDispatchError onError;

  T? _pendingValue;
  bool _hasPendingValue = false;
  bool _isRunning = false;
  bool _isClosed = false;
  int _generation = 0;
  Completer<void> _idleCompleter = Completer<void>()..complete();

  Future<void> get idle => _idleCompleter.future;

  void add(T value) {
    if (_isClosed) {
      throw StateError('LatestValueDispatcher is closed.');
    }
    _pendingValue = value;
    _hasPendingValue = true;
    if (!_isRunning) {
      _startDrain();
    }
  }

  /// Drops a queued value and invalidates the result of an in-flight dispatch.
  void clear() {
    _pendingValue = null;
    _hasPendingValue = false;
    _generation += 1;
    if (!_isRunning && !_idleCompleter.isCompleted) {
      _idleCompleter.complete();
    }
  }

  void close() {
    if (_isClosed) return;
    _isClosed = true;
    clear();
  }

  void _startDrain() {
    _isRunning = true;
    if (_idleCompleter.isCompleted) {
      _idleCompleter = Completer<void>();
    }
    unawaited(_drain(_generation));
  }

  Future<void> _drain(int generation) async {
    try {
      while (!_isClosed && generation == _generation && _hasPendingValue) {
        final value = _pendingValue as T;
        _pendingValue = null;
        _hasPendingValue = false;
        try {
          await dispatch(value);
        } on Object catch (error, stackTrace) {
          if (!_isClosed && generation == _generation) {
            onError(error, stackTrace);
          }
        }
      }
    } finally {
      _isRunning = false;
      if (!_isClosed && _hasPendingValue) {
        _startDrain();
      } else if (!_idleCompleter.isCompleted) {
        _idleCompleter.complete();
      }
    }
  }
}
