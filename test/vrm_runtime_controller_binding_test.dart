import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/src/content/vrm_content_host.dart';
import 'package:flutter_three_vrm/src/models/vrm_events.dart';
import 'package:flutter_three_vrm/src/platform/vrm_webview_adapter.dart';
import 'package:flutter_three_vrm/src/runtime/vrm_runtime_controller_binding.dart';

void main() {
  group('VrmRuntimeControllerBinding', () {
    test(
      'routes WebView and controller events through the active endpoint',
      () async {
        final webView = _FakeWebViewAdapter();
        final endpoint = _EndpointHarness();
        final initialized = <String>[];
        final controllerErrors = <String>[];
        final resourceErrors = <String>[];
        final bridgeErrors = <Object>[];

        final binding = VrmRuntimeControllerBinding(
          endpoint: endpoint.endpoint,
          webView: webView,
          reloadRuntime: () async {},
          isRuntimeReady: () => true,
          onRuntimeInitialized: () async => initialized.add('initialized'),
          onControllerError: controllerErrors.add,
          onModelLoaded: () => throw StateError('restore failed'),
          onModelReport: (_) async {},
          onModelUnloaded: () async {},
          onBridgeMessageError: (error, _) => bridgeErrors.add(error),
          onRuntimeResourceError: resourceErrors.add,
        );

        endpoint.states.add(VrmStateChangedEvent(state: 'initialized'));
        endpoint.errors.add(VrmErrorEvent(message: 'controller failed'));
        endpoint.modelLoadedEvents.add(
          VrmModelLoadedEvent(name: 'avatar', version: '1.0'),
        );
        webView.messageController.add('runtime message');
        webView.errorController.add('resource failed');
        webView.messageController.addError(StateError('bridge failed'));
        await Future<void>.delayed(Duration.zero);

        expect(endpoint.monitorAttachCount, 1);
        expect(initialized, <String>['initialized']);
        expect(controllerErrors, <String>['controller failed']);
        expect(endpoint.runtimeMessages, <String>['runtime message']);
        expect(resourceErrors, <String>['resource failed']);
        expect(bridgeErrors.single, isA<StateError>());
        expect(endpoint.reportedErrors.single, isA<StateError>());

        await binding.dispose();
        await endpoint.close();
        await webView.close();
      },
    );

    test(
      'rebind transfers runtime ownership to the replacement controller',
      () async {
        final webView = _FakeWebViewAdapter();
        final first = _EndpointHarness()..modelLoaded = true;
        final second = _EndpointHarness();
        final contentHost = _FakeContentHost();
        var initializedCount = 0;

        final binding = VrmRuntimeControllerBinding(
          endpoint: first.endpoint,
          webView: webView,
          reloadRuntime: () async {},
          isRuntimeReady: () => true,
          onRuntimeInitialized: () async => initializedCount += 1,
          onControllerError: (_) {},
          onModelLoaded: () async {},
          onModelReport: (_) async {},
          onModelUnloaded: () async {},
          onBridgeMessageError: (_, _) {},
          onRuntimeResourceError: (_) {},
        );
        binding.attachTransport();
        binding.attachContentHost(contentHost);

        binding.rebind(second.endpoint);
        first.states.add(VrmStateChangedEvent(state: 'initialized'));
        second.states.add(VrmStateChangedEvent(state: 'initialized'));
        webView.messageController.add('after rebind');
        await Future<void>.delayed(Duration.zero);

        expect(first.monitorDetachCount, 1);
        expect(first.transportDetachCount, 1);
        expect(first.contentHostDetachCount, 1);
        expect(second.monitorAttachCount, 1);
        expect(second.transportAttachCount, 1);
        expect(second.contentHostAttachCount, 1);
        expect(second.restoredModelLoaded, isTrue);
        expect(first.runtimeMessages, isEmpty);
        expect(second.runtimeMessages, <String>['after rebind']);
        expect(initializedCount, 1);

        await binding.dispose();
        expect(second.monitorDetachCount, 1);
        expect(second.transportDetachCount, 1);
        expect(second.contentHostDetachCount, 1);
        expect(contentHost.closeCount, 1);

        await first.close();
        await second.close();
        await webView.close();
      },
    );

    test('dispose waits for an async callback started before rebind', () async {
      final callbackStarted = Completer<void>();
      final callbackBarrier = Completer<void>();
      final failure = StateError('stale callback failed');
      final webView = _FakeWebViewAdapter();
      final first = _EndpointHarness();
      final second = _EndpointHarness();
      final host = _FakeContentHost();
      final binding = VrmRuntimeControllerBinding(
        endpoint: first.endpoint,
        webView: webView,
        reloadRuntime: () async {},
        isRuntimeReady: () => true,
        onRuntimeInitialized: () async {},
        onControllerError: (_) {},
        onModelLoaded: () async {
          callbackStarted.complete();
          await callbackBarrier.future;
          throw failure;
        },
        onModelReport: (_) async {},
        onModelUnloaded: () async {},
        onBridgeMessageError: (_, _) {},
        onRuntimeResourceError: (_) {},
      );
      binding.attachContentHost(host);
      addTearDown(() async {
        if (!callbackBarrier.isCompleted) callbackBarrier.complete();
        await binding.dispose();
        await first.close();
        await second.close();
        await webView.close();
      });

      first.modelLoadedEvents.add(
        VrmModelLoadedEvent(name: 'avatar', version: '1.0'),
      );
      await callbackStarted.future;
      binding.rebind(second.endpoint);
      final disposal = binding.dispose();
      var disposalCompleted = false;
      unawaited(disposal.then<void>((_) => disposalCompleted = true));
      await Future<void>.delayed(Duration.zero);

      expect(disposalCompleted, isFalse);
      expect(host.closeCount, 0);

      callbackBarrier.complete();
      await disposal;
      expect(disposalCompleted, isTrue);
      expect(host.closeCount, 1);
      expect(first.reportedErrors, isEmpty);
      expect(second.reportedErrors, isEmpty);
    });

    test('dispose waits for subscription cleanup started by rebind', () async {
      final cancellationBarrier = Completer<void>();
      final webView = _FakeWebViewAdapter();
      final first = _EndpointHarness(
        cancellationBarrier: cancellationBarrier.future,
      );
      final second = _EndpointHarness();
      final binding = VrmRuntimeControllerBinding(
        endpoint: first.endpoint,
        webView: webView,
        reloadRuntime: () async {},
        isRuntimeReady: () => true,
        onRuntimeInitialized: () async {},
        onControllerError: (_) {},
        onModelLoaded: () async {},
        onModelReport: (_) async {},
        onModelUnloaded: () async {},
        onBridgeMessageError: (_, _) {},
        onRuntimeResourceError: (_) {},
      );
      addTearDown(() async {
        if (!cancellationBarrier.isCompleted) cancellationBarrier.complete();
        await binding.dispose();
        await first.close();
        await second.close();
        await webView.close();
      });

      binding.rebind(second.endpoint);
      final disposal = binding.dispose();
      var disposalCompleted = false;
      unawaited(disposal.then<void>((_) => disposalCompleted = true));
      await Future<void>.delayed(Duration.zero);

      expect(first.cancellationCount, 5);
      expect(disposalCompleted, isFalse);

      cancellationBarrier.complete();
      await disposal;
      expect(disposalCompleted, isTrue);
    });

    test(
      'reports retired cancellation failures and still closes the host',
      () async {
        final cancellationBarrier = Completer<void>();
        final failure = StateError('retired cancellation failed');
        final webView = _FakeWebViewAdapter();
        final first = _EndpointHarness(
          cancellationBarrier: cancellationBarrier.future,
        );
        final second = _EndpointHarness();
        final host = _FakeContentHost();
        final binding = VrmRuntimeControllerBinding(
          endpoint: first.endpoint,
          webView: webView,
          reloadRuntime: () async {},
          isRuntimeReady: () => true,
          onRuntimeInitialized: () async {},
          onControllerError: (_) {},
          onModelLoaded: () async {},
          onModelReport: (_) async {},
          onModelUnloaded: () async {},
          onBridgeMessageError: (_, _) {},
          onRuntimeResourceError: (_) {},
        );
        binding.attachContentHost(host);
        addTearDown(() async {
          if (!cancellationBarrier.isCompleted) cancellationBarrier.complete();
          await binding.dispose();
          await first.close();
          await second.close();
          await webView.close();
        });

        binding.rebind(second.endpoint);
        final disposal = binding.dispose();
        cancellationBarrier.completeError(failure);
        await disposal;

        expect(first.reportedErrors, <Object>[failure]);
        expect(host.closeCount, 1);
      },
    );

    test(
      'closes the host when current subscription cancellation fails',
      () async {
        final cancellationBarrier = Completer<void>();
        final failure = StateError('current cancellation failed');
        final webView = _FakeWebViewAdapter();
        final endpoint = _EndpointHarness(
          cancellationBarrier: cancellationBarrier.future,
        );
        final host = _FakeContentHost();
        final binding = VrmRuntimeControllerBinding(
          endpoint: endpoint.endpoint,
          webView: webView,
          reloadRuntime: () async {},
          isRuntimeReady: () => true,
          onRuntimeInitialized: () async {},
          onControllerError: (_) {},
          onModelLoaded: () async {},
          onModelReport: (_) async {},
          onModelUnloaded: () async {},
          onBridgeMessageError: (_, _) {},
          onRuntimeResourceError: (_) {},
        );
        binding.attachContentHost(host);
        addTearDown(() async {
          if (!cancellationBarrier.isCompleted) cancellationBarrier.complete();
          await endpoint.close();
          await webView.close();
        });

        final disposal = binding.dispose();
        cancellationBarrier.completeError(failure);

        await expectLater(disposal, throwsA(same(failure)));
        expect(endpoint.cancellationCount, 5);
        expect(host.closeCount, 1);
      },
    );

    test(
      'attempts every cancellation and closes the host after sync failure',
      () async {
        final cancellationFailure = StateError('synchronous cancel failed');
        final closeFailure = StateError('content host close failed');
        final webView = _FakeWebViewAdapter();
        final endpoint = _EndpointHarness(
          synchronousCancellationFailure: cancellationFailure,
        );
        final host = _FakeContentHost(closeFailure: closeFailure);
        final binding = VrmRuntimeControllerBinding(
          endpoint: endpoint.endpoint,
          webView: webView,
          reloadRuntime: () async {},
          isRuntimeReady: () => true,
          onRuntimeInitialized: () async {},
          onControllerError: (_) {},
          onModelLoaded: () async {},
          onModelReport: (_) async {},
          onModelUnloaded: () async {},
          onBridgeMessageError: (_, _) {},
          onRuntimeResourceError: (_) {},
        );
        binding.attachContentHost(host);
        addTearDown(() async {
          await endpoint.close();
          await webView.close();
        });

        await expectLater(
          binding.dispose(),
          throwsA(same(cancellationFailure)),
        );

        expect(endpoint.synchronousCancellationAttempts, 5);
        expect(host.closeCount, 1);
      },
    );

    test('dispose waits for transport cleanup retired by rebind', () async {
      final transportBarrier = Completer<void>();
      final webView = _FakeWebViewAdapter();
      final first = _EndpointHarness(
        transportDetachBarrier: transportBarrier.future,
      );
      final second = _EndpointHarness();
      final host = _FakeContentHost();
      final binding = VrmRuntimeControllerBinding(
        endpoint: first.endpoint,
        webView: webView,
        reloadRuntime: () async {},
        isRuntimeReady: () => true,
        onRuntimeInitialized: () async {},
        onControllerError: (_) {},
        onModelLoaded: () async {},
        onModelReport: (_) async {},
        onModelUnloaded: () async {},
        onBridgeMessageError: (_, _) {},
        onRuntimeResourceError: (_) {},
      );
      binding.attachTransport();
      binding.attachContentHost(host);
      addTearDown(() async {
        if (!transportBarrier.isCompleted) transportBarrier.complete();
        await binding.dispose();
        await first.close();
        await second.close();
        await webView.close();
      });

      binding.rebind(second.endpoint);
      final disposal = binding.dispose();
      var disposalCompleted = false;
      unawaited(disposal.then<void>((_) => disposalCompleted = true));
      await Future<void>.delayed(Duration.zero);
      expect(disposalCompleted, isFalse);
      expect(host.closeCount, 0);

      transportBarrier.complete();
      await disposal;
      expect(host.closeCount, 1);
    });

    test('dispose is idempotent and suppresses later messages', () async {
      final webView = _FakeWebViewAdapter();
      final endpoint = _EndpointHarness();
      final closeBarrier = Completer<void>();
      final host = _FakeContentHost(closeBarrier: closeBarrier.future);
      final resourceErrors = <String>[];
      final bridgeErrors = <Object>[];

      final binding = VrmRuntimeControllerBinding(
        endpoint: endpoint.endpoint,
        webView: webView,
        reloadRuntime: () async {},
        isRuntimeReady: () => false,
        onRuntimeInitialized: () async {},
        onControllerError: (_) {},
        onModelLoaded: () async {},
        onModelReport: (_) async {},
        onModelUnloaded: () async {},
        onBridgeMessageError: (error, _) => bridgeErrors.add(error),
        onRuntimeResourceError: resourceErrors.add,
      );
      binding.attachTransport();
      binding.attachContentHost(host);

      final firstDispose = binding.dispose();
      final secondDispose = binding.dispose();
      var disposalCompleted = false;
      unawaited(firstDispose.then<void>((_) => disposalCompleted = true));
      await Future<void>.delayed(Duration.zero);

      expect(disposalCompleted, isFalse);
      expect(host.closeCount, 1);
      closeBarrier.complete();
      await Future.wait<void>([firstDispose, secondDispose]);
      webView.messageController.add('stale');
      webView.errorController.add('stale resource error');
      webView.messageController.addError(StateError('stale bridge error'));
      await Future<void>.delayed(Duration.zero);

      expect(endpoint.runtimeMessages, isEmpty);
      expect(resourceErrors, isEmpty);
      expect(bridgeErrors, isEmpty);
      expect(endpoint.monitorDetachCount, 1);
      expect(endpoint.transportDetachCount, 1);
      expect(host.closeCount, 1);

      await endpoint.close();
      await webView.close();
    });
  });
}

