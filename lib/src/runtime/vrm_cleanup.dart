typedef VrmCleanupPhase = Future<void> Function();

/// Runs every cleanup phase and rethrows the first failure afterwards.
Future<void> runVrmCleanupPhases(Iterable<VrmCleanupPhase> phases) async {
  Object? firstError;
  StackTrace? firstStackTrace;

  for (final phase in phases) {
    try {
      await phase();
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
  }

  if (firstError case final error?) {
    Error.throwWithStackTrace(error, firstStackTrace!);
  }
}
