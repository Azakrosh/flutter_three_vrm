import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../bridge/vrm_protocol_contract.dart';
import '../models/vrm_wind.dart';
import 'vrm_hosted_resource_dispatcher.dart';

typedef VrmSceneCommandSender =
    Future<void> Function(
      VrmProtocolCommand action, [
      Map<String, dynamic>? payload,
    ]);

typedef VrmSceneCommandEmitter =
    void Function(VrmProtocolCommand action, [Map<String, dynamic>? payload]);

/// Owns scene, physics, wind, and background command construction.
final class VrmSceneDispatcher {
  VrmSceneDispatcher(
    this._hostedResources,
    this._sendCommand,
    this._emitCommand,
  );

  final VrmHostedResourceDispatcher _hostedResources;
  final VrmSceneCommandSender _sendCommand;
  final VrmSceneCommandEmitter _emitCommand;

  void setLighting({
    Color? ambientColor,
    double? ambientIntensity,
    Color? directionalColor,
    double? directionalIntensity,
  }) {
    if (ambientIntensity != null) {
      _requireNonNegativeFinite(ambientIntensity, 'ambientIntensity');
    }
    if (directionalIntensity != null) {
      _requireNonNegativeFinite(directionalIntensity, 'directionalIntensity');
    }
    _emitCommand(VrmProtocolCommand.setLighting, {
      if (ambientColor != null) 'ambientColor': _colorToHex(ambientColor),
      'ambientIntensity': ?ambientIntensity,
      if (directionalColor != null)
        'directionalColor': _colorToHex(directionalColor),
      'directionalIntensity': ?directionalIntensity,
    });
  }

  void setEnvironmentColor(Color color, {double intensity = 0.5}) {
    _requireUnitInterval(intensity, 'intensity');
    _emitCommand(VrmProtocolCommand.setEnvironmentColor, {
      'color': _colorToHex(color),
      'intensity': intensity,
    });
  }

  void setShadows(bool enabled) {
    _emitCommand(VrmProtocolCommand.setShadows, {'enabled': enabled});
  }

  void setPhysics({double stiffness = 1, double gravity = 1, double drag = 1}) {
    _requireNonNegativeFinite(stiffness, 'stiffness');
    _requireNonNegativeFinite(gravity, 'gravity');
    _requireNonNegativeFinite(drag, 'drag');
    _emitCommand(VrmProtocolCommand.setPhysics, {
      'stiffness': stiffness,
      'gravity': gravity,
      'drag': drag,
    });
  }

  void setWind({
    VrmWindType type = VrmWindType.none,
    VrmWindDirection direction = VrmWindDirection.right,
  }) {
    _emitCommand(VrmProtocolCommand.setWind, {
      'type': type.name,
      'direction': direction.name,
    });
  }

  void stopWind() {
    _emitCommand(VrmProtocolCommand.stopWind);
  }

  Future<void> setBackground({
    required Color color,
    bool transparent = false,
    String? imageAssetPath,
    String? imageUrl,
  }) async {
    if (imageAssetPath != null && imageUrl != null) {
      throw ArgumentError(
        'Provide either imageAssetPath or imageUrl, not both.',
      );
    }

    final payload = <String, dynamic>{
      'color': _colorToHex(color),
      'transparent': transparent,
    };
    if (imageAssetPath != null) {
      await _hostedResources.send(
        expose: (host) => host.exposeAsset(imageAssetPath),
        action: VrmProtocolCommand.setBackground,
        fileName: p.basename(imageAssetPath),
        urlField: 'imageUrl',
        payload: <String, dynamic>{...payload, 'hostedImage': true},
      );
      return;
    }

    await _sendCommand(VrmProtocolCommand.setBackground, {
      ...payload,
      'imageUrl': ?imageUrl,
      'hostedImage': false,
    });
  }

  Future<void> setBackgroundFromFile(
    io.File file, {
    required Color color,
    bool transparent = false,
  }) {
    return _hostedResources.send(
      expose: (host) => host.exposeFile(file),
      action: VrmProtocolCommand.setBackground,
      fileName: p.basename(file.path),
      urlField: 'imageUrl',
      payload: <String, dynamic>{
        'color': _colorToHex(color),
        'transparent': transparent,
        'hostedImage': true,
      },
    );
  }

  Future<void> setBackgroundFromBytes(
    Uint8List bytes, {
    required String fileName,
    required Color color,
    bool transparent = false,
  }) {
    if (fileName.trim().isEmpty) {
      throw ArgumentError.value(fileName, 'fileName', 'Must not be empty.');
    }
    return _hostedResources.send(
      expose: (host) => host.exposeBytes(bytes, fileName: fileName),
      action: VrmProtocolCommand.setBackground,
      fileName: fileName,
      urlField: 'imageUrl',
      payload: <String, dynamic>{
        'color': _colorToHex(color),
        'transparent': transparent,
        'hostedImage': true,
      },
    );
  }
}

String _colorToHex(Color color) {
  final hex = color.toARGB32().toRadixString(16).padLeft(8, '0');
  return '#${hex.substring(2)}';
}

void _requireNonNegativeFinite(double value, String name) {
  if (!value.isFinite || value < 0) {
    throw ArgumentError.value(value, name, 'Must be non-negative and finite.');
  }
}

void _requireUnitInterval(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(
      value,
      name,
      'Must be finite and between 0 and 1.',
    );
  }
}
