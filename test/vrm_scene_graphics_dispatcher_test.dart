import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/src/bridge/vrm_protocol_contract.dart';
import 'package:flutter_three_vrm/src/content/vrm_content_host.dart';
import 'package:flutter_three_vrm/src/controller/vrm_graphics_dispatcher.dart';
import 'package:flutter_three_vrm/src/controller/vrm_hosted_resource_dispatcher.dart';
import 'package:flutter_three_vrm/src/controller/vrm_scene_dispatcher.dart';
import 'package:flutter_three_vrm/src/models/vrm_graphics.dart';
import 'package:flutter_three_vrm/src/models/vrm_wind.dart';

void main() {
  group('VrmSceneDispatcher', () {
    test('validates and emits scene commands with stable payloads', () {
      final emitted = <_CommandCall>[];
      void emit(VrmProtocolCommand action, [Map<String, dynamic>? payload]) {
        emitted.add(_CommandCall(action, payload));
      }

      final dispatcher = VrmSceneDispatcher(
        VrmHostedResourceDispatcher(() {}, (_, _) async {}),
        (_, [_]) async {},
        emit,
      );

      dispatcher.setLighting(
        ambientColor: const Color(0xFF112233),
        ambientIntensity: 0.4,
        directionalColor: const Color(0xFFABCDEF),
        directionalIntensity: 1.2,
      );
      dispatcher.setEnvironmentColor(const Color(0xFF334455), intensity: 0.25);
      dispatcher.setShadows(true);
      dispatcher.setPhysics(stiffness: 0.8, gravity: 1.1, drag: 0.7);
      dispatcher.setWind(
        type: VrmWindType.strong,
        direction: VrmWindDirection.left,
      );
      dispatcher.stopWind();

      expect(emitted[0].action, VrmProtocolCommand.setLighting);
      expect(emitted[0].payload, <String, dynamic>{
        'ambientColor': '#112233',
        'ambientIntensity': 0.4,
        'directionalColor': '#abcdef',
        'directionalIntensity': 1.2,
      });
      expect(emitted[1].payload, <String, dynamic>{
        'color': '#334455',
        'intensity': 0.25,
      });
      expect(emitted[2].payload, <String, dynamic>{'enabled': true});
      expect(emitted[3].payload, <String, dynamic>{
        'stiffness': 0.8,
        'gravity': 1.1,
        'drag': 0.7,
      });
      expect(emitted[4].payload, <String, dynamic>{
        'type': 'strong',
        'direction': 'left',
      });
      expect(emitted[5].action, VrmProtocolCommand.stopWind);
      expect(emitted[5].payload, isNull);

      expect(
        () => dispatcher.setLighting(ambientIntensity: double.nan),
        throwsArgumentError,
      );
      expect(
        () => dispatcher.setEnvironmentColor(Colors.black, intensity: 1.1),
        throwsArgumentError,
      );
      expect(() => dispatcher.setPhysics(stiffness: -0.1), throwsArgumentError);
      expect(emitted, hasLength(6));
    });

    test(
      'routes hosted and public backgrounds without leaking resources',
      () async {
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
        final dispatcher = VrmSceneDispatcher(hosted, send, (_, [_]) {});

        await dispatcher.setBackground(
          color: const Color(0xFF010203),
          transparent: true,
          imageAssetPath: 'assets/background.png',
        );
        expect(calls.first.action, VrmProtocolCommand.setBackground);
        expect(calls.first.payload, <String, dynamic>{
          'color': '#010203',
          'transparent': true,
          'hostedImage': true,
          'imageUrl': host.exposedUri.toString(),
          'fileName': 'background.png',
        });
        expect(host.releasedUris, <Uri>[host.exposedUri]);

        await dispatcher.setBackground(
          color: Colors.black,
          imageUrl: 'https://example.com/background.png',
        );
        expect(calls.last.payload, <String, dynamic>{
          'color': '#000000',
          'transparent': false,
          'imageUrl': 'https://example.com/background.png',
          'hostedImage': false,
        });

        await expectLater(
          dispatcher.setBackground(
            color: Colors.black,
            imageAssetPath: 'assets/background.png',
            imageUrl: 'https://example.com/background.png',
          ),
          throwsArgumentError,
        );
        expect(
          () => dispatcher.setBackgroundFromBytes(
            Uint8List(0),
            fileName: ' ',
            color: Colors.black,
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('VrmGraphicsDispatcher', () {
    test('validates settings and serializes renderer commands', () async {
      final calls = <_CommandCall>[];
      Future<void> send(
        VrmProtocolCommand action, [
        Map<String, dynamic>? payload,
      ]) async {
        calls.add(_CommandCall(action, payload));
      }

      final dispatcher = VrmGraphicsDispatcher(send, (_, [_]) async => null);

      await dispatcher.setPreset(VrmGraphicsPreset.performance);
      await dispatcher.setAdaptiveQuality(
        const VrmAdaptiveQualitySettings(
          targetFps: 60,
          minPixelRatio: 0.75,
          maxPixelRatio: 1.25,
        ),
      );
      await dispatcher.setSettings(
        pixelRatio: 1.25,
        antialias: false,
        enablePhysics: true,
        fpsCap: 0,
      );

      expect(calls[0].payload, <String, dynamic>{'preset': 'performance'});
      expect(calls[1].payload?['settings'], <String, Object>{
        'enabled': true,
        'targetFps': 60,
        'minPixelRatio': 0.75,
        'maxPixelRatio': 1.25,
      });
      expect(calls[2].payload, <String, dynamic>{
        'settings': <String, dynamic>{
          'pixelRatio': 1.25,
          'antialias': false,
          'enablePhysics': true,
          'fpsCap': 0,
        },
      });

      expect(
        () => dispatcher.setSettings(pixelRatio: double.infinity),
        throwsArgumentError,
      );
      expect(() => dispatcher.setSettings(fpsCap: 121), throwsArgumentError);
      expect(calls, hasLength(3));
    });

    test('queries and strictly decodes performance snapshots', () async {
      VrmProtocolCommand? requested;
      final dispatcher = VrmGraphicsDispatcher((_, [_]) async {}, (
        action, [
        payload,
      ]) async {
        requested = action;
        return null;
      });

      await expectLater(
        dispatcher.getPerformanceSnapshot(),
        throwsFormatException,
      );
      expect(requested, VrmProtocolCommand.getPerformanceSnapshot);
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
    'http://127.0.0.1:32123/resources/session/background.png',
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
  Uri exposeBytes(Uint8List bytes, {required String fileName}) => exposedUri;

  @override
  Uri exposeBytesBundle(
    Map<String, Uint8List> files, {
    required String entryFileName,
  }) => throw UnimplementedError();

  @override
  Uri exposeFile(File file) => exposedUri;

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
