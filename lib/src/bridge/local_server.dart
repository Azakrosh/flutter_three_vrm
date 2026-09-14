import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../content/vrm_content_host.dart';

/// Session-scoped loopback content host used by Android and Windows.
///
/// It binds to a random port and only exposes resources that were explicitly
/// registered by this instance. Raw filesystem paths are never accepted over
/// HTTP.
final class LocalAssetsServer implements VrmContentHost {
  LocalAssetsServer({required this.runtimeAssetRoot})
    : _sessionToken = _randomToken(24);

  final String runtimeAssetRoot;
  final String _sessionToken;
  final Map<String, _HostedResource> _resources = <String, _HostedResource>{};

  HttpServer? _server;
  Future<void>? _startFuture;
  bool _isClosed = false;

  @override
  bool get isStarted => _server != null && !_isClosed;

  @override
  Uri get runtimeUri {
    final server = _requireServer();
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      path: '/$_sessionToken/runtime/index.html',
    );
  }

  @override
  Future<void> start() async {
    if (_isClosed) {
      throw StateError('The content host has already been closed.');
    }
    if (_server != null) {
      return;
    }

    final existingStart = _startFuture;
    if (existingStart != null) {
      return existingStart;
    }

    final start = _start();
    _startFuture = start;
    try {
      await start;
    } catch (_) {
      _startFuture = null;
      rethrow;
    }
  }

  Future<void> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (_isClosed) {
      await server.close(force: true);
      throw StateError('The content host was closed while starting.');
    }

    _server = server;
    server.listen(
      (HttpRequest request) => unawaited(_handleRequest(request)),
      onError: (Object error, StackTrace stackTrace) {
        if (kDebugMode) {
          debugPrint('VRM content host error: $error');
        }
      },
    );
  }

  @override
  Uri exposeAsset(String assetKey) {
    _requireServer();
    final id = _register(_AssetResource(assetKey));
    return _resourceUri(id, path.basename(assetKey));
  }

  @override
  Uri exposeFile(File file) {
    _requireServer();
    final id = _register(_FileResource(file));
    return _resourceUri(id, path.basename(file.path));
  }

  @override
  Uri exposeBytes(Uint8List bytes, {required String fileName}) {
    _requireServer();
    final id = _register(_MemoryResource(bytes, fileName));
    return _resourceUri(id, path.basename(fileName));
  }

  @override
  Uri exposeFileBundle(
    Map<String, File> files, {
    required String entryFileName,
  }) {
    _requireServer();
    final bundle = _validatedBundle(files, entryFileName: entryFileName);
    final id = _register(_FileBundleResource(bundle.files));
    return _resourceUri(id, bundle.entryFileName);
  }

  @override
  Uri exposeBytesBundle(
    Map<String, Uint8List> files, {
    required String entryFileName,
  }) {
    _requireServer();
    final bundle = _validatedBundle(files, entryFileName: entryFileName);
    final id = _register(_MemoryBundleResource(bundle.files));
    return _resourceUri(id, bundle.entryFileName);
  }

  @override
  void release(Uri uri) {
    final segments = uri.pathSegments;
    if (uri.host != InternetAddress.loopbackIPv4.address ||
        segments.length < 3 ||
        segments[0] != _sessionToken ||
        segments[1] != 'resource') {
      return;
    }
    _resources.remove(segments[2]);
  }

  String _register(_HostedResource resource) {
    String id;
    do {
      id = _randomToken(18);
    } while (_resources.containsKey(id));
    _resources[id] = resource;
    return id;
  }

  Uri _resourceUri(String id, String relativePath) {
    final server = _requireServer();
    final resourceSegments = relativePath.isEmpty
        ? const <String>['resource.bin']
        : relativePath.split('/');
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: <String>[
        _sessionToken,
        'resource',
        id,
        ...resourceSegments,
      ],
    );
  }

  _ValidatedBundle<T> _validatedBundle<T>(
    Map<String, T> files, {
    required String entryFileName,
  }) {
    if (files.isEmpty) {
      throw ArgumentError.value(files, 'files', 'A resource bundle is empty.');
    }

    final normalizedFiles = <String, T>{};
    for (final entry in files.entries) {
      final logicalPath = _validateLogicalPath(entry.key);
      if (normalizedFiles.containsKey(logicalPath)) {
        throw ArgumentError.value(
          entry.key,
          'files',
          'Duplicate logical path.',
        );
      }
      normalizedFiles[logicalPath] = entry.value;
    }

    final normalizedEntry = _validateLogicalPath(entryFileName);
    if (!normalizedFiles.containsKey(normalizedEntry)) {
      throw ArgumentError.value(
        entryFileName,
        'entryFileName',
        'The entrypoint is not present in the resource bundle.',
      );
    }
    return _ValidatedBundle<T>(
      Map<String, T>.unmodifiable(normalizedFiles),
      normalizedEntry,
    );
  }

  String _validateLogicalPath(String value) {
    final uri = Uri.tryParse(value);
    final segments = value.split('/');
    if (value.isEmpty ||
        value.startsWith('/') ||
        value.contains(r'\') ||
        uri == null ||
        uri.hasScheme ||
        uri.hasQuery ||
        uri.hasFragment ||
        segments.any(
          (segment) => segment.isEmpty || segment == '.' || segment == '..',
        )) {
      throw ArgumentError.value(
        value,
        'logicalPath',
        'Expected a safe relative URI path.',
      );
    }
    return segments.join('/');
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    response.headers
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Cross-Origin-Resource-Policy', 'same-origin')
      ..set(
        'Content-Security-Policy',
        "default-src 'self' blob: data:; "
            "script-src 'self'; "
            "style-src 'self'; "
            "img-src 'self' blob: data: http: https:; "
            "connect-src 'self' blob: data: http: https:; "
            "object-src 'none'; "
            "base-uri 'none'; "
            "frame-ancestors 'none'",
      )
      ..set(HttpHeaders.cacheControlHeader, 'no-store');

    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
        return;
      }

      final host = request.headers.value(HttpHeaders.hostHeader);
      final expectedHost = '127.0.0.1:${_requireServer().port}';
      if (host != expectedHost) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }

      final segments = request.uri.pathSegments;
      if (segments.length < 2 || segments.first != _sessionToken) {
        response.statusCode = HttpStatus.notFound;
        return;
      }

      switch (segments[1]) {
        case 'runtime':
          await _serveRuntime(request, segments.skip(2).toList());
        case 'resource':
          await _serveResource(request, segments);
        default:
          response.statusCode = HttpStatus.notFound;
      }
    } on FlutterError catch (error) {
      if (kDebugMode) {
        debugPrint('VRM asset was not found: ${error.message}');
      }
      response.statusCode = HttpStatus.notFound;
    } on FileSystemException {
      response.statusCode = HttpStatus.notFound;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('VRM content request failed: $error\n$stackTrace');
      }
      response.statusCode = HttpStatus.internalServerError;
    } finally {
      await response.close();
    }
  }

  Future<void> _serveRuntime(
    HttpRequest request,
    List<String> relativeSegments,
  ) async {
    if (relativeSegments.isEmpty ||
        relativeSegments.any(
          (segment) =>
              segment.isEmpty ||
              segment == '.' ||
              segment == '..' ||
              segment.contains(r'\'),
        )) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }

    final assetKey = <String>[runtimeAssetRoot, ...relativeSegments].join('/');
    final data = await rootBundle.load(assetKey);
    await _serveBytes(
      request,
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      assetKey,
    );
  }

  Future<void> _serveResource(
    HttpRequest request,
    List<String> segments,
  ) async {
    if (segments.length < 4) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }

    final resource = _resources[segments[2]];
    if (resource == null) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }

    switch (resource) {
      case _AssetResource(:final assetKey):
        final data = await rootBundle.load(assetKey);
        await _serveBytes(
          request,
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          assetKey,
        );
      case _FileResource(:final file):
        if (!await file.exists()) {
          request.response.statusCode = HttpStatus.notFound;
          return;
        }
        request.response.headers.contentType = _contentType(file.path);
        request.response.contentLength = await file.length();
        if (request.method == 'GET') {
          await request.response.addStream(file.openRead());
        }
      case _MemoryResource(:final bytes, :final fileName):
        await _serveBytes(request, bytes, fileName);
      case _FileBundleResource(:final files):
        final logicalPath = segments.skip(3).join('/');
        final file = files[logicalPath];
        if (file == null || !await file.exists()) {
          request.response.statusCode = HttpStatus.notFound;
          return;
        }
        request.response.headers.contentType = _contentType(logicalPath);
        request.response.contentLength = await file.length();
        if (request.method == 'GET') {
          await request.response.addStream(file.openRead());
        }
      case _MemoryBundleResource(:final files):
        final logicalPath = segments.skip(3).join('/');
        final bytes = files[logicalPath];
        if (bytes == null) {
          request.response.statusCode = HttpStatus.notFound;
          return;
        }
        await _serveBytes(request, bytes, logicalPath);
    }
  }

  Future<void> _serveBytes(
    HttpRequest request,
    Uint8List bytes,
    String fileName,
  ) async {
    request.response.headers.contentType = _contentType(fileName);
    request.response.contentLength = bytes.length;
    if (request.method == 'GET') {
      request.response.add(bytes);
    }
  }

  ContentType _contentType(String fileName) {
    switch (path.extension(fileName).toLowerCase()) {
      case '.html':
        return ContentType.html;
      case '.js':
      case '.mjs':
        return ContentType('application', 'javascript', charset: 'utf-8');
      case '.css':
        return ContentType('text', 'css', charset: 'utf-8');
      case '.json':
      case '.gltf':
        return ContentType.json;
      case '.png':
        return ContentType('image', 'png');
      case '.jpg':
      case '.jpeg':
        return ContentType('image', 'jpeg');
      case '.webp':
        return ContentType('image', 'webp');
      case '.gif':
        return ContentType('image', 'gif');
      case '.svg':
        return ContentType('image', 'svg+xml');
      case '.wasm':
        return ContentType('application', 'wasm');
      case '.vrm':
      case '.vrma':
      case '.glb':
      case '.bin':
      case '.ktx2':
        return ContentType.binary;
      default:
        return ContentType.binary;
    }
  }

  HttpServer _requireServer() {
    final server = _server;
    if (server == null || _isClosed) {
      throw StateError('The content host has not been started.');
    }
    return server;
  }

  @override
  Future<void> close() async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;

    final start = _startFuture;
    if (start != null) {
      try {
        await start;
      } catch (_) {
        // A failed or cancelled start has no server left to close.
      }
    }

    final server = _server;
    _server = null;
    _resources.clear();
    if (server != null) {
      await server.close(force: true);
    }
  }

  static String _randomToken(int byteCount) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteCount, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

sealed class _HostedResource {
  const _HostedResource();
}

final class _AssetResource extends _HostedResource {
  const _AssetResource(this.assetKey);

  final String assetKey;
}

final class _FileResource extends _HostedResource {
  const _FileResource(this.file);

  final File file;
}

final class _MemoryResource extends _HostedResource {
  const _MemoryResource(this.bytes, this.fileName);

  final Uint8List bytes;
  final String fileName;
}

final class _FileBundleResource extends _HostedResource {
  const _FileBundleResource(this.files);

  final Map<String, File> files;
}

final class _MemoryBundleResource extends _HostedResource {
  const _MemoryBundleResource(this.files);

  final Map<String, Uint8List> files;
}

final class _ValidatedBundle<T> {
  const _ValidatedBundle(this.files, this.entryFileName);

  final Map<String, T> files;
  final String entryFileName;
}