final class _EndpointHarness {
  _EndpointHarness({
    this.cancellationBarrier,
    this.transportDetachBarrier,
    this.synchronousCancellationFailure,
  }) {
    states = _createController<VrmStateChangedEvent>();
    errors = _createController<VrmErrorEvent>();
    modelLoadedEvents = _createController<VrmModelLoadedEvent>();
    modelReports = _createController<VrmModelReportEvent>();
    modelUnloadedEvents = _createController<VrmModelUnloadedEvent>();
  }

  final Future<void>? cancellationBarrier;
  final Future<void>? transportDetachBarrier;
  final Object? synchronousCancellationFailure;
  late final StreamController<VrmStateChangedEvent> states;
  late final StreamController<VrmErrorEvent> errors;
  late final StreamController<VrmModelLoadedEvent> modelLoadedEvents;
  late final StreamController<VrmModelReportEvent> modelReports;
  late final StreamController<VrmModelUnloadedEvent> modelUnloadedEvents;

  bool modelLoaded = false;
  bool? restoredModelLoaded;
  int monitorAttachCount = 0;
  int monitorDetachCount = 0;
  int transportAttachCount = 0;
  int transportDetachCount = 0;
  int contentHostAttachCount = 0;
  int contentHostDetachCount = 0;
  int memoryPressureCount = 0;
  int cancellationCount = 0;
  int synchronousCancellationAttempts = 0;
  final List<String> runtimeMessages = [];
  final List<Object> reportedErrors = [];

