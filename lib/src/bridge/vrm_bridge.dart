part of '../vrm_runtime.dart';

typedef VrmJavaScriptRunner = Future<void> Function(String source);
typedef VrmRuntimeReloader = Future<void> Function();

final class _VrmBridge {
  static const int _protocolVersion = 1;
  static const Duration _commandTimeout = Duration(minutes: 2);
  final StreamController<VrmEvent> _eventController =
      StreamController<VrmEvent>.broadcast();
  final Map<String, _PendingCommand> _pending = <String, _PendingCommand>{};

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

  void _handleEvent(Map<String, dynamic> decoded) {
    if (decoded['version'] != _protocolVersion) {
      throw FormatException(
        'Unsupported VRM protocol version: ${decoded['version']}.',
      );
    }
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
      case 'onModelReport':
        _eventController.add(
          VrmModelReportEvent(report: VrmModelReport.fromJson(payload)),
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
        if (payload['state'] == 'initialized') {
          _runtimeReady = true;
        }
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
      case 'onPerformance':
        _eventController.add(
          VrmPerformanceEvent(
            snapshot: VrmPerformanceSnapshot.fromJson(payload),
          ),
        );
      case 'onWebGLContextChanged':
        final state = switch (payload['state']) {
          'lost' => VrmWebGlContextState.lost,
          'restored' => VrmWebGlContextState.restored,
          _ => throw const FormatException('Unknown WebGL context state.'),
        };
        _eventController.add(VrmWebGlContextEvent(state: state));
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
    _failPending(error);
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
    _reloadRuntime = null;
    _runtimeReady = false;
    _failPending(StateError('VrmController was disposed.'));
    await _eventController.close();
  }
}

final class _PendingCommand {
  const _PendingCommand({required this.completer, required this.timer});

  final Completer<Object?> completer;
  final Timer timer;
}
