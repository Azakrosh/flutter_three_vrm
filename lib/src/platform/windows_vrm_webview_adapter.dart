import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import 'vrm_webview_adapter.dart';
import 'vrm_webview_adapter_lifecycle.dart';

final class WindowsVrmWebViewAdapter implements VrmWebViewAdapter {
  WindowsVrmWebViewAdapter({required this.backgroundColor});

  final Color backgroundColor;
  final WebviewController _controller = WebviewController();
  final VrmWebViewAdapterLifecycle _lifecycle = VrmWebViewAdapterLifecycle();

  @override
  Stream<String> get messages => _controller.webMessage.map(
    (message) => message is String ? message : jsonEncode(message),
  );

  @override
  Stream<String> get errors =>
      _controller.onLoadError.map((error) => error.toString());

  @override
  Future<void> initialize() => _lifecycle.initialize(_initialize);

  Future<void> _initialize() async {
    await _controller.initialize();
    await _controller.setBackgroundColor(backgroundColor);
    await _controller.setDefaultContextMenusEnabled(false);
  }

  @override
  Widget buildWidget() {
    _lifecycle.ensureActive();
    return Webview(_controller);
  }

  @override
  Future<void> load(Uri uri) =>
      _lifecycle.runOperation(() => _controller.loadUrl(uri.toString()));

  @override
  Future<void> runJavaScript(String source) =>
      _lifecycle.runOperation(() async => _controller.executeScript(source));

  @override
  Future<Object?> runJavaScriptReturningResult(String source) =>
      _lifecycle.runOperation(() => _controller.executeScript(source));

  @override
  Future<void> dispose() => _lifecycle.dispose([_controller.dispose]);
}