  late final VrmRuntimeControllerEndpoint endpoint =
      VrmRuntimeControllerEndpoint(
        identity: this,
        states: _stream(states),
        errors: _stream(errors),
        modelLoadedEvents: _stream(modelLoadedEvents),
        modelReports: _stream(modelReports),
        modelUnloadedEvents: _stream(modelUnloadedEvents),
        readModelLoaded: () => modelLoaded,
        restoreModelLoaded: (loaded) {
          restoredModelLoaded = loaded;
          modelLoaded = loaded;
        },
        handleRuntimeMessage: runtimeMessages.add,
        attachTransport:
            ({
              required owner,
              required runJavaScript,
              required reloadRuntime,
              required runtimeReady,
            }) {
              transportAttachCount += 1;
            },
        detachTransport: (_) async {
          transportDetachCount += 1;
          await transportDetachBarrier;
        },
        attachContentHost: (_) => contentHostAttachCount += 1,
        detachContentHost: (_) => contentHostDetachCount += 1,
        attachHostResourceMonitoring: () => monitorAttachCount += 1,
        detachHostResourceMonitoring: () => monitorDetachCount += 1,
        recordHostMemoryPressure: () => memoryPressureCount += 1,
        reportAsyncError: (error, _) => reportedErrors.add(error),
      );

