import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/src/bridge/vrm_protocol_contract.dart';
import 'package:flutter_three_vrm/src/content/vrm_content_host.dart';
import 'package:flutter_three_vrm/src/controller/vrm_hosted_resource_dispatcher.dart';

void main() {
  group('VrmHostedResourceDispatcher', () {
    test(
      'sends the exposed URL and always releases it after success',
      () async {
        final host = _FakeContentHost();
        VrmProtocolCommand? sentAction;
        Map<String, dynamic>? sentPayload;
        final dispatcher = VrmHostedResourceDispatcher(() {}, (
          action,
          payload,
        ) async {
          sentAction = action;
          sentPayload = payload;
        })..attach(host);

        await dispatcher.send(
          expose: (attachedHost) => attachedHost.exposeAsset('avatar.vrm'),
          action: VrmProtocolCommand.loadModelFromUrl,
          fileName: 'avatar.vrm',
          payload: <String, dynamic>{'request': 'model'},
        );

        expect(sentAction, VrmProtocolCommand.loadModelFromUrl);
        expect(sentPayload, <String, dynamic>{
          'request': 'model',
          'url': host.exposedUri.toString(),
          'fileName': 'avatar.vrm',
        });
        expect(host.releasedUris, <Uri>[host.exposedUri]);
      },
    );

    test('releases the exposed URL when the runtime command fails', () async {
      final host = _FakeContentHost();
      final dispatcher = VrmHostedResourceDispatcher(
        () {},
        (_, _) async => throw StateError('runtime failed'),
      )..attach(host);

      await expectLater(
        dispatcher.send(
          expose: (attachedHost) => attachedHost.exposeAsset('avatar.vrm'),
          action: VrmProtocolCommand.loadModelFromUrl,
          fileName: 'avatar.vrm',
        ),
        throwsStateError,
      );

      expect(host.releasedUris, <Uri>[host.exposedUri]);
    });

    test('rejects commands without an active started content host', () async {
      final dispatcher = VrmHostedResourceDispatcher(() {}, (_, _) async {});

      await expectLater(
        dispatcher.send(
          expose: (host) => host.exposeAsset('avatar.vrm'),
          action: VrmProtocolCommand.loadModelFromUrl,
          fileName: 'avatar.vrm',
        ),
        throwsStateError,
      );

      final stoppedHost = _FakeContentHost(isStarted: false);
      dispatcher.attach(stoppedHost);
      await expectLater(
        dispatcher.send(
          expose: (host) => host.exposeAsset('avatar.vrm'),
          action: VrmProtocolCommand.loadModelFromUrl,
          fileName: 'avatar.vrm',
        ),
        throwsStateError,
      );
      expect(stoppedHost.exposeCount, 0);
    });

    test(
      'detaches only the matching host and checks controller lifetime',
      () async {
        var active = true;
        final firstHost = _FakeContentHost();
        final otherHost = _FakeContentHost();
        final dispatcher = VrmHostedResourceDispatcher(() {
          if (!active) throw StateError('disposed');
        }, (_, _) async {})..attach(firstHost);

        expect(dispatcher.detach(otherHost), isFalse);
        await dispatcher.send(
          expose: (host) => host.exposeAsset('avatar.vrm'),
          action: VrmProtocolCommand.loadModelFromUrl,
          fileName: 'avatar.vrm',
        );
        expect(firstHost.exposeCount, 1);

        expect(dispatcher.detach(firstHost), isTrue);
        active = false;
        await expectLater(
          dispatcher.send(
            expose: (host) => host.exposeAsset('avatar.vrm'),
            action: VrmProtocolCommand.loadModelFromUrl,
            fileName: 'avatar.vrm',
          ),
          throwsStateError,
        );
      },
    );
  });
}

final class _FakeContentHost implements VrmContentHost {
  _FakeContentHost({this.isStarted = true});

  @override
  final bool isStarted;

  final Uri exposedUri = Uri.parse(
    'http://127.0.0.1:32123/resources/session/avatar.vrm',
  );
  final List<Uri> releasedUris = [];
  int exposeCount = 0;

  @override
  Uri get runtimeUri => Uri.parse('http://127.0.0.1:32123/runtime');

  @override
  Future<void> start() async {}

  @override
  Future<void> close() async {}

  @override
  Uri exposeAsset(String assetKey) {
    exposeCount += 1;
    return exposedUri;
  }

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
