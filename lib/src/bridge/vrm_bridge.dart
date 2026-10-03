import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/vrm_events.dart';
import '../models/vrm_exception.dart';
import '../runtime/vrm_cleanup.dart';
import '../runtime/vrm_runtime_transition.dart';
import 'latest_value_dispatcher.dart';
import 'vrm_event_decoder.dart';
import 'vrm_protocol_contract.dart';

typedef VrmJavaScriptRunner = Future<void> Function(String source);
typedef VrmRuntimeReloader = Future<void> Function();

/// Internal protocol-v3 transport used by [VrmController].
///
/// The class is intentionally not exported from the package public library.
final class VrmBridge {
  VrmBridge({Duration commandTimeout = const Duration(minutes: 2)})
    : _commandTimeout = commandTimeout {
    if (commandTimeout.isNegative || commandTimeout == Duration.zero) {
      throw ArgumentError.value(
        commandTimeout,
        'commandTimeout',
        'Must be greater than zero.',
      );
    }
  }

  static const int _maxIgnoredResponseIds = 256;

  final Duration _commandTimeout;
  final StreamController<VrmEvent> _eventController =
      StreamController<VrmEvent>.broadcast();
  final Map<String, _PendingCommand> _pending = <String, _PendingCommand>{};
  final Set<String> _ignoredResponseIds = <String>{};
  final Map<String, LatestValueDispatcher<Map<String, dynamic>>>
  _latestDispatchers = <String, LatestValueDispatcher<Map<String, dynamic>>>{};
  final Map<Object, Set<Future<void>>> _transportDispatches =
      HashMap<Object, Set<Future<void>>>.identity();

  Object? _transportOwner;
  VrmJavaScriptRunner? _runJavaScript;
  VrmRuntimeReloader? _reloadRuntime;
  int _nextCommandId = 0;
  bool _disposed = false;
  bool _runtimeReady = false;
  Future<void>? _disposeFuture;

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

  Future<void> detachTransport(Object owner) {
    if (identical(_transportOwner, owner)) {
      _transportOwner = null;
      _runJavaScript = null;
      _reloadRuntime = null;
      _runtimeReady = false;
      _clearLatestCommands();
      _failPending(
        StateError('VrmView was detached before a command completed.'),
      );
    }
    return _waitForTransportDispatches(owner);
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
      switch (decodedValue['type']) {
        case 'response':
          _handleResponse(decodedValue);
        case 'event':
          _handleEvent(decodedValue);
        default:
          throw const FormatException('Unknown VRM bridge message type.');
      }
    } on Object catch (error, stackTrace) {
      reportAsyncError(error, stackTrace);
    }
  }

  void _handleResponse(Map<String, dynamic> envelope) {
    final rawId = envelope['id'];
    if (rawId is! String || rawId.isEmpty) {
      throw const FormatException('Response id is missing.');
    }

    final pending = _pending.remove(rawId);
    if (pending == null) {
      if (_ignoredResponseIds.remove(rawId)) {
        return;
      }
      debugPrint('Ignoring response for unknown VRM command: $rawId');
      return;
    }
    pending.timer.cancel();

    try {
      if (envelope['version'] != vrmProtocolVersion) {
        throw FormatException(
          'Unsupported VRM protocol version: ${envelope['version']}.',
        );
      }
      final ok = envelope['ok'];
      if (ok is! bool) {
        throw const FormatException('Response ok flag is missing.');
      }
      if (ok) {
        pending.completer.complete(envelope['result']);
        return;
      }

      final rawError = envelope['error'];
      if (rawError is! Map<String, dynamic>) {
        throw const FormatException('Response error is missing.');
      }
      final code = rawError['code'];
      final message = rawError['message'];
      if (code is! String || code.isEmpty || message is! String) {
        throw const FormatException('Response error payload is malformed.');
      }
      pending.completer.completeError(
        VrmRuntimeException(
          code: code,
          message: message,
          details: rawError['details'],
        ),
      );
    } on Object catch (error, stackTrace) {
      pending.completer.completeError(error, stackTrace);
    }
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
    final transportOwner = _transportOwner;
    if (reload == null || transportOwner == null) {
      throw StateError('VrmView is not attached to this controller.');
    }
    markRuntimeUnavailable(vrmRuntimeTransitionCancellation);
    final dispatch = Future<void>.sync(reload);
    await _trackTransportDispatch(transportOwner, dispatch);
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
    final transportOwner = _transportOwner;
    if (runner == null || transportOwner == null) {
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
      if (pending == null) return;
      _rememberIgnoredResponseId(id);
      pending.completer.completeError(
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
      if (pending == null) return;
      pending.timer.cancel();
      _rememberIgnoredResponseId(id);
      pending.completer.completeError(error, stackTrace);
    }

    final dispatch =
        Future<void>.sync(
          () => runner('window.flutterVrmDispatch(${jsonEncode(command)});'),
        ).then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            failDispatch(error, stackTrace);
          },
        );
    unawaited(_trackTransportDispatch(transportOwner, dispatch));

    return completer.future;
  }

  void reportAsyncError(Object error, StackTrace stackTrace) {
    if (!_disposed && !isExpectedVrmRuntimeCancellation(error)) {
      _eventController.add(VrmErrorEvent(message: error.toString()));
      debugPrint('Asynchronous VRM command failed: $error\n$stackTrace');
    }
  }

  void _failPending(Object error) {
    final pendingEntries = _pending.entries.toList(growable: false);
    _pending.clear();
    for (final entry in pendingEntries) {
      _rememberIgnoredResponseId(entry.key);
      entry.value.timer.cancel();
      entry.value.completer.completeError(error);
    }
  }

  void _rememberIgnoredResponseId(String id) {
    _ignoredResponseIds.add(id);
    while (_ignoredResponseIds.length > _maxIgnoredResponseIds) {
      _ignoredResponseIds.remove(_ignoredResponseIds.first);
    }
  }

  void _clearLatestCommands() {
    for (final dispatcher in _latestDispatchers.values) {
      dispatcher.clear();
    }
  }

  Future<void> _trackTransportDispatch(Object owner, Future<void> dispatch) {
    final tasks = _transportDispatches.putIfAbsent(
      owner,
      () => <Future<void>>{},
    );
    late final Future<void> tracked;
    tracked = dispatch.whenComplete(() {
      tasks.remove(tracked);
      if (tasks.isEmpty) {
        _transportDispatches.remove(owner);
      }
    });
    tasks.add(tracked);
    return tracked;
  }

  Future<void> _waitForTransportDispatches(Object owner) async {
    while (true) {
      final tasks = _transportDispatches[owner];
      if (tasks == null || tasks.isEmpty) return;
      await Future.wait<void>(List<Future<void>>.of(tasks));
    }
  }

  Future<void> _waitForAllTransportDispatches() async {
    while (_transportDispatches.isNotEmpty) {
      final tasks = _transportDispatches.values
          .expand((ownerTasks) => ownerTasks)
          .toList(growable: false);
      if (tasks.isEmpty) return;
      await Future.wait<void>(tasks);
    }
  }

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
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
    await runVrmCleanupPhases([
      _waitForAllTransportDispatches,
      _eventController.close,
    ]);
  }
}

final class _PendingCommand {
  const _PendingCommand({required this.completer, required this.timer});

  final Completer<Object?> completer;
  final Timer timer;
}
