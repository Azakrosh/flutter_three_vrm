import '../bridge/vrm_protocol_contract.dart';
import '../content/vrm_content_host.dart';
import '../models/vrm_animation_options.dart';
import 'vrm_hosted_resource_dispatcher.dart';

typedef VrmAnimationCommandSender =
    Future<void> Function(
      VrmProtocolCommand action, [
      Map<String, dynamic>? payload,
    ]);

/// Internal animation command pipeline behind the public controller facade.
final class VrmAnimationDispatcher {
  VrmAnimationDispatcher(this._hostedResources, this._sendCommand);

  final VrmHostedResourceDispatcher _hostedResources;
  final VrmAnimationCommandSender _sendCommand;

  int _playbackSequence = 0;

  Future<VrmAnimationPlayback> playHosted({
    required Uri Function(VrmContentHost host) expose,
    required String fileName,
    required bool loop,
    required double speed,
    required double fadeDuration,
    required VrmRootMotion rootMotion,
    required String? clipName,
  }) {
    final options = _validatedOptions(
      fileName: fileName,
      loop: loop,
      speed: speed,
      fadeDuration: fadeDuration,
      rootMotion: rootMotion,
      clipName: clipName,
    );
    final playback = _createPlayback();
    return _hostedResources
        .send(
          expose: expose,
          action: VrmProtocolCommand.playAnimationFromUrl,
          fileName: fileName,
          payload: <String, dynamic>{
            'options': <String, dynamic>{
              ...options.toJson(),
              'playbackId': playback.id,
            },
          },
        )
        .then((_) => playback);
  }

  Future<VrmAnimationPlayback> playUrl(
    String url, {
    required bool loop,
    required double speed,
    required double fadeDuration,
    required VrmRootMotion rootMotion,
    required String? clipName,
  }) {
    _requireNonEmpty(url, 'url');
    final fileName = Uri.parse(url).pathSegments.lastOrNull ?? 'animation.vrma';
    final options = _validatedOptions(
      fileName: fileName,
      loop: loop,
      speed: speed,
      fadeDuration: fadeDuration,
      rootMotion: rootMotion,
      clipName: clipName,
    );
    final playback = _createPlayback();
    return _sendCommand(VrmProtocolCommand.playAnimationFromUrl, {
      'url': url,
      'fileName': fileName,
      'options': <String, dynamic>{
        ...options.toJson(),
        'playbackId': playback.id,
      },
    }).then((_) => playback);
  }

  Future<void> pause() => _sendCommand(VrmProtocolCommand.pauseAnimation);

  Future<void> resume({double speed = 1}) {
    _requirePositiveFinite(speed, 'speed');
    return _sendCommand(VrmProtocolCommand.resumeAnimation, {'speed': speed});
  }

  Future<void> cancelLoad() =>
      _sendCommand(VrmProtocolCommand.cancelAnimationLoad);

  Future<void> stop({double fadeDuration = 0.5}) {
    _requireNonNegativeFinite(fadeDuration, 'fadeDuration');
    return _sendCommand(VrmProtocolCommand.stopAnimation, {
      'fadeDuration': fadeDuration,
    });
  }

  Future<void> setSpeed(double speed) {
    _requirePositiveFinite(speed, 'speed');
    return _sendCommand(VrmProtocolCommand.setAnimationSpeed, {'speed': speed});
  }

  VrmAnimationOptions _validatedOptions({
    required String fileName,
    required bool loop,
    required double speed,
    required double fadeDuration,
    required VrmRootMotion rootMotion,
    required String? clipName,
  }) {
    _requireNonEmpty(fileName, 'fileName');
    final options = VrmAnimationOptions(
      loop: loop,
      speed: speed,
      fadeDuration: fadeDuration,
      rootMotion: rootMotion,
      clipName: clipName,
    );
    options.validate();
    return options;
  }

  VrmAnimationPlayback _createPlayback() {
    final id =
        'animation-${DateTime.now().microsecondsSinceEpoch}-'
        '${_playbackSequence++}';
    return VrmAnimationPlayback(id: id);
  }
}

void _requireNonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
}

void _requirePositiveFinite(double value, String name) {
  if (!value.isFinite || value <= 0) {
    throw ArgumentError.value(value, name, 'Must be positive and finite.');
  }
}

void _requireNonNegativeFinite(double value, String name) {
  if (!value.isFinite || value < 0) {
    throw ArgumentError.value(value, name, 'Must be non-negative and finite.');
  }
}
