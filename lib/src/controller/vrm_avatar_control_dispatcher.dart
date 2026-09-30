import 'package:flutter/widgets.dart';

import '../bridge/vrm_protocol_contract.dart';
import '../models/vrm_expression.dart';
import '../models/vrm_pose.dart';
import 'vrm_speech_dispatcher.dart';

typedef VrmAvatarCommandSender =
    Future<void> Function(
      VrmProtocolCommand action, [
      Map<String, dynamic>? payload,
    ]);

typedef VrmAvatarCommandRequester =
    Future<Object?> Function(
      VrmProtocolCommand action, [
      Map<String, dynamic>? payload,
    ]);

typedef VrmAvatarCommandEmitter =
    void Function(VrmProtocolCommand action, [Map<String, dynamic>? payload]);

typedef VrmAvatarLatestCommandSender =
    void Function({
      required String channel,
      required VrmProtocolCommand action,
      required Map<String, dynamic> payload,
    });

/// Internal command boundary for pose, face, and programmatic gaze controls.
final class VrmAvatarControlDispatcher {
  VrmAvatarControlDispatcher(
    this._ensureActive,
    this._sendCommand,
    this._requestCommand,
    this._emitCommand,
    this._sendLatestCommand,
    this._speech,
  );

  final void Function() _ensureActive;
  final VrmAvatarCommandSender _sendCommand;
  final VrmAvatarCommandRequester _requestCommand;
  final VrmAvatarCommandEmitter _emitCommand;
  final VrmAvatarLatestCommandSender _sendLatestCommand;
  final VrmSpeechDispatcher _speech;

  Future<VrmPose> getPose() async {
    final result = await _requestCommand(VrmProtocolCommand.getPose);
    return VrmPose.fromJson(result);
  }

  Future<void> setPose(VrmPose pose, {double fadeDuration = 0.5}) {
    _requireNonNegativeFinite(fadeDuration, 'fadeDuration');
    return _sendCommand(VrmProtocolCommand.setPose, {
      'pose': pose.toJson(),
      'fadeDuration': fadeDuration,
    });
  }

  Future<void> resetPose({double fadeDuration = 0.5}) {
    _requireNonNegativeFinite(fadeDuration, 'fadeDuration');
    return _sendCommand(VrmProtocolCommand.resetPose, {
      'fadeDuration': fadeDuration,
    });
  }

  void setExpression(
    VrmExpression expression, {
    ExpressionLayer? layer,
    double weight = 1.0,
    Duration duration = const Duration(milliseconds: 250),
    bool disableAutoBlink = false,
  }) {
    _requireUnitInterval(weight, 'weight');
    _requireNonNegativeDuration(duration, 'duration');
    final resolvedLayer = layer ?? expression.defaultLayer;
    final speechRevision = resolvedLayer == ExpressionLayer.mouth
        ? _speech.takeMouthControl()
        : null;
    _emitCommand(VrmProtocolCommand.setExpression, {
      'expression': expression.name,
      'layer': resolvedLayer.name,
      'weight': weight,
      'duration': duration.inMilliseconds / 1000.0,
      'disableAutoBlink': disableAutoBlink,
      'speechRevision': ?speechRevision,
    });
  }

  void clearExpressionLayer(ExpressionLayer layer) {
    final speechRevision = layer == ExpressionLayer.mouth
        ? _speech.takeMouthControl()
        : null;
    _emitCommand(VrmProtocolCommand.clearExpressionLayer, {
      'layer': layer.name,
      'speechRevision': ?speechRevision,
    });
  }

  void clearAllExpressions() {
    _emitCommand(VrmProtocolCommand.clearAllExpressions, {
      'speechRevision': _speech.takeMouthControl(),
    });
  }

  void setCustomBlendShape(String name, double weight) {
    _requireNonEmpty(name, 'name');
    _requireUnitInterval(weight, 'weight');
    _emitCommand(VrmProtocolCommand.setCustomBlendShape, {
      'name': name,
      'weight': weight,
    });
  }

  void setAutoSaccades({bool enabled = true}) {
    _emitCommand(VrmProtocolCommand.setAutoSaccades, {'enabled': enabled});
  }

  void setAutoBlink(bool enabled) {
    _emitCommand(VrmProtocolCommand.setAutoBlink, {'enabled': enabled});
  }

  void setLookAtTarget(Offset screenPosition) {
    _ensureActive();
    if (!screenPosition.dx.isFinite || !screenPosition.dy.isFinite) {
      throw ArgumentError.value(
        screenPosition,
        'screenPosition',
        'Coordinates must be finite.',
      );
    }
    _sendLatestCommand(
      channel: 'lookAtTarget',
      action: VrmProtocolCommand.setLookAtTarget,
      payload: {'x': screenPosition.dx, 'y': screenPosition.dy},
    );
  }

  void setLookAtConfig({Duration? holdDuration}) {
    if (holdDuration != null) {
      _requireNonNegativeDuration(holdDuration, 'holdDuration');
    }
    _emitCommand(VrmProtocolCommand.setLookAtConfig, {
      if (holdDuration != null)
        'holdDurationSec': holdDuration.inMilliseconds / 1000.0,
    });
  }
}

void _requireNonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
}

void _requireNonNegativeFinite(double value, String name) {
  if (!value.isFinite || value < 0) {
    throw ArgumentError.value(value, name, 'Must be finite and non-negative.');
  }
}

void _requireUnitInterval(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(value, name, 'Must be between 0 and 1.');
  }
}

void _requireNonNegativeDuration(Duration value, String name) {
  if (value.isNegative) {
    throw ArgumentError.value(value, name, 'Must not be negative.');
  }
}
