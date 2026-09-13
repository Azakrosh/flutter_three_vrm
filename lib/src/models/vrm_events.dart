import 'vrm_expression.dart';

/// Base event class emitted by the VRM controller.
abstract class VrmEvent {
  final DateTime timestamp;
  VrmEvent() : timestamp = DateTime.now();
}

/// Emitted when a VRM 1.0 model is successfully loaded and added to the 3D scene.
class VrmModelLoadedEvent extends VrmEvent {
  final String name;
  final String version;

  VrmModelLoadedEvent({required this.name, required this.version});
}

/// Emitted repeatedly during model download to report loading progress.
/// [percent] ranges from 0 to 100.
/// [loaded] and [total] are byte counts; [total] may be 0 if the server
/// does not report Content-Length.
class VrmModelLoadProgressEvent extends VrmEvent {
  final int percent;
  final int loaded;
  final int total;

  VrmModelLoadProgressEvent({
    required this.percent,
    required this.loaded,
    required this.total,
  });
}

/// Emitted when the current VRM model is unloaded from the scene.
class VrmModelUnloadedEvent extends VrmEvent {}

/// Emitted when a VRMA animation clip starts playing.
class VrmAnimationStartedEvent extends VrmEvent {
  final String name;

  VrmAnimationStartedEvent({required this.name});
}

/// Emitted when a non-looping VRMA animation clip finishes playing.
class VrmAnimationFinishedEvent extends VrmEvent {
  final String name;

  VrmAnimationFinishedEvent({required this.name});
}

/// Emitted when an expression layer changes target expression or weight.
class VrmExpressionChangedEvent extends VrmEvent {
  final VrmExpression expression;
  final ExpressionLayer layer;

  VrmExpressionChangedEvent({required this.expression, required this.layer});
}

/// Emitted when queued speech viseme frames complete playback.
class VrmSpeechFinishedEvent extends VrmEvent {}

/// Emitted when an error occurs during model loading or rendering in WebGL.
class VrmErrorEvent extends VrmEvent {
  final String message;

  VrmErrorEvent({required this.message});
}

/// Emitted when WebGL engine internal state changes.
class VrmStateChangedEvent extends VrmEvent {
  final String state;

  VrmStateChangedEvent({required this.state});
}

/// Emitted when camera view changes.
class VrmCameraChangedEvent extends VrmEvent {
  final String preset;

  VrmCameraChangedEvent({required this.preset});
}

/// Emitted when user taps or clicks on the 3D view.
class VrmTapEvent extends VrmEvent {
  final double x;
  final double y;

  VrmTapEvent({required this.x, required this.y});
}
