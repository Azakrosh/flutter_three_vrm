part of '../vrm_runtime.dart';

typedef VrmJavaScriptRunner = Future<void> Function(String source);
typedef VrmRuntimeReloader = Future<void> Function();

final class _VrmBridge {
  static const Duration _commandTimeout = Duration(minutes: 2);
  static const int _maxIgnoredResponseIds = 256;
  final StreamController<VrmEvent> _eventController =
      StreamController<VrmEvent>.broadcast();
  final Map<String, _PendingCommand> _pending = <String, _PendingCommand>{};
  final Set<String> _ignoredResponseIds = <String>{};
  final Map<String, LatestValueDispatcher<Map<String, dynamic>>>
  _latestDispatchers = <String, LatestValueDispatcher<Map<String, dynamic>>>{};

  Object? _transportOwner;
  VrmJavaScriptRunner? _runJavaScript;
  VrmRuntimeReloader? _reloadRuntime;
  int _nextCommandId = 0;
  bool _disposed = false;
  bool _runtimeReady = false;

  Stream<VrmEvent> get eventStream => _eventController.stream;
  bool get isRuntimeReady => _runtimeReady;

  void publishEvent(VrmEvent event) {
    if (!_disposed) {
      _eventController.add(event);
    }
  }

  void attachTransport({
    required Object owner,
    required VrmJavaScriptRunner runJavaScript,
    required VrmRuntimeReloader reloadRuntime,
    required bool runtimeReady,
  }) {
    if (_disposed) {
      throw StateError('VrmController has already been disposed.');
    }
    if (_transportOwner != null && !identical(_transportOwner, owner)) {
      _clearLatestCommands();
      _failPending(
        StateError('The VrmController was attached to another VrmView.'),
      );
    }
    _transportOwner = owner;
    _runJavaScript = runJavaScript;
    _reloadRuntime = reloadRuntime;
    _runtimeReady = runtimeReady;
  }

  void detachTransport(Object owner) {
    if (!identical(_transportOwner, owner)) {
      return;
    }
    _transportOwner = null;
    _runJavaScript = null;
    _reloadRuntime = null;
    _runtimeReady = false;
    _clearLatestCommands();
    _failPending(
      StateError('VrmView was detached before a command completed.'),
    );
  }

  void handleJsMessage(String message) {
    if (_disposed) {
      return;
    }

    try {
      final Object? decodedValue = jsonDecode(message);
      if (decodedValue is! Map<String, dynamic>) {
        throw const FormatException('Bridge message must be a JSON object.');
      }
      if (decodedValue['type'] == 'response') {
        _handleResponse(decodedValue);
        return;
      }
      if (decodedValue['type'] == 'event') {
        _handleEvent(decodedValue);
        return;
      }
      throw const FormatException('Unknown VRM bridge message type.');
    } on Object catch (error, stackTrace) {
      debugPrint('Invalid VRM runtime message: $error\n$stackTrace');
    }
  }

  void _handleResponse(Map<String, dynamic> envelope) {
    if (envelope['version'] != vrmProtocolVersion) {
      throw FormatException(
        'Unsupported VRM protocol version: ${envelope['version']}.',
      );
    }
    final id = envelope['id'];
    if (id is! String) {
      throw const FormatException('Response id is missing.');
    }
    final pending = _pending.remove(id);
    if (pending == null) {
      if (_ignoredResponseIds.remove(id)) {
        return;
      }
      debugPrint('Ignoring response for unknown VRM command: $id');
      return;
    }
    pending.timer.cancel();

    if (envelope['ok'] == true) {
      pending.completer.complete(envelope['result']);
      return;
    }

    final rawError = envelope['error'];
    final error = rawError is Map<String, dynamic>
        ? rawError
        : const <String, dynamic>{};
    pending.completer.completeError(
      VrmRuntimeException(
        code: error['code'] as String? ?? 'runtimeError',
        message: error['message'] as String? ?? 'VRM runtime command failed.',
        details: error['details'],
      ),
    );
  }

  void _handleEvent(Map<String, dynamic> decoded) {
    final event = decodeVrmRuntimeEventEnvelope(decoded);
    if (event case VrmStateChangedEvent(state: 'initialized')) {
      _runtimeReady = true;
    }
    _eventController.add(event);
  }

  Future<void> sendCommand(
    VrmProtocolCommand action, [
    Map<String, dynamic>? payload,
  ]) async {
    await requestCommand(action, payload);
  }

