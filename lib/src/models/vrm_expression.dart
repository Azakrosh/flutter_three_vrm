/// Presets for VRM 1.0 standard expressions.
enum VrmExpression {
  happy,
  sad,
  angry,
  relaxed,
  surprised,
  neutral,
  blink,
  blinkLeft,
  blinkRight,
  aa,
  ih,
  ou,
  ee,
  oh;

  /// Returns the recommended [ExpressionLayer] for this expression.
  /// For example, visemes go to the mouth layer, while blinks go to the eyes.
  ExpressionLayer get defaultLayer {
    switch (this) {
      case VrmExpression.aa:
      case VrmExpression.ih:
      case VrmExpression.ou:
      case VrmExpression.ee:
      case VrmExpression.oh:
        return ExpressionLayer.mouth;
      case VrmExpression.angry:
      case VrmExpression.sad:
        return ExpressionLayer.brows;
      case VrmExpression.blink:
      case VrmExpression.blinkLeft:
      case VrmExpression.blinkRight:
      case VrmExpression.happy:
      case VrmExpression.relaxed:
      case VrmExpression.surprised:
      case VrmExpression.neutral:
        return ExpressionLayer.eyes;
    }
  }

  /// Parses a string representation into a [VrmExpression].
  /// Defaults to [VrmExpression.neutral] if the string doesn't match.
  static VrmExpression fromString(String value) {
    final normalized = value.trim().toLowerCase();
    for (final expr in VrmExpression.values) {
      if (expr.name.toLowerCase() == normalized) {
        return expr;
      }
    }
    return VrmExpression.neutral;
  }
}

/// Independent expression layers to prevent conflicting blendshapes.
enum ExpressionLayer {
  /// Eye & upper face expressions (happy eyes, blink, surprised)
  eyes,

  /// Mouth & speech expressions (lip sync visemes, open mouth)
  mouth,

  /// Eyebrow & pose expressions (angry brows, sad brows)
  brows;

  /// Parses a string representation into an [ExpressionLayer].
  static ExpressionLayer fromString(String value) {
    final normalized = value.trim().toLowerCase();
    for (final layer in ExpressionLayer.values) {
      if (layer.name.toLowerCase() == normalized) {
        return layer;
      }
    }
    return ExpressionLayer.eyes;
  }
}
