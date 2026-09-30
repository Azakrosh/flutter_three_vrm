import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/src/bridge/vrm_protocol_contract.dart';
import 'package:flutter_three_vrm/src/content/vrm_content_host.dart';
import 'package:flutter_three_vrm/src/controller/vrm_animation_dispatcher.dart';
import 'package:flutter_three_vrm/src/controller/vrm_hosted_resource_dispatcher.dart';
import 'package:flutter_three_vrm/src/models/vrm_animation_options.dart';

void main() {
  group('VrmAnimationDispatcher', () {
    test('builds URL playback payloads with unique identities', () async {
      final calls = <_CommandCall>[];
      Future<void> send(
        VrmProtocolCommand action, [
        Map<String, dynamic>? payload,
      ]) async {
        calls.add(_CommandCall(action, payload));
      }

      final dispatcher = VrmAnimationDispatcher(
        VrmHostedResourceDispatcher(() {}, (action, payload) {
          return send(action, payload);
        }),
        send,
      );

      final first = await dispatcher.playUrl(
        'https://example.com/motions/wave.glb',
        loop: false,
        speed: 1.25,
        fadeDuration: 0.3,
        rootMotion: VrmRootMotion.full,
        clipName: 'Wave',
      );
      final second = await dispatcher.playUrl(
        'https://example.com/motions/idle.vrma',
        loop: true,
        speed: 1,
        fadeDuration: 0.5,
        rootMotion: VrmRootMotion.inPlace,
        clipName: null,
      );

      expect(first.id, startsWith('animation-'));
      expect(second.id, startsWith('animation-'));
      expect(second.id, isNot(first.id));
      expect(calls.first.action, VrmProtocolCommand.playAnimationFromUrl);
      expect(calls.first.payload?['url'], contains('/wave.glb'));
      expect(calls.first.payload?['fileName'], 'wave.glb');
      expect(calls.first.payload?['options'], <String, dynamic>{
        'loop': false,
        'speed': 1.25,
        'fadeDuration': 0.3,
        'rootMotion': 'full',
        'clipName': 'Wave',
        'playbackId': first.id,
      });
      expect(
        (calls.last.payload?['options'] as Map<String, dynamic>).containsKey(
          'clipName',
        ),
        isFalse,
      );
    });

    test('delegates hosted playback and releases the exposed URI', () async {
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
      final dispatcher = VrmAnimationDispatcher(hosted, send);

      final playback = await dispatcher.playHosted(
        expose: (attachedHost) => attachedHost.exposeAsset('wave.vrma'),
        fileName: 'wave.vrma',
        loop: true,
        speed: 1,
        fadeDuration: 0.5,
        rootMotion: VrmRootMotion.inPlace,
        clipName: null,
      );

      expect(calls.single.action, VrmProtocolCommand.playAnimationFromUrl);
      expect(calls.single.payload?['url'], host.exposedUri.toString());
      expect(calls.single.payload?['fileName'], 'wave.vrma');
      expect(
        calls.single.payload?['options'],
        containsPair('playbackId', playback.id),
      );
      expect(host.releasedUris, <Uri>[host.exposedUri]);
    });

    test('preserves validation and payload semantics for controls', () async {
      final calls = <_CommandCall>[];
      Future<void> send(
        VrmProtocolCommand action, [
        Map<String, dynamic>? payload,
      ]) async {
        calls.add(_CommandCall(action, payload));
      }

      final dispatcher = VrmAnimationDispatcher(
        VrmHostedResourceDispatcher(() {}, (action, payload) {
          return send(action, payload);
        }),
        send,
      );

      expect(
        () => dispatcher.playUrl(
          ' ',
          loop: true,
          speed: 1,
          fadeDuration: 0.5,
          rootMotion: VrmRootMotion.inPlace,
          clipName: null,
        ),
        throwsArgumentError,
      );
      expect(() => dispatcher.resume(speed: 0), throwsArgumentError);
      expect(() => dispatcher.stop(fadeDuration: -0.1), throwsArgumentError);
      expect(() => dispatcher.setSpeed(double.nan), throwsArgumentError);

      await dispatcher.pause();
      await dispatcher.resume(speed: 1.5);
      await dispatcher.cancelLoad();
      await dispatcher.stop(fadeDuration: 0.2);
      await dispatcher.setSpeed(0.75);

      expect(calls.map((call) => call.action), <VrmProtocolCommand>[
        VrmProtocolCommand.pauseAnimation,
        VrmProtocolCommand.resumeAnimation,
        VrmProtocolCommand.cancelAnimationLoad,
        VrmProtocolCommand.stopAnimation,
        VrmProtocolCommand.setAnimationSpeed,
      ]);
      expect(calls[0].payload, isNull);
      expect(calls[1].payload, <String, dynamic>{'speed': 1.5});
      expect(calls[2].payload, isNull);
      expect(calls[3].payload, <String, dynamic>{'fadeDuration': 0.2});
      expect(calls[4].payload, <String, dynamic>{'speed': 0.75});
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
    'http://127.0.0.1:32123/resources/session/wave.vrma',
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
