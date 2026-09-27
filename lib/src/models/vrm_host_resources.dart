/// Thermal state reported by the host operating system.
///
/// [unavailable] means that the current platform adapter cannot provide a
/// trustworthy thermal signal. It must not be interpreted as [none].
enum VrmThermalStatus {
  unavailable,
  none,
  light,
  moderate,
  severe,
  critical,
  emergency,
  shutdown,
}

/// Point-in-time resource diagnostics for the Flutter host process.
///
/// RSS values describe the complete application process rather than only the
/// embedded VRM runtime. Their exact accounting is platform dependent, so they
/// are intended for trends and comparable soak runs instead of hard limits.
final class VrmHostResourceSnapshot {
  const VrmHostResourceSnapshot({
    required this.capturedAt,
    required this.currentRssBytes,
    required this.maxRssBytes,
    required this.memoryPressureCount,
    required this.thermalStatus,
  });

  final DateTime capturedAt;
  final int currentRssBytes;

  /// Greatest non-negative value observed by this monitor from either the
  /// platform peak reader or [currentRssBytes].
  ///
  /// Some Android runtimes report a platform max RSS below a previously read
  /// current RSS. The monitor normalizes that platform inconsistency and keeps
  /// this value monotonic for the lifetime of the controller.
  final int maxRssBytes;

  /// Number of low-memory notifications observed since controller creation.
  final int memoryPressureCount;

  final VrmThermalStatus thermalStatus;
}
