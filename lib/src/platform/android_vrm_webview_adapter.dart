import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'vrm_webview_adapter.dart';

final class AndroidVrmWebViewAdapter implements VrmWebViewAdapter {
  AndroidVrmWebViewAdapter({required this.backgroundColor});

  final Color backgroundColor;
  final WebViewController _controller =
      WebViewController.fromPlatformCreationParams(
        const PlatformWebViewControllerCreationParams(),
      );
  final StreamController<String> _messages =
      StreamController<String>.broadcast();
  final StreamController<String> _errors = StreamController<String>.broadcast();
  bool _disposed = false;

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<void> initialize() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setBackgroundColor(backgroundColor);
    await _controller.addJavaScriptChannel(
      'FlutterBridge',
      onMessageReceived: (message) {
        if (!_disposed) {
          _messages.add(message.message);
        }
      },
    );
    await _controller.setOnConsoleMessage((message) {
      debugPrint('VRM WebView JS [${message.level.name}]: ${message.message}');
    });
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onWebResourceError: (error) {
          if (!_disposed && error.isForMainFrame == true) {
            _errors.add(error.description);
          }
        },
      ),
    );
  }

  @override
  Widget buildWidget() => WebViewWidget(
    controller: _controller,
    gestureRecognizers: {
      Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
    },
  );

  @override
  Future<void> load(Uri uri) => _controller.loadRequest(uri);

  @override
  Future<void> runJavaScript(String source) =>
      _controller.runJavaScript(source);

  @override
  Future<Object?> runJavaScriptReturningResult(String source) =>
      _controller.runJavaScriptReturningResult(source);

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _messages.close();
    await _errors.close();
  }
}
