part of '../vrm_runtime.dart';

typedef VrmJavaScriptRunner = Future<void> Function(String source);

final class _VrmBridge {
  static const int _protocolVersion = 1;
  static const Duration _commandTimeout = Duration(minutes: 2);
  final StreamController<VrmEvent> _eventController =
      StreamController<VrmEvent>.broadcast();
  final Map<String, _PendingCommand> _pending = <String, _PendingCommand>{};

  Object? _transportOwner;
  VrmJavaScriptRunner? _runJavaScript;
  int _nextCommandId = 0;
  bool _disposed = false;

  Stream<VrmEvent> get eventStream => _eventController.stream;

  void attachTransport({
    required Object owner,
    required VrmJavaScriptRunner runJavaScript,
  }) {
    if (_disposed) {
      throw StateError('VrmController has already been disposed.');
    }
    if (_transportOwner != null && !identical(_transportOwner, owner)) {
      _failPending(
        StateError('The VrmController was attached to another VrmView.'),
      );
    }
    _transportOwner = owner;
    _runJavaScript = runJavaScript;
  }

  void detachTransport(Object owner) {
    if (!identical(_transportOwner, owner)) {
      return;
    }
    _transportOwner = null;
    _runJavaScript = null;
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
      _handleLegacyEvent(decodedValue);
    } on Object catch (error, stackTrace) {
      debugPrint('Invalid VRM runtime message: $error\n$stackTrace');
    }
  }

  void _handleResponse(Map<String, dynamic> envelope) {
    if (envelope['version'] != _protocolVersion) {
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

  void _handleLegacyEvent(Map<String, dynamic> decoded) {
    final event = decoded['event'];
    if (event is! String) {
      throw const FormatException('Bridge event name is missing.');
    }
    final rawPayload = decoded['payload'];
    final payload = rawPayload is Map<String, dynamic>
        ? rawPayload
        : const <String, dynamic>{};

    switch (event) {
      case 'onModelLoaded':
        _eventController.add(
          VrmModelLoadedEvent(
            name: payload['name'] as String? ?? 'VRM Model',
            version: payload['version'] as String? ?? '1.0',
          ),
        );
      case 'onModelLoadProgress':
        _eventController.add(
          VrmModelLoadProgressEvent(
            percent: (payload['percent'] as num?)?.toInt() ?? 0,
            loaded: (payload['loaded'] as num?)?.toInt() ?? 0,
            total: (payload['total'] as num?)?.toInt() ?? 0,
          ),
        );
      case 'onModelUnloaded':
        _eventController.add(VrmModelUnloadedEvent());
      case 'onAnimationStarted':
        _eventController.add(
          VrmAnimationStartedEvent(
            name: payload['name'] as String? ?? 'Animation',
          ),
        );
      case 'onAnimationFinished':
        _eventController.add(
          VrmAnimationFinishedEvent(
            name: payload['name'] as String? ?? 'Animation',
          ),
        );
      case 'onExpressionChanged':
        _eventController.add(
          VrmExpressionChangedEvent(
            expression: VrmExpression.fromString(
              payload['expression'] as String? ?? '',
            ),
            layer: ExpressionLayer.fromString(
              payload['layer'] as String? ?? '',
            ),
          ),
        );
      case 'onSpeechFinished':
        _eventController.add(VrmSpeechFinishedEvent());
      case 'onError':
        _eventController.add(
          VrmErrorEvent(
            message: payload['message'] as String? ?? 'Unknown WebGL error',
          ),
        );
      case 'onStateChanged':
        _eventController.add(
          VrmStateChangedEvent(state: payload['state'] as String? ?? ''),
        );
      case 'onCameraChanged':
        _eventController.add(
          VrmCameraChangedEvent(
            x: (payload['x'] as num?)?.toDouble(),
            y: (payload['y'] as num?)?.toDouble(),
            zoom: (payload['zoom'] as num?)?.toDouble(),
          ),
        );
      case 'onTap':
        _eventController.add(
          VrmTapEvent(
            x: (payload['x'] as num?)?.toDouble() ?? 0,
            y: (payload['y'] as num?)?.toDouble() ?? 0,
          ),
        );
      default:
        debugPrint('Unknown VRM runtime event: $event');
    }
  }

  Future<void> sendCommand(
    String action, [
    Map<String, dynamic>? payload,
  ]) async {
    await requestCommand(action, payload);
  }

  Future<Object?> requestCommand(
    String action, [
    Map<String, dynamic>? payload,
  ]) async {
    final runner = _runJavaScript;
    if (runner == null) {
      throw StateError('VrmView is not attached to this controller.');
    }

    final id = '${DateTime.now().microsecondsSinceEpoch}-${_nextCommandId++}';
    final completer = Completer<Object?>();
    final timer = Timer(_commandTimeout, () {
      final pending = _pending.remove(id);
      pending?.completer.completeError(
        TimeoutException(
          'VRM command "$action" did not complete.',
          _commandTimeout,
        ),
      );
    });
    _pending[id] = _PendingCommand(completer: completer, timer: timer);

    final command = jsonEncode(<String, Object?>{
      'version': _protocolVersion,
      'id': id,
      'type': 'command',
      'action': action,
      'payload': payload ?? const <String, dynamic>{},
    });

    try {
      await runner('window.flutterVrmDispatch(${jsonEncode(command)});');
    } on Object catch (error, stackTrace) {
      final pending = _pending.remove(id);
      pending?.timer.cancel();
      pending?.completer.completeError(error, stackTrace);
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
    final pendingCommands = _pending.values.toList(growable: false);
    _pending.clear();
    for (final pending in pendingCommands) {
      pending.timer.cancel();
      pending.completer.completeError(error);
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _transportOwner = null;
    _runJavaScript = null;
    _failPending(StateError('VrmController was disposed.'));
    await _eventController.close();
  }
}

final class _PendingCommand {
  const _PendingCommand({required this.completer, required this.timer});

  final Completer<Object?> completer;
  final Timer timer;
}
