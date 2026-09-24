import '../models/vrm_events.dart';
import '../models/vrm_expression.dart';
import '../models/vrm_graphics.dart';
import '../models/vrm_model_report.dart';
import 'vrm_protocol_contract.dart';

/// Decodes the internal WebView event envelope without applying fallback data.
VrmEvent decodeVrmRuntimeEventEnvelope(Map<String, dynamic> envelope) {
  if (envelope['version'] != vrmProtocolVersion) {
    throw FormatException(
      'Unsupported VRM protocol version: ${envelope['version']}.',
    );
  }
  if (envelope['type'] != 'event') {
    throw const FormatException('Expected a VRM event envelope.');
  }
  final eventName = _requireNonEmptyString(envelope, 'event');
  final event = vrmProtocolEventFromWireName(eventName);
  if (event == null) {
    throw FormatException('Unknown VRM runtime event: $eventName.');
  }
  final rawPayload = envelope['payload'];
  if (rawPayload is! Map<String, dynamic>) {
    throw FormatException('VRM runtime event $eventName payload is invalid.');
  }
  final payload = rawPayload;

  return switch (event) {
    VrmProtocolEvent.onModelLoaded => VrmModelLoadedEvent(
      name: _requireNonEmptyString(payload, 'name'),
      version: _requireNonEmptyString(payload, 'version'),
    ),
    VrmProtocolEvent.onModelLoadProgress => _decodeModelLoadProgress(payload),
    VrmProtocolEvent.onModelReport => VrmModelReportEvent(
      report: VrmModelReport.fromJson(payload),
    ),
    VrmProtocolEvent.onModelUnloaded => _decodeModelUnloaded(payload),
    VrmProtocolEvent.onAnimationStarted => VrmAnimationStartedEvent(
      name: _requireNonEmptyString(payload, 'name'),
      playbackId: _requireNonEmptyString(payload, 'playbackId'),
    ),
    VrmProtocolEvent.onAnimationFinished => VrmAnimationFinishedEvent(
      name: _requireNonEmptyString(payload, 'name'),
      playbackId: _requireNonEmptyString(payload, 'playbackId'),
    ),
    VrmProtocolEvent.onExpressionChanged => VrmExpressionChangedEvent(
      expression: _requireExpression(payload['expression']),
      layer: _requireExpressionLayer(payload['layer']),
    ),
    VrmProtocolEvent.onSpeechFinished => VrmSpeechFinishedEvent(
      sessionId: _requireNonEmptyString(payload, 'sessionId'),
    ),
    VrmProtocolEvent.onError => VrmErrorEvent(
      message: _requireNonEmptyString(payload, 'message'),
    ),
    VrmProtocolEvent.onStateChanged => _decodeStateChanged(payload),
    VrmProtocolEvent.onCameraChanged => _decodeCameraChanged(payload),
    VrmProtocolEvent.onPerformance => _decodePerformance(payload),
    VrmProtocolEvent.onWebGlContextChanged => _decodeWebGlContext(payload),
    VrmProtocolEvent.onTap => VrmTapEvent(
      x: _requireFiniteDouble(payload, 'x'),
      y: _requireFiniteDouble(payload, 'y'),
    ),
  };
}

VrmModelLoadProgressEvent _decodeModelLoadProgress(
  Map<String, dynamic> payload,
) {
  final percent = _requireNonNegativeInteger(payload, 'percent');
  final loaded = _requireNonNegativeInteger(payload, 'loaded');
  final total = _requireNonNegativeInteger(payload, 'total');
  if (percent > 100) {
    throw const FormatException('percent must not exceed 100.');
  }
  if (total > 0 && loaded > total) {
    throw const FormatException('loaded must not exceed total.');
  }
  return VrmModelLoadProgressEvent(
    percent: percent,
    loaded: loaded,
    total: total,
  );
}

VrmModelUnloadedEvent _decodeModelUnloaded(Map<String, dynamic> payload) {
  if (payload.isNotEmpty) {
    throw const FormatException('Model unloaded event payload must be empty.');
  }
  return VrmModelUnloadedEvent();
}

VrmStateChangedEvent _decodeStateChanged(Map<String, dynamic> payload) {
  final state = _requireNonEmptyString(payload, 'state');
  if (state != 'initialized') {
    throw FormatException('Unknown VRM runtime state: $state.');
  }
  return VrmStateChangedEvent(state: state);
}

VrmCameraChangedEvent _decodeCameraChanged(Map<String, dynamic> payload) {
  final zoom = _requireFiniteDouble(payload, 'zoom');
  if (zoom <= 0) {
    throw const FormatException('zoom must be positive.');
  }
  return VrmCameraChangedEvent(
    x: _requireFiniteDouble(payload, 'x'),
    y: _requireFiniteDouble(payload, 'y'),
    zoom: zoom,
    userInitiated: _requireBool(payload, 'userInitiated'),
  );
}

VrmWebGlContextEvent _decodeWebGlContext(Map<String, dynamic> payload) {
  final state = switch (payload['state']) {
    'lost' => VrmWebGlContextState.lost,
    'restored' => VrmWebGlContextState.restored,
    _ => throw const FormatException('Unknown WebGL context state.'),
  };
  return VrmWebGlContextEvent(state: state);
}

VrmPerformanceEvent _decodePerformance(Map<String, dynamic> payload) {
  final snapshot = VrmPerformanceSnapshot.fromJson(payload);
  if (snapshot.fps < 0 ||
      snapshot.frameTimeMs < 0 ||
      snapshot.frameTimeP50Ms < 0 ||
      snapshot.frameTimeP95Ms < 0 ||
      snapshot.fpsCap < 0) {
    throw const FormatException(
      'Performance timing values must be non-negative.',
    );
  }
  if (snapshot.pixelRatio <= 0) {
    throw const FormatException('Performance pixelRatio must be positive.');
  }
  if (snapshot.drawCalls < 0 ||
      snapshot.triangles < 0 ||
      snapshot.geometries < 0 ||
      snapshot.textures < 0) {
    throw const FormatException(
      'Performance renderer counters must be non-negative.',
    );
  }
  return VrmPerformanceEvent(snapshot: snapshot);
}

VrmExpression _requireExpression(Object? value) {
  if (value is String) {
    for (final expression in VrmExpression.values) {
      if (expression.name == value) return expression;
    }
  }
  throw const FormatException('Unknown VRM expression.');
}

ExpressionLayer _requireExpressionLayer(Object? value) {
  if (value is String) {
    for (final layer in ExpressionLayer.values) {
      if (layer.name == value) return layer;
    }
  }
  throw const FormatException('Unknown VRM expression layer.');
}

String _requireNonEmptyString(Map<String, dynamic> source, String field) {
  final value = source[field];
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value;
}

int _requireNonNegativeInteger(Map<String, dynamic> source, String field) {
  final value = source[field];
  if (value is! num ||
      !value.isFinite ||
      value != value.truncate() ||
      value < 0) {
    throw FormatException('$field must be a non-negative integer.');
  }
  return value.toInt();
}

double _requireFiniteDouble(Map<String, dynamic> source, String field) {
  final value = source[field];
  if (value is! num || !value.isFinite) {
    throw FormatException('$field must be a finite number.');
  }
  return value.toDouble();
}

bool _requireBool(Map<String, dynamic> source, String field) {
  final value = source[field];
  if (value is! bool) {
    throw FormatException('$field must be a boolean.');
  }
  return value;
}
