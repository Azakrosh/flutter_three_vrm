import 'vrm_expression.dart';
import 'vrm_wind.dart';

/// Wind configuration for a mood preset.
class VrmMoodWind {
  final VrmWindType type;
  final VrmWindDirection direction;

  const VrmMoodWind({
    required this.type,
    this.direction = VrmWindDirection.right,
  });
}

/// Physics configuration for a mood preset.
class VrmMoodPhysics {
  final double stiffness;
  final double gravity;
  final double drag;

  const VrmMoodPhysics({
    this.stiffness = 1.0,
    this.gravity = 1.0,
    this.drag = 1.0,
  });
}

/// High-level emotional preset that combines expression, wind, and physics
/// into a single API call.
///
/// Use the built-in static presets or create custom ones:
/// ```dart
/// controller.setMood(VrmMood.happy);
/// controller.setMood(VrmMood.thinking);
/// controller.clearMood();
///
/// controller.setMood(VrmMood.custom(
///   expression: VrmExpression.sad,
///   expressionWeight: 0.7,
///   wind: VrmMoodWind(type: VrmWindType.light),
/// ));
/// ```
class VrmMood {
  /// Expression applied to the eyes layer (happy, relaxed, surprised, etc.).
  final VrmExpression? expression;

  /// Weight of the eyes expression (0.0–1.0).
  final double expressionWeight;

  /// Expression applied to the brows layer (angry, sad).
  final VrmExpression? browExpression;

  /// Weight of the brows expression (0.0–1.0).
  final double browWeight;

  /// Optional wind effect.
  final VrmMoodWind? wind;

  /// Optional physics adjustments.
  final VrmMoodPhysics? physics;

  /// Whether to enable auto-saccades (random eye movements).
  /// `null` means don't change the current setting.
  final bool? autoSaccades;

  const VrmMood({
    this.expression,
    this.expressionWeight = 1.0,
    this.browExpression,
    this.browWeight = 1.0,
    this.wind,
    this.physics,
    this.autoSaccades,
  });

  /// Creates a custom mood preset.
  factory VrmMood.custom({
    VrmExpression? expression,
    double expressionWeight = 1.0,
    VrmExpression? browExpression,
    double browWeight = 1.0,
    VrmMoodWind? wind,
    VrmMoodPhysics? physics,
    bool? autoSaccades,
  }) {
    return VrmMood(
      expression: expression,
      expressionWeight: expressionWeight,
      browExpression: browExpression,
      browWeight: browWeight,
      wind: wind,
      physics: physics,
      autoSaccades: autoSaccades,
    );
  }

  // ---------------------------------------------------------------------------
  // Built-in presets
  // ---------------------------------------------------------------------------

  /// Joyful expression with light breeze.
  static const happy = VrmMood(
    expression: VrmExpression.happy,
    expressionWeight: 1.0,
    wind: VrmMoodWind(type: VrmWindType.light, direction: VrmWindDirection.right),
    autoSaccades: true,
  );

  /// Melancholic expression with softer physics.
  static const sad = VrmMood(
    expression: VrmExpression.relaxed,
    expressionWeight: 0.5,
    browExpression: VrmExpression.sad,
    browWeight: 0.8,
    physics: VrmMoodPhysics(stiffness: 0.6),
    autoSaccades: false,
  );

  /// Intense expression with strong wind.
  static const angry = VrmMood(
    expression: VrmExpression.angry,
    expressionWeight: 0.3,
    browExpression: VrmExpression.angry,
    browWeight: 1.0,
    wind: VrmMoodWind(type: VrmWindType.strong, direction: VrmWindDirection.front),
    physics: VrmMoodPhysics(stiffness: 1.5),
    autoSaccades: true,
  );

  /// Contemplative — subtle relaxed eyes, no saccades.
  static const thinking = VrmMood(
    expression: VrmExpression.relaxed,
    expressionWeight: 0.3,
    autoSaccades: false,
  );

  /// Wide-eyed surprise with light physics.
  static const surprised = VrmMood(
    expression: VrmExpression.surprised,
    expressionWeight: 1.0,
    wind: VrmMoodWind(type: VrmWindType.light, direction: VrmWindDirection.front),
    physics: VrmMoodPhysics(gravity: 0.5),
    autoSaccades: true,
  );

  /// Calm and peaceful with gentle breeze.
  static const relaxed = VrmMood(
    expression: VrmExpression.relaxed,
    expressionWeight: 0.8,
    wind: VrmMoodWind(type: VrmWindType.light, direction: VrmWindDirection.right),
    physics: VrmMoodPhysics(stiffness: 0.7),
    autoSaccades: true,
  );

  /// Resets everything to default.
  static const neutral = VrmMood(
    expression: VrmExpression.neutral,
    expressionWeight: 0.0,
    autoSaccades: true,
  );
}
