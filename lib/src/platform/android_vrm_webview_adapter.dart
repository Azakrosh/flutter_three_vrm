import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'vrm_webview_adapter.dart';
import 'vrm_webview_adapter_lifecycle.dart';

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
  final VrmWebViewAdapterLifecycle _lifecycle = VrmWebViewAdapterLifecycle();

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<void> initialize() => _lifecycle.initialize(_initialize);

  Future<void> _initialize() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setBackgroundColor(backgroundColor);
    await _controller.addJavaScriptChannel(
      'FlutterBridge',
      onMessageReceived: (message) {
        try {
          _lifecycle.ensureActive();
          _messages.add(message.message);
        } on StateError {
          // Ignore callbacks delivered after terminal adapter disposal.
        }
      },
    );
    await _controller.setOnConsoleMessage((message) {
      debugPrint('VRM WebView JS [${message.level.name}]: ${message.message}');
    });
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onWebResourceError: (error) {
          if (error.isForMainFrame == true) {
            try {
              _lifecycle.ensureActive();
              _errors.add(error.description);
            } on StateError {
              // Ignore callbacks delivered after terminal adapter disposal.
            }
          }
        },
      ),
    );
  }

  @override
  Widget buildWidget() {
    _lifecycle.ensureActive();
    return WebViewWidget(
      controller: _controller,
      gestureRecognizers: {
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
    );
  }

  @override
  Future<void> load(Uri uri) =>
      _lifecycle.runOperation(() => _controller.loadRequest(uri));

  @override
  Future<void> runJavaScript(String source) =>
      _lifecycle.runOperation(() => _controller.runJavaScript(source));

  @override
  Future<Object?> runJavaScriptReturningResult(String source) => _lifecycle
      .runOperation(() => _controller.runJavaScriptReturningResult(source));

  @override
  Future<void> dispose() =>
      _lifecycle.dispose([_messages.close, _errors.close]);
}
