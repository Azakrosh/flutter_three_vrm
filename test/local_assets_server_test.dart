import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/src/bridge/local_server.dart';

void main() {
  group('LocalAssetsServer', () {
    late Directory temporaryDirectory;
    late File modelFile;
    late LocalAssetsServer server;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'flutter_three_vrm_test_',
      );
      modelFile = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}avatar.vrm',
      );
      await modelFile.writeAsBytes(utf8.encode('test-vrm-content'));
      server = LocalAssetsServer(runtimeAssetRoot: 'assets/web');
      await server.start();
    });

    tearDown(() async {
      await server.close();
      await temporaryDirectory.delete(recursive: true);
    });

    test(
      'serves only explicitly registered files through opaque URLs',
      () async {
        final resourceUri = server.exposeFile(modelFile);

        expect(resourceUri.host, '127.0.0.1');
        expect(resourceUri.port, greaterThan(0));
        expect(
          resourceUri.toString(),
          isNot(contains(temporaryDirectory.path)),
        );

        final client = HttpClient();
        addTearDown(client.close);
        final response = await (await client.getUrl(resourceUri)).close();
        final body = await response.transform(utf8.decoder).join();

        expect(response.statusCode, HttpStatus.ok);
        expect(body, 'test-vrm-content');
        expect(
          response.headers.contentType?.mimeType,
          'application/octet-stream',
        );
        expect(response.headers.value('access-control-allow-origin'), isNull);
        expect(response.headers.value('x-content-type-options'), 'nosniff');
        expect(
          response.headers.value('cross-origin-resource-policy'),
          'same-origin',
        );
      },
    );

    test('serves authenticated bytes without exposing credentials', () async {
      final resourceUri = server.exposeBytes(
        Uint8List.fromList(<int>[1, 2, 3, 4]),
        fileName: 'secured.vrm',
      );
      final client = HttpClient();
      addTearDown(client.close);
      final response = await (await client.getUrl(resourceUri)).close();
      final body = await response.fold<List<int>>(<int>[], (bytes, chunk) {
        bytes.addAll(chunk);
        return bytes;
      });

      expect(response.statusCode, HttpStatus.ok);
      expect(body, <int>[1, 2, 3, 4]);
      expect(resourceUri.query, isEmpty);

      server.release(resourceUri);
      final releasedResponse = await (await client.getUrl(resourceUri)).close();
      expect(releasedResponse.statusCode, HttpStatus.notFound);
    });
    test('rejects missing session token and a spoofed Host header', () async {
      final client = HttpClient();
      addTearDown(client.close);

      final missingTokenUri = server.runtimeUri.replace(
        path: '/invalid/runtime/index.html',
      );
      final missingTokenResponse = await (await client.getUrl(
        missingTokenUri,
      )).close();
      expect(missingTokenResponse.statusCode, HttpStatus.notFound);

      final request = await client.getUrl(server.exposeFile(modelFile));
      request.headers.set(HttpHeaders.hostHeader, 'attacker.invalid');
      final spoofedHostResponse = await request.close();
      expect(spoofedHostResponse.statusCode, HttpStatus.forbidden);
    });

    test(
      'serves an explicit glTF resource bundle and releases it atomically',
      () async {
        final resourceUri = server.exposeBytesBundle(<String, Uint8List>{
          'animation.gltf': Uint8List.fromList(utf8.encode('{"buffers":[]}')),
          'buffers/motion.bin': Uint8List.fromList(<int>[5, 6, 7]),
        }, entryFileName: 'animation.gltf');
        final client = HttpClient();
        addTearDown(client.close);

        final entryResponse = await (await client.getUrl(resourceUri)).close();
        expect(entryResponse.statusCode, HttpStatus.ok);
        expect(entryResponse.headers.contentType?.mimeType, 'application/json');

        final bufferUri = resourceUri.resolve('buffers/motion.bin');
        final bufferResponse = await (await client.getUrl(bufferUri)).close();
        final body = await bufferResponse.fold<List<int>>(<int>[], (
          bytes,
          chunk,
        ) {
          bytes.addAll(chunk);
          return bytes;
        });
        expect(bufferResponse.statusCode, HttpStatus.ok);
        expect(body, <int>[5, 6, 7]);

        server.release(resourceUri);
        final releasedResponse = await (await client.getUrl(bufferUri)).close();
        expect(releasedResponse.statusCode, HttpStatus.notFound);
      },
    );

    test('rejects unsafe or missing resource bundle entrypoints', () {
      expect(
        () => server.exposeBytesBundle(<String, Uint8List>{
          '../secret.bin': Uint8List(0),
        }, entryFileName: '../secret.bin'),
        throwsArgumentError,
      );
      expect(
        () => server.exposeBytesBundle(<String, Uint8List>{
          'animation.bin': Uint8List(0),
        }, entryFileName: 'animation.gltf'),
        throwsArgumentError,
      );
    });

    test('supports HEAD without returning the resource body', () async {
      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.openUrl(
        'HEAD',
        server.exposeFile(modelFile),
      );
      final response = await request.close();
      final body = await response.fold<List<int>>(<int>[], (bytes, chunk) {
        bytes.addAll(chunk);
        return bytes;
      });

      expect(response.statusCode, HttpStatus.ok);
      expect(response.contentLength, utf8.encode('test-vrm-content').length);
      expect(body, isEmpty);
    });
  });
}
