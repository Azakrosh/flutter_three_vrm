import '../bridge/vrm_protocol_contract.dart';
import '../models/vrm_graphics.dart';

typedef VrmGraphicsCommandSender =
    Future<void> Function(
      VrmProtocolCommand action, [
      Map<String, dynamic>? payload,
    ]);

typedef VrmGraphicsCommandRequester =
    Future<Object?> Function(
      VrmProtocolCommand action, [
      Map<String, dynamic>? payload,
    ]);

/// Owns renderer configuration validation and performance queries.
final class VrmGraphicsDispatcher {
  VrmGraphicsDispatcher(this._sendCommand, this._requestCommand);

  final VrmGraphicsCommandSender _sendCommand;
  final VrmGraphicsCommandRequester _requestCommand;

  Future<void> setPreset(VrmGraphicsPreset preset) {
    return _sendCommand(VrmProtocolCommand.setGraphicsPreset, {
      'preset': preset.name,
    });
  }

  Future<void> setAdaptiveQuality(VrmAdaptiveQualitySettings settings) {
    return _sendCommand(VrmProtocolCommand.setAdaptiveQuality, {
      'settings': settings.toJson(),
    });
  }

  Future<VrmPerformanceSnapshot> getPerformanceSnapshot() async {
    final result = await _requestCommand(
      VrmProtocolCommand.getPerformanceSnapshot,
    );
    return VrmPerformanceSnapshot.fromJson(result);
  }

  Future<void> setSettings({
    double? pixelRatio,
    bool? antialias,
    bool? enablePhysics,
    int? fpsCap,
  }) {
    if (pixelRatio != null) {
      _requirePositiveFinite(pixelRatio, 'pixelRatio');
    }
    if (fpsCap != null && (fpsCap < 0 || fpsCap > 120)) {
      throw ArgumentError.value(
        fpsCap,
        'fpsCap',
        'Must be zero or between 1 and 120.',
      );
    }

    return _sendCommand(VrmProtocolCommand.setGraphicsSettings, {
      'settings': <String, dynamic>{
        'pixelRatio': ?pixelRatio,
        'antialias': ?antialias,
        'enablePhysics': ?enablePhysics,
        'fpsCap': ?fpsCap,
      },
    });
  }
}

void _requirePositiveFinite(double value, String name) {
  if (!value.isFinite || value <= 0) {
    throw ArgumentError.value(value, name, 'Must be positive and finite.');
  }
}
