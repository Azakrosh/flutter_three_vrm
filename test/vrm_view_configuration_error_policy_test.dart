import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/src/models/vrm_exception.dart';
import 'package:flutter_three_vrm/src/runtime/vrm_view_configuration_error_policy.dart';

void main() {
  test('active graphics failure is diagnostic and user visible', () async {
    final failure = StateError('graphics failed');
    final failureStack = StackTrace.current;
    final diagnostics = <Object>[];
    final diagnosticStacks = <StackTrace>[];
    final messages = <String>[];
    final unhandledErrors = <Object>[];

    await runZonedGuarded(() async {
      observeVrmViewConfigurationTask(
        Future<void>.error(failure, failureStack),
        kind: VrmViewConfigurationTask.graphics,
        isCurrent: () => true,
        reportDiagnostic: (error, stackTrace) {
          diagnostics.add(error);
          diagnosticStacks.add(stackTrace);
        },
        showUserError: messages.add,
      );
      await Future<void>.delayed(Duration.zero);
    }, (error, _) => unhandledErrors.add(error));

    expect(diagnostics, <Object>[failure]);
    expect(diagnosticStacks, <StackTrace>[failureStack]);
    expect(messages.single, contains('graphics failed'));
    expect(unhandledErrors, isEmpty);
  });

  test('active background failure is diagnostic without a UI error', () async {
    final failure = StateError('background failed');
    final diagnostics = <Object>[];
    final messages = <String>[];

    observeVrmViewConfigurationTask(
      Future<void>.error(failure),
      kind: VrmViewConfigurationTask.background,
      isCurrent: () => true,
      reportDiagnostic: (error, _) => diagnostics.add(error),
      showUserError: messages.add,
    );
    await Future<void>.delayed(Duration.zero);

    expect(diagnostics, <Object>[failure]);
    expect(messages, isEmpty);
  });

  test('stale and canceled failures are ignored', () async {
    final diagnostics = <Object>[];
    final messages = <String>[];

    observeVrmViewConfigurationTask(
      Future<void>.error(StateError('stale')),
      kind: VrmViewConfigurationTask.graphics,
      isCurrent: () => false,
      reportDiagnostic: (error, _) => diagnostics.add(error),
      showUserError: messages.add,
    );
    observeVrmViewConfigurationTask(
      Future<void>.error(
        const VrmRuntimeException(code: 'canceled', message: 'superseded'),
      ),
      kind: VrmViewConfigurationTask.graphics,
      isCurrent: () => true,
      reportDiagnostic: (error, _) => diagnostics.add(error),
      showUserError: messages.add,
    );
    await Future<void>.delayed(Duration.zero);

    expect(diagnostics, isEmpty);
    expect(messages, isEmpty);
  });

  test('successful task produces no diagnostics', () async {
    final diagnostics = <Object>[];
    final messages = <String>[];

    observeVrmViewConfigurationTask(
      Future<void>.value(),
      kind: VrmViewConfigurationTask.graphics,
      isCurrent: () => true,
      reportDiagnostic: (error, _) => diagnostics.add(error),
      showUserError: messages.add,
    );
    await Future<void>.delayed(Duration.zero);

    expect(diagnostics, isEmpty);
    expect(messages, isEmpty);
  });
}
