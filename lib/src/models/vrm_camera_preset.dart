/// Control modes for the VRM camera.
enum VrmCameraMode {
  /// Character Creator Orbit: rotate only around Y-axis, restricted zoom range to head/body
  characterCreator,

  /// Locked preset mode: camera is locked to a fixed camera preset view
  preset,

  /// Free orbit mode: unconstrained orbit controls for debugging or custom navigation
  free;

  /// Parses a string representation into a [VrmCameraMode].
  /// Defaults to [VrmCameraMode.characterCreator] if the string doesn't match.
  static VrmCameraMode fromString(String value) {
    final normalized = value.trim().toLowerCase();
    for (final mode in VrmCameraMode.values) {
      if (mode.name.toLowerCase() == normalized) {
        return mode;
      }
    }
    return VrmCameraMode.characterCreator;
  }
}

