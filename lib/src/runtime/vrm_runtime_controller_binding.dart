import 'dart:async';

import '../content/vrm_content_host.dart';
import '../models/vrm_events.dart';
import '../models/vrm_model_report.dart';
import '../platform/vrm_webview_adapter.dart';

typedef VrmRuntimeTransportAttach =
    void Function({
      required Object owner,
      required Future<void> Function(String source) runJavaScript,
      required Future<void> Function() reloadRuntime,
      required bool runtimeReady,
    });

/// Controller-facing operations needed by one runtime view session.
///
/// The endpoint keeps private bridge and controller internals out of the
/// coordinator. It is internal package infrastructure and is not exported by
/// the public package library.
final class VrmRuntimeControllerEndpoint {
  const VrmRuntimeControllerEndpoint({
    required this.identity,
    required this.states,
    required this.errors,
    required this.modelLoadedEvents,
    required this.modelReports,
    required this.modelUnloadedEvents,
    required this.readModelLoaded,
    required this.restoreModelLoaded,
    required this.handleRuntimeMessage,
    required this.attachTransport,
    required this.detachTransport,
    required this.attachContentHost,
    required this.detachContentHost,
    required this.attachHostResourceMonitoring,
    required this.detachHostResourceMonitoring,
    required this.recordHostMemoryPressure,
    required this.reportAsyncError,
  });

  final Object identity;
  final Stream<VrmStateChangedEvent> states;
  final Stream<VrmErrorEvent> errors;
  final Stream<VrmModelLoadedEvent> modelLoadedEvents;
  final Stream<VrmModelReportEvent> modelReports;
  final Stream<VrmModelUnloadedEvent> modelUnloadedEvents;
  final bool Function() readModelLoaded;
  final void Function(bool loaded) restoreModelLoaded;
  final void Function(String message) handleRuntimeMessage;
  final VrmRuntimeTransportAttach attachTransport;
  final void Function(Object owner) detachTransport;
  final void Function(VrmContentHost contentHost) attachContentHost;
  final void Function(VrmContentHost contentHost) detachContentHost;
  final void Function() attachHostResourceMonitoring;
  final void Function() detachHostResourceMonitoring;
  final void Function() recordHostMemoryPressure;
  final void Function(Object error, StackTrace stackTrace) reportAsyncError;
}

/// Owns controller/WebView subscriptions and resource attachment for a session.
final class VrmRuntimeControllerBinding {
  factory VrmRuntimeControllerBinding({
    required VrmRuntimeControllerEndpoint endpoint,
    required VrmWebViewAdapter webView,
    required Future<void> Function() reloadRuntime,
    required bool Function() isRuntimeReady,
    required Future<void> Function() onRuntimeInitialized,
    required void Function(String message) onControllerError,
    required Future<void> Function() onModelLoaded,
    required Future<void> Function(VrmModelReport report) onModelReport,
    required Future<void> Function() onModelUnloaded,
    required void Function(Object error, StackTrace stackTrace)
    onBridgeMessageError,
    required void Function(String message) onRuntimeResourceError,
  }) => VrmRuntimeControllerBinding._(
    endpoint,
    webView,
    reloadRuntime,
    isRuntimeReady,
    onRuntimeInitialized,
    onControllerError,
    onModelLoaded,
    onModelReport,
    onModelUnloaded,
    onBridgeMessageError,
    onRuntimeResourceError,
  );

  VrmRuntimeControllerBinding._(
    this._endpoint,
    this._webView,
    this._reloadRuntime,
    this._isRuntimeReady,
    this._onRuntimeInitialized,
    this._onControllerError,
    this._onModelLoaded,
    this._onModelReport,
    this._onModelUnloaded,
    void Function(Object error, StackTrace stackTrace) onBridgeMessageError,
    void Function(String message) onRuntimeResourceError,
  ) {
    _endpoint.attachHostResourceMonitoring();
    _bindEndpoint(_endpoint);
    _webViewSubscriptions
      ..add(
        _webView.messages.listen(
          (message) {
            if (!_disposed) {
              _handleRuntimeMessage(message);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!_disposed) {
              onBridgeMessageError(error, stackTrace);
            }
          },
        ),
      )
      ..add(
        _webView.errors.listen((message) {
          if (!_disposed) {
            onRuntimeResourceError(message);
          }
        }),
      );
  }

  final VrmWebViewAdapter _webView;
  final Future<void> Function() _reloadRuntime;
  final bool Function() _isRuntimeReady;
  final Future<void> Function() _onRuntimeInitialized;
  final void Function(String message) _onControllerError;
  final Future<void> Function() _onModelLoaded;
  final Future<void> Function(VrmModelReport report) _onModelReport;
  final Future<void> Function() _onModelUnloaded;
  final List<StreamSubscription<dynamic>> _controllerSubscriptions = [];
  final List<StreamSubscription<dynamic>> _webViewSubscriptions = [];

