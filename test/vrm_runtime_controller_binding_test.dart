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
  final StreamController<VrmStateChangedEvent> states =
      StreamController<VrmStateChangedEvent>.broadcast(sync: true);
  final StreamController<VrmErrorEvent> errors =
      StreamController<VrmErrorEvent>.broadcast(sync: true);
  final StreamController<VrmModelLoadedEvent> modelLoadedEvents =
      StreamController<VrmModelLoadedEvent>.broadcast(sync: true);
  final StreamController<VrmModelReportEvent> modelReports =
      StreamController<VrmModelReportEvent>.broadcast(sync: true);
  final StreamController<VrmModelUnloadedEvent> modelUnloadedEvents =
      StreamController<VrmModelUnloadedEvent>.broadcast(sync: true);

  bool modelLoaded = false;
  bool? restoredModelLoaded;
  int monitorAttachCount = 0;
  int monitorDetachCount = 0;
  int transportAttachCount = 0;
  int transportDetachCount = 0;
  int contentHostAttachCount = 0;
  int contentHostDetachCount = 0;
  int memoryPressureCount = 0;
  final List<String> runtimeMessages = [];
  final List<Object> reportedErrors = [];

  late final VrmRuntimeControllerEndpoint endpoint =
      VrmRuntimeControllerEndpoint(
        identity: this,
        states: states.stream,
        errors: errors.stream,
        modelLoadedEvents: modelLoadedEvents.stream,
        modelReports: modelReports.stream,
        modelUnloadedEvents: modelUnloadedEvents.stream,
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
        detachTransport: (_) => transportDetachCount += 1,
        attachContentHost: (_) => contentHostAttachCount += 1,
        detachContentHost: (_) => contentHostDetachCount += 1,
        attachHostResourceMonitoring: () => monitorAttachCount += 1,
        detachHostResourceMonitoring: () => monitorDetachCount += 1,
        recordHostMemoryPressure: () => memoryPressureCount += 1,
        reportAsyncError: (error, _) => reportedErrors.add(error),
      );

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
  _FakeContentHost({this.closeBarrier});

  final Future<void>? closeBarrier;
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
