import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/src/bridge/vrm_protocol_contract.dart';
import 'package:flutter_three_vrm/src/content/vrm_content_host.dart';
import 'package:flutter_three_vrm/src/controller/vrm_hosted_resource_dispatcher.dart';
import 'package:flutter_three_vrm/src/controller/vrm_model_dispatcher.dart';

void main() {
  group('VrmModelDispatcher', () {
    test('loads a hosted model and releases its temporary URI', () async {
      final calls = <_CommandCall>[];
      Future<void> send(
        VrmProtocolCommand action, [
        Map<String, dynamic>? payload,
      ]) async {
        calls.add(_CommandCall(action, payload));
      }

      final host = _FakeContentHost();
      final hosted = VrmHostedResourceDispatcher(() {}, (action, payload) {
        return send(action, payload);
      })..attach(host);
      final dispatcher = VrmModelDispatcher(hosted, send);

      await dispatcher.loadHosted(
        expose: (attachedHost) => attachedHost.exposeAsset('avatar.vrm'),
        fileName: 'avatar.vrm',
      );

      expect(dispatcher.isLoading, isFalse);
      expect(dispatcher.isLoaded, isTrue);
      expect(calls.single.action, VrmProtocolCommand.loadModelFromUrl);
      expect(calls.single.payload, <String, dynamic>{
        'url': host.exposedUri.toString(),
        'fileName': 'avatar.vrm',
      });
      expect(host.releasedUris, <Uri>[host.exposedUri]);
    });

    test(
      'a stale replacement cannot restore model state after runtime loss',
      () async {
        final calls = <_CommandCall>[];
        final completions = <Completer<void>>[];
        Future<void> send(
          VrmProtocolCommand action, [
          Map<String, dynamic>? payload,
        ]) {
          calls.add(_CommandCall(action, payload));
          final completion = Completer<void>();
          completions.add(completion);
          return completion.future;
        }

        final dispatcher = VrmModelDispatcher(
          VrmHostedResourceDispatcher(() {}, (action, payload) {
            return send(action, payload);
          }),
          send,
        );

        final first = dispatcher.loadUrl('https://example.com/first.vrm');
        final second = dispatcher.loadUrl('https://example.com/second.vrm');

        expect(dispatcher.isLoading, isTrue);
        expect(calls[0].payload?['fileName'], 'first.vrm');
        expect(calls[1].payload?['fileName'], 'second.vrm');

        completions[1].complete();
        await second;
        expect(dispatcher.isLoaded, isTrue);
        expect(dispatcher.isLoading, isFalse);

        dispatcher.invalidateRuntime();
        completions[0].complete();
        await first;

        expect(dispatcher.isLoaded, isFalse);
        expect(dispatcher.isLoading, isFalse);
      },
    );

    test(
      'cancel invalidates a pending load before sending its command',
      () async {
        final loadCompletion = Completer<void>();
        final calls = <_CommandCall>[];
        Future<void> send(
          VrmProtocolCommand action, [
          Map<String, dynamic>? payload,
        ]) {
          calls.add(_CommandCall(action, payload));
          if (action == VrmProtocolCommand.loadModelFromUrl) {
            return loadCompletion.future;
          }
          return Future<void>.value();
        }

        final dispatcher = VrmModelDispatcher(
          VrmHostedResourceDispatcher(() {}, (action, payload) {
            return send(action, payload);
          }),
          send,
        );

        final pendingLoad = dispatcher.loadUrl(
          'https://example.com/avatar.vrm',
        );
        expect(dispatcher.isLoading, isTrue);

        await dispatcher.cancelLoad();

        expect(dispatcher.isLoading, isFalse);
        expect(calls.last.action, VrmProtocolCommand.cancelModelLoad);
        expect(calls.last.payload, isNull);

        loadCompletion.complete();
        await pendingLoad;
        expect(dispatcher.isLoaded, isFalse);
      },
    );

    test('unload preserves loaded state until the command succeeds', () async {
      final unloadCompletion = Completer<void>();
      final calls = <_CommandCall>[];
      Future<void> send(
        VrmProtocolCommand action, [
        Map<String, dynamic>? payload,
      ]) {
        calls.add(_CommandCall(action, payload));
        return unloadCompletion.future;
      }

      final dispatcher = VrmModelDispatcher(
        VrmHostedResourceDispatcher(() {}, (action, payload) {
          return send(action, payload);
        }),
        send,
      )..restoreLoaded(true);

      final unload = dispatcher.unload(speechRevision: 17);

      expect(dispatcher.isLoaded, isTrue);
      expect(calls.single.action, VrmProtocolCommand.unloadModel);
      expect(calls.single.payload, <String, dynamic>{'speechRevision': 17});

      unloadCompletion.complete();
      await unload;
      expect(dispatcher.isLoaded, isFalse);
      expect(dispatcher.isLoading, isFalse);
    });
  });
}

final class _CommandCall {
  const _CommandCall(this.action, this.payload);

  final VrmProtocolCommand action;
  final Map<String, dynamic>? payload;
}

final class _FakeContentHost implements VrmContentHost {
  final Uri exposedUri = Uri.parse(
    'http://127.0.0.1:32123/resources/session/avatar.vrm',
  );
  final List<Uri> releasedUris = [];

  @override
  bool get isStarted => true;

  @override
  Uri get runtimeUri => Uri.parse('http://127.0.0.1:32123/runtime');

  @override
  Future<void> start() async {}

  @override
  Future<void> close() async {}

  @override
  Uri exposeAsset(String assetKey) => exposedUri;

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
  void release(Uri uri) {
    releasedUris.add(uri);
  }
}
