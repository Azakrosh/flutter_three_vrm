import 'vrm_expression.dart';
import 'vrm_graphics.dart';
import 'vrm_model_report.dart';

/// Base event class emitted by the VRM controller.
abstract class VrmEvent {
  final DateTime timestamp;
  VrmEvent() : timestamp = DateTime.now();
}

/// Emitted when a VRM model is successfully loaded and added to the scene.
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

/// Emitted after the runtime has inspected a newly loaded VRM model.
class VrmModelReportEvent extends VrmEvent {
  VrmModelReportEvent({required this.report});

  final VrmModelReport report;
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

/// Emitted when the user changes pan or zoom.
class VrmCameraChangedEvent extends VrmEvent {
  final double? x;
  final double? y;
  final double? zoom;

  VrmCameraChangedEvent({this.x, this.y, this.zoom});
}

/// Periodic renderer workload telemetry and adaptive-quality changes.
class VrmPerformanceEvent extends VrmEvent {
  VrmPerformanceEvent({required this.snapshot});

  final VrmPerformanceSnapshot snapshot;
}

/// Emitted when Android or Windows loses or restores its WebGL context.
class VrmWebGlContextEvent extends VrmEvent {
  VrmWebGlContextEvent({required this.state});

  final VrmWebGlContextState state;
}

/// Emitted when user taps or clicks on the 3D view.
class VrmTapEvent extends VrmEvent {
  final double x;
  final double y;

  VrmTapEvent({required this.x, required this.y});
}
