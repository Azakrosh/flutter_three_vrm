/// Controls how application lifecycle changes affect the WebGL render loop.
enum VrmRenderLifecyclePolicy {
  /// Uses a focused-only policy on Android and a visible-only policy on Windows.
  platformDefault,

  /// Keeps rendering while visible, including when the window loses focus.
  pauseWhenHidden,

  /// Renders only while the application has input focus.
  pauseWhenUnfocused,
}
