/// High-level Flutter API for displaying and controlling one VRM avatar on
/// Android and Windows.
///
/// The package owns the embedded WebView runtime and exposes typed model,
/// animation, pose, expression, speech-timeline, camera, scene, performance,
/// lifecycle, and recovery controls without exposing Three.js internals.
library;

export 'src/vrm_runtime.dart';
export 'src/models/vrm_expression.dart';
export 'src/models/vrm_graphics.dart';
export 'src/models/vrm_host_resources.dart';
export 'src/models/vrm_camera_mode.dart';
export 'src/models/vrm_animation_options.dart';
export 'src/models/vrm_lip_sync_data.dart';
export 'src/models/vrm_events.dart';
export 'src/models/vrm_exception.dart';
export 'src/models/vrm_wind.dart';
export 'src/models/vrm_mood.dart';
export 'src/models/vrm_model_report.dart';
export 'src/models/vrm_model_performance.dart';
export 'src/models/vrm_pose.dart';
export 'src/models/vrm_runtime_health.dart';
export 'src/models/vrm_transform.dart';
export 'src/models/vrm_render_lifecycle_policy.dart';
export 'src/animation_queue/vrm_animation_queue.dart';
export 'src/animation_queue/vrm_animation_queue_state.dart';
export 'src/animation_queue/vrm_animation_queue_snapshot.dart';
