import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A lightweight local HTTP server to bypass strict WebView CORS policies
/// for ES modules (`<script type="module">`). It serves Flutter assets over `http://127.0.0.1`.
class LocalAssetsServer {
  static io.HttpServer? _server;
  static int _port = 0;
  static String? _basePath;
  static int _usageCount = 0;
  static Completer<int>? _startCompleter;

  static int get port => _port;

  static Future<int> start(String basePath) async {
    _usageCount++;
    if (_server != null) return _port;

    // Guard against concurrent start() calls
    if (_startCompleter != null) return _startCompleter!.future;
    _startCompleter = Completer<int>();

    _basePath = basePath;
    try {
      // Пытаемся занять фиксированный порт 8080.
      // Это критически важно для WebView, так как IndexedDB (кэш) привязан к "Origin" (ip + port).
      // Если порт будет случайным (0), при каждом запуске кэш будет пуст, а старые данные станут мусором.
      _server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 8080);
    } catch (e) {
      // Fallback на случайный порт, если 8080 занят другим процессом
      _server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    }
    _port = _server!.port;

    _server!.listen((io.HttpRequest request) async {
      try {
        // Поддержка CORS для запросов из WebView
        request.response.headers.add('Access-Control-Allow-Origin', '*');

        final path = request.uri.path;
        if (path == '/favicon.ico') {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        debugPrint('LocalAssetsServer: Received request for path: $path');

        if (path == '/asset') {
          // Загрузка Flutter Asset (.vrm, .vrma, изображения)

          final targetPath = request.uri.queryParameters['path'];
          debugPrint('LocalAssetsServer: Loading asset: $targetPath');
          if (targetPath != null) {
            final data = await rootBundle.load(targetPath);

            String contentType = 'application/octet-stream';
            final lowerPath = targetPath.toLowerCase();
            if (lowerPath.endsWith('.png')) {
              contentType = 'image/png';
            } else if (lowerPath.endsWith('.jpg') ||
                lowerPath.endsWith('.jpeg')) {
              contentType = 'image/jpeg';
            } else if (lowerPath.endsWith('.webp')) {
              contentType = 'image/webp';
            } else if (lowerPath.endsWith('.gif')) {
              contentType = 'image/gif';
            }

            request.response.headers.contentType =
                io.ContentType.parse(contentType);
            request.response.add(data.buffer.asUint8List());
            await request.response.close();
            return;
          }
        } else if (path == '/file') {
          // Загрузка файла из файловой системы устройства (.vrm, .vrma)
          final targetPath = request.uri.queryParameters['path'];
          debugPrint('LocalAssetsServer: Loading file: $targetPath');
          if (targetPath != null) {
            final file = io.File(targetPath);
            if (await file.exists()) {
              request.response.headers.contentType =
                  io.ContentType.parse('application/octet-stream');
              await request.response.addStream(file.openRead());
              await request.response.close();
              return;
            } else {
              debugPrint('LocalAssetsServer: File not found: $targetPath');
            }
          }
        }

        // Стандартная отдача веб-ассетов (index.html, JS, CSS)
        final webPath = path == '/' ? '/index.html' : path;
        final assetPath = '$_basePath$webPath';
        debugPrint('LocalAssetsServer: Loading web asset: $assetPath');
        final data = await rootBundle.load(assetPath);

        String contentType = 'text/plain';
        if (webPath.endsWith('.html')) {
          contentType = 'text/html';
        } else if (webPath.endsWith('.js')) {
          contentType = 'application/javascript';
        } else if (webPath.endsWith('.css')) {
          contentType = 'text/css';
        } else if (webPath.endsWith('.png')) {
          contentType = 'image/png';
        }

        request.response.headers.contentType =
            io.ContentType.parse(contentType);
        request.response.add(data.buffer.asUint8List());
      } catch (e) {
        debugPrint('LocalAssetsServer: Error processing request: $e');
        request.response.statusCode = 404;
      }
      await request.response.close();
    });

    _startCompleter?.complete(_port);
    return _port;
  }

  static void decrementUsage() {
    _usageCount--;
    if (_usageCount <= 0) {
      _server?.close();
      _server = null;
      _startCompleter = null;
      _usageCount = 0;
    }
  }
}