  VrmRuntimeControllerEndpoint _endpoint;
  VrmContentHost? _contentHost;
  Future<void>? _disposeFuture;
  bool _transportAttached = false;
  bool _disposed = false;

  bool get isTransportAttached => _transportAttached && !_disposed;
  VrmContentHost? get contentHost => _contentHost;

  void attachTransport() {
    _ensureActive();
    if (_transportAttached) return;
    _attachCurrentTransport();
    _transportAttached = true;
  }

  void attachContentHost(VrmContentHost contentHost) {
    _ensureActive();
    final current = _contentHost;
    if (identical(current, contentHost)) return;
    if (current != null) {
      throw StateError('A runtime content host is already attached.');
    }
    _contentHost = contentHost;
    _endpoint.attachContentHost(contentHost);
  }

  void rebind(VrmRuntimeControllerEndpoint endpoint) {
    _ensureActive();
    if (identical(_endpoint.identity, endpoint.identity)) return;

    final previous = _endpoint;
    final hadModel = previous.readModelLoaded();
    previous.detachHostResourceMonitoring();
    if (_transportAttached) {
      previous.detachTransport(_webView);
    }
    final contentHost = _contentHost;
    if (contentHost != null) {
      previous.detachContentHost(contentHost);
    }
    _cancelControllerSubscriptions();

    _endpoint = endpoint;
    endpoint.attachHostResourceMonitoring();
    if (contentHost != null) {
      endpoint.attachContentHost(contentHost);
    }
    endpoint.restoreModelLoaded(hadModel);
    _bindEndpoint(endpoint);
    if (_transportAttached) {
      _attachCurrentTransport();
    }
  }

  void recordHostMemoryPressure() {
    if (!_disposed) {
      _endpoint.recordHostMemoryPressure();
    }
  }

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;

    final endpoint = _endpoint;
    endpoint.detachHostResourceMonitoring();
    if (_transportAttached) {
      _transportAttached = false;
      endpoint.detachTransport(_webView);
    }

    final contentHost = _contentHost;
    _contentHost = null;
    if (contentHost != null) {
      endpoint.detachContentHost(contentHost);
    }

    final subscriptions = <StreamSubscription<dynamic>>[
      ..._controllerSubscriptions,
      ..._webViewSubscriptions,
    ];
    _controllerSubscriptions.clear();
    _webViewSubscriptions.clear();
    await Future.wait<void>(
      subscriptions.map((subscription) => subscription.cancel()),
    );
    await contentHost?.close();
  }

  void _bindEndpoint(VrmRuntimeControllerEndpoint endpoint) {
    _controllerSubscriptions
      ..add(
        endpoint.states.listen((event) {
          if (_isCurrent(endpoint) && event.state == 'initialized') {
            _dispatchAsync(_onRuntimeInitialized, endpoint);
          }
        }),
      )
      ..add(
        endpoint.errors.listen((event) {
          if (_isCurrent(endpoint)) {
            _onControllerError(event.message);
          }
        }),
      )
      ..add(
        endpoint.modelLoadedEvents.listen((_) {
          if (_isCurrent(endpoint)) {
            _dispatchAsync(_onModelLoaded, endpoint);
          }
        }),
      )
      ..add(
        endpoint.modelReports.listen((event) {
          if (_isCurrent(endpoint)) {
            _dispatchAsync(() => _onModelReport(event.report), endpoint);
          }
        }),
      )
      ..add(
        endpoint.modelUnloadedEvents.listen((_) {
          if (_isCurrent(endpoint)) {
            _dispatchAsync(_onModelUnloaded, endpoint);
          }
        }),
      );
  }

  void _handleRuntimeMessage(String message) {
    if (!_disposed) {
      _endpoint.handleRuntimeMessage(message);
    }
  }

  void _attachCurrentTransport() {
    _endpoint.attachTransport(
      owner: _webView,
      runJavaScript: _webView.runJavaScript,
      reloadRuntime: _reloadRuntime,
      runtimeReady: _isRuntimeReady(),
    );
  }

  void _dispatchAsync(
    Future<void> Function() action,
    VrmRuntimeControllerEndpoint endpoint,
  ) {
    unawaited(
      Future<void>.sync(action).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        if (_isCurrent(endpoint)) {
          endpoint.reportAsyncError(error, stackTrace);
        }
      }),
    );
  }

  bool _isCurrent(VrmRuntimeControllerEndpoint endpoint) =>
      !_disposed && identical(_endpoint, endpoint);

  void _cancelControllerSubscriptions() {
    for (final subscription in _controllerSubscriptions) {
      unawaited(subscription.cancel());
    }
    _controllerSubscriptions.clear();
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('Runtime controller binding has already been disposed.');
    }
  }
}
