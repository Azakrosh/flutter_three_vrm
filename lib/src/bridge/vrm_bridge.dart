import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/vrm_events.dart';
import '../models/vrm_expression.dart';

class VrmBridge {
  WebViewController? _webViewController;

  final StreamController<VrmEvent> _eventController = StreamController<VrmEvent>.broadcast();
  Stream<VrmEvent> get eventStream => _eventController.stream;

  void attachController(WebViewController webViewController) {
    _webViewController = webViewController;
  }

  /// Handles incoming JavaScript messages from WebView bridge
  void handleJsMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final event = data['event'] as String?;
      final payload = data['payload'] as Map<String, dynamic>? ?? {};

      if (event == null) return;

      switch (event) {
        case 'onModelLoaded':
          _eventController.add(VrmModelLoadedEvent(
            name: payload['name'] ?? 'VRM Model',
            version: payload['version'] ?? '1.0',
          ));
          break;
        case 'onModelLoadProgress':
          _eventController.add(VrmModelLoadProgressEvent(
            percent: (payload['percent'] as num?)?.toInt() ?? 0,
            loaded: (payload['loaded'] as num?)?.toInt() ?? 0,
            total: (payload['total'] as num?)?.toInt() ?? 0,
          ));
          break;
        case 'onModelUnloaded':
          _eventController.add(VrmModelUnloadedEvent());
          break;
        case 'onAnimationStarted':
          _eventController.add(VrmAnimationStartedEvent(name: payload['name'] ?? 'Animation'));
          break;
        case 'onAnimationFinished':
          _eventController.add(VrmAnimationFinishedEvent(name: payload['name'] ?? 'Animation'));
          break;
        case 'onExpressionChanged':
          _eventController.add(VrmExpressionChangedEvent(
            expression: VrmExpression.fromString(payload['expression'] ?? ''),
            layer: ExpressionLayer.fromString(payload['layer'] ?? ''),
          ));
          break;
        case 'onSpeechFinished':
          _eventController.add(VrmSpeechFinishedEvent());
          break;
        case 'onError':
          _eventController.add(VrmErrorEvent(message: payload['message'] ?? 'Unknown WebGL error'));
          break;
        case 'onStateChanged':
          _eventController.add(VrmStateChangedEvent(state: payload['state'] ?? ''));
          break;
        case 'onCameraChanged':
          _eventController.add(VrmCameraChangedEvent(
            preset: payload['preset'] ?? 'upperBody',
          ));
          break;
        case 'onTap':
          _eventController.add(VrmTapEvent(
            x: (payload['x'] as num?)?.toDouble() ?? 0.0,
            y: (payload['y'] as num?)?.toDouble() ?? 0.0,
          ));
          break;
        default:
          debugPrint('Unknown VRM WebGL Event: $event');
      }
    } catch (e) {
      debugPrint('Error parsing JS message: $e');
    }
  }

  /// Sends a command and payload to the JavaScript runner
  Future<void> sendCommand(String action, [Map<String, dynamic>? payload]) async {
    if (_webViewController == null) return;

    final map = Map<String, dynamic>.from(payload ?? {});
    final payloadJson = jsonEncode(map);
    
    // jsonEncode(payloadJson) escapes the JSON string safely for JS injection.
    final safePayload = jsonEncode(payloadJson);
    final jsCode = "if (window.flutterVrmInvoke) { window.flutterVrmInvoke('$action', $safePayload); }";
    await _webViewController!.runJavaScript(jsCode);
  }

  /// Evaluates JavaScript and returns the result
  Future<Object?> evalJavaScript(String jsCode) async {
    if (_webViewController == null) return null;
    return await _webViewController!.runJavaScriptReturningResult(jsCode);
  }

  void dispose() {
    _eventController.close();
  }
}