  Stream<T> _stream<T>(StreamController<T> controller) {
    final failure = synchronousCancellationFailure;
    if (failure == null) return controller.stream;
    return _CancelTrackingStream<T>(controller.stream, () {
      synchronousCancellationAttempts += 1;
      if (synchronousCancellationAttempts == 1) throw failure;
    });
  }

  StreamController<T> _createController<T>() {
    final barrier = cancellationBarrier;
    if (barrier == null) {
      return StreamController<T>.broadcast(sync: true);
    }
    return StreamController<T>(
      sync: true,
      onCancel: () {
        cancellationCount += 1;
        return barrier;
      },
    );
  }

  Future<void> close() async {
    await Future.wait<void>([
      states.close(),
      errors.close(),
      modelLoadedEvents.close(),
      modelReports.close(),
      modelUnloadedEvents.close(),
    ]);
  }
}

final class _CancelTrackingStream<T> extends Stream<T> {
  const _CancelTrackingStream(this._source, this._onCancel);

  final Stream<T> _source;
  final void Function() _onCancel;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _CancelTrackingSubscription<T>(
    _source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    ),
    _onCancel,
  );
}

final class _CancelTrackingSubscription<T> implements StreamSubscription<T> {
  const _CancelTrackingSubscription(this._delegate, this._onCancel);

