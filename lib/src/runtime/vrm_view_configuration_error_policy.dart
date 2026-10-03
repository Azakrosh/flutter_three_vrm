import 'dart:async';

import '../models/vrm_exception.dart';

enum VrmViewConfigurationTask { graphics, background }

typedef VrmViewConfigurationDiagnostic =
    void Function(Object error, StackTrace stackTrace);

/// Observes one fire-and-forget declarative configuration task.
///
/// Stale controller results and expected runtime cancellation are intentionally
/// ignored. Active failures keep their original stack trace; graphics failures
/// are additionally made visible through the owning runtime session.
void observeVrmViewConfigurationTask(
  Future<void> task, {
  required VrmViewConfigurationTask kind,
  required bool Function() isCurrent,
  required VrmViewConfigurationDiagnostic reportDiagnostic,
  required void Function(String message) showUserError,
}) {
  unawaited(
    task.catchError((Object error, StackTrace stackTrace) {
      if (!isCurrent() || _isExpectedCancellation(error)) return;

      reportDiagnostic(error, stackTrace);
      if (kind == VrmViewConfigurationTask.graphics) {
        showUserError('Failed to configure VRM graphics: $error');
      }
    }),
  );
}

bool _isExpectedCancellation(Object error) =>
    error is VrmRuntimeException && error.code == 'canceled';
