import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/vrm_integration_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('loads authenticated model bytes and an external glTF bundle', (
    tester,
  ) async {
    final harness = await VrmIntegrationHarness.start(tester);
    final controller = harness.controller;
    await harness.waitForModel();
    await harness.waitForAnimation();

    final asset = await rootBundle.load('assets/vrm/sample.vrm');
    final modelBytes = asset.buffer.asUint8List(
      asset.offsetInBytes,
      asset.lengthInBytes,
    );

    await controller.unloadModel();
    final modelLoaded = controller.onModelLoaded.first;
    await controller.loadModelFromBytes(
      modelBytes,
      fileName: 'authenticated-avatar.vrm',
    );
    await modelLoaded.timeout(const Duration(seconds: 45));

    final report = await controller.getModelReport();
    expect(report.sourceBytes, modelBytes.lengthInBytes);
    expect(report.humanoidBones, greaterThan(0));
    expect(controller.isModelLoaded, isTrue);

    final bundle = _createExternalGltfBundle();
    final animationStarted = controller.onAnimationStarted.first;
    final animationFinished = controller.onAnimationFinished.first;
    final playback = await controller.playAnimationFromBytesBundle(
      bundle,
      entryFileName: 'animation.gltf',
      loop: false,
      fadeDuration: 0,
      clipName: 'AuthenticatedBundle',
    );

    expect(
      (await animationStarted.timeout(const Duration(seconds: 5))).playbackId,
      playback.id,
    );
    expect(
      (await animationFinished.timeout(const Duration(seconds: 10))).playbackId,
      playback.id,
    );
    expect((await controller.getRuntimeHealth()).contextLost, isFalse);

    await harness.disposeView();
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Map<String, Uint8List> _createExternalGltfBundle() {
  final binary = ByteData(40);
  const values = <double>[0, 0.5, 0, 0, 0, 1, 0, 0.2588190451, 0, 0.9659258263];
  for (var index = 0; index < values.length; index += 1) {
    binary.setFloat32(index * 4, values[index], Endian.little);
  }

  final document = <String, Object>{
    'asset': <String, Object>{
      'version': '2.0',
      'generator': 'flutter_three_vrm integration test',
    },
    'scene': 0,
    'scenes': <Object>[
      <String, Object>{
        'nodes': <int>[0],
      },
    ],
    'nodes': <Object>[
      <String, Object>{
        'name': 'mixamorigHips',
        'rotation': <double>[0, 0, 0, 1],
      },
    ],
    'buffers': <Object>[
      <String, Object>{'uri': 'buffers/motion.bin', 'byteLength': 40},
    ],
    'bufferViews': <Object>[
      <String, Object>{'buffer': 0, 'byteOffset': 0, 'byteLength': 8},
      <String, Object>{'buffer': 0, 'byteOffset': 8, 'byteLength': 32},
    ],
    'accessors': <Object>[
      <String, Object>{
        'bufferView': 0,
        'componentType': 5126,
        'count': 2,
        'type': 'SCALAR',
        'min': <double>[0],
        'max': <double>[0.5],
      },
      <String, Object>{
        'bufferView': 1,
        'componentType': 5126,
        'count': 2,
        'type': 'VEC4',
      },
    ],
    'animations': <Object>[
      <String, Object>{
        'name': 'AuthenticatedBundle',
        'samplers': <Object>[
          <String, Object>{'input': 0, 'output': 1, 'interpolation': 'LINEAR'},
        ],
        'channels': <Object>[
          <String, Object>{
            'sampler': 0,
            'target': <String, Object>{'node': 0, 'path': 'rotation'},
          },
        ],
      },
    ],
  };

  return <String, Uint8List>{
    'animation.gltf': Uint8List.fromList(utf8.encode(jsonEncode(document))),
    'buffers/motion.bin': binary.buffer.asUint8List(),
  };
}
