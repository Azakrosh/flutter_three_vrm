import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';

void main() {
  group('VrmController background validation', () {
    late VrmController controller;

    setUp(() {
      controller = VrmController();
    });

    tearDown(() async {
      await controller.dispose();
    });

    test(
      'rejects multiple image sources before accessing the runtime',
      () async {
        await expectLater(
          controller.setBackground(
            color: Colors.black,
            imageAssetPath: 'assets/background.png',
            imageUrl: 'https://example.test/background.png',
          ),
          throwsArgumentError,
        );
      },
    );

    test('rejects an empty byte resource file name', () {
      expect(
        () => controller.setBackgroundFromBytes(
          Uint8List(0),
          fileName: '   ',
          color: Colors.black,
        ),
        throwsArgumentError,
      );
    });
  });
}
