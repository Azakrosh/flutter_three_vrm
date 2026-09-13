import 'package:flutter/widgets.dart';

/// Platform-neutral WebView surface used by the VRM runtime.
abstract interface class VrmWebViewAdapter {
  Stream<String> get messages;

  Stream<String> get errors;

  Widget buildWidget();

  Future<void> initialize();

  Future<void> load(Uri uri);

  Future<void> runJavaScript(String source);

  Future<Object?> runJavaScriptReturningResult(String source);

  Future<void> dispose();
}