  /// Sends realtime state with one in-flight command per channel.
  ///
  /// While a command is awaiting its WebView response, repeated updates replace
  /// the queued value instead of growing the pending-command map.
  void sendLatestCommand({
    required String channel,
    required VrmProtocolCommand action,
    required Map<String, dynamic> payload,
  }) {
    if (_disposed) {
      throw StateError('VrmController has already been disposed.');
    }
    if (!_runtimeReady) return;

    final dispatcher = _latestDispatchers.putIfAbsent(
      channel,
      () => LatestValueDispatcher<Map<String, dynamic>>(
        dispatch: (value) => sendCommand(action, value),
        onError: reportAsyncError,
      ),
    );
    dispatcher.add(Map<String, dynamic>.unmodifiable(payload));
  }

  void clearLatestCommand(String channel) {
    _latestDispatchers[channel]?.clear();
  }

  Future<void> reloadRuntime() async {
    final reload = _reloadRuntime;
    if (reload == null) {
      throw StateError('VrmView is not attached to this controller.');
    }
    markRuntimeUnavailable(StateError('VRM runtime is reloading.'));
    await reload();
  }

  void markRuntimeUnavailable(Object error) {
    _runtimeReady = false;
    _clearLatestCommands();
    _failPending(error);
  }

  // Keep this method synchronous until the response Future is returned. A
  // fast WebView error response can otherwise complete the pending command
  // before the caller has any opportunity to attach an error handler.
  Future<Object?> requestCommand(
    VrmProtocolCommand action, [
    Map<String, dynamic>? payload,
  ]) {
    final runner = _runJavaScript;
    if (runner == null) {
      throw StateError('VrmView is not attached to this controller.');
    }
    if (!_runtimeReady) {
      throw StateError(
        'VRM runtime is not ready. Wait for VrmController.waitUntilReady().',
      );
    }

    final id = '${DateTime.now().microsecondsSinceEpoch}-${_nextCommandId++}';
    final completer = Completer<Object?>();
    final timer = Timer(_commandTimeout, () {
      final pending = _pending.remove(id);
      pending?.completer.completeError(
        TimeoutException(
          'VRM command "${action.name}" did not complete.',
          _commandTimeout,
        ),
      );
    });
    _pending[id] = _PendingCommand(completer: completer, timer: timer);

    final command = jsonEncode(<String, Object?>{
      'version': vrmProtocolVersion,
      'id': id,
      'type': 'command',
      'action': action.name,
      'payload': payload ?? const <String, dynamic>{},
    });

    void failDispatch(Object error, StackTrace stackTrace) {
      final pending = _pending.remove(id);
      pending?.timer.cancel();
      pending?.completer.completeError(error, stackTrace);
    }

    try {
      final dispatch = runner(
        'window.flutterVrmDispatch(${jsonEncode(command)});',
      );
      unawaited(
        dispatch.then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            failDispatch(error, stackTrace);
          },
        ),
      );
    } on Object catch (error, stackTrace) {
      failDispatch(error, stackTrace);
    }

    return completer.future;
  }

  void reportAsyncError(Object error, StackTrace stackTrace) {
    if (!_disposed) {
      _eventController.add(VrmErrorEvent(message: error.toString()));
      debugPrint('Asynchronous VRM command failed: $error\n$stackTrace');
    }
  }

  void _failPending(Object error) {
    _ignoredResponseIds.addAll(_pending.keys);
    while (_ignoredResponseIds.length > _maxIgnoredResponseIds) {
      _ignoredResponseIds.remove(_ignoredResponseIds.first);
    }
    final pendingCommands = _pending.values.toList(growable: false);
    _pending.clear();
    for (final pending in pendingCommands) {
      pending.timer.cancel();
      pending.completer.completeError(error);
    }
  }

  void _clearLatestCommands() {
    for (final dispatcher in _latestDispatchers.values) {
      dispatcher.clear();
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _transportOwner = null;
    _runJavaScript = null;
    _reloadRuntime = null;
    _runtimeReady = false;
    for (final dispatcher in _latestDispatchers.values) {
      dispatcher.close();
    }
    _latestDispatchers.clear();
    _failPending(StateError('VrmController was disposed.'));
    await _eventController.close();
  }
}

final class _PendingCommand {
  const _PendingCommand({required this.completer, required this.timer});

  final Completer<Object?> completer;
  final Timer timer;
}
