/// Defines the strength and style of the wind simulation.
enum VrmWindType {
  /// No wind effect
  none,

  /// Gentle breeze affecting hair and cloth
  light,

  /// Moderate wind with visible cloth movement
  strong,

  /// Intense storm-like wind
  storm,
}

/// Defines the direction the wind is blowing from the camera's perspective.
enum VrmWindDirection {
  /// Wind blowing to the left
  left,

  /// Wind blowing to the right
  right,

  /// Wind blowing towards the camera
  front,

  /// Wind blowing away from the camera
  back,
}