  final StreamSubscription<T> _delegate;
  final void Function() _onCancel;

  @override
  Future<void> cancel() {
    _onCancel();
    return _delegate.cancel();
  }

  @override
  void onData(void Function(T data)? handleData) =>
      _delegate.onData(handleData);

  @override
  void onError(Function? handleError) => _delegate.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _delegate.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => _delegate.pause(resumeSignal);

  @override
  void resume() => _delegate.resume();

  @override
  bool get isPaused => _delegate.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => _delegate.asFuture<E>(futureValue);
}

final class _FakeWebViewAdapter implements VrmWebViewAdapter {
  final StreamController<String> messageController =
      StreamController<String>.broadcast(sync: true);
  final StreamController<String> errorController =
      StreamController<String>.broadcast(sync: true);

  @override
  Stream<String> get messages => messageController.stream;

  @override
  Stream<String> get errors => errorController.stream;

  @override
  Widget buildWidget() => const SizedBox.shrink();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> load(Uri uri) async {}

  @override
  Future<void> runJavaScript(String source) async {}

  @override
  Future<Object?> runJavaScriptReturningResult(String source) async => null;

  Future<void> close() async {
    await messageController.close();
    await errorController.close();
  }
}

final class _FakeContentHost implements VrmContentHost {
  _FakeContentHost({this.closeBarrier, this.closeFailure});

  final Future<void>? closeBarrier;
  final Object? closeFailure;
  int closeCount = 0;

  @override
  bool get isStarted => true;

  @override
  Uri get runtimeUri => Uri.parse('http://127.0.0.1/runtime');

  @override
  Future<void> start() async {}

  @override
  Future<void> close() async {
    closeCount += 1;
    await closeBarrier;
    if (closeFailure case final failure?) throw failure;
  }

  @override
  Uri exposeAsset(String assetKey) => throw UnimplementedError();

  @override
  Uri exposeBytes(Uint8List bytes, {required String fileName}) =>
      throw UnimplementedError();

  @override
  Uri exposeBytesBundle(
    Map<String, Uint8List> files, {
    required String entryFileName,
  }) => throw UnimplementedError();

  @override
  Uri exposeFile(File file) => throw UnimplementedError();

  @override
  Uri exposeFileBundle(
    Map<String, File> files, {
    required String entryFileName,
  }) => throw UnimplementedError();

  @override
  void release(Uri uri) {}
}
