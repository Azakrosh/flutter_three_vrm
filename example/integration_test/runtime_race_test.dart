import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';
import 'package:integration_test/integration_test.dart';

import 'support/vrm_integration_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('settles replacement, cancel, and reload model races', (
    tester,
  ) async {
    final harness = await VrmIntegrationHarness.start(tester);
    final controller = harness.controller;
    await harness.waitForModel();
    await harness.waitForAnimation();

    await controller.unloadModel();
    final replacedOutcome = _captureOutcome(
      controller.loadModel('assets/vrm/', 'sample.vrm'),
    );
    final replacementOutcome = _captureOutcome(
      controller.loadModel('assets/vrm/', 'sample.vrm'),
    );
    expect(await replacedOutcome, _canceledRuntimeCommand);
    expect(await replacementOutcome, isNull);
    expect(controller.isModelLoaded, isTrue);

    await controller.unloadModel();
    final canceledOutcome = _captureOutcome(
      controller.loadModel('assets/vrm/', 'sample.vrm'),
    );
    await Future<void>.delayed(Duration.zero);
    final cancelOutcome = _captureOutcome(controller.cancelModelLoad());
    expect(await cancelOutcome, isNull);
    expect(await canceledOutcome, _canceledRuntimeCommand);
    expect(controller.isLoadingModel, isFalse);
    expect(controller.isModelLoaded, isFalse);

    final staleRuntimeOutcome = _captureOutcome(
      controller.loadModel('assets/vrm/', 'sample.vrm'),
    );
    await Future<void>.delayed(Duration.zero);
    final reloadOutcome = _captureOutcome(controller.reloadRuntime());
    expect(await reloadOutcome, isNull);
    expect(
      await staleRuntimeOutcome,
      anyOf(
        _canceledRuntimeCommand,
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('reloading'),
        ),
      ),
    );

    await controller.waitUntilReady(timeout: const Duration(seconds: 30));
    await harness.waitForModel();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final recovered = await controller.getRuntimeHealth();
    expect(recovered.modelLoaded, isTrue);
    expect(recovered.contextLost, isFalse);

    await harness.disposeView();
  }, timeout: const Timeout(Duration(minutes: 3)));
}

final Matcher _canceledRuntimeCommand = isA<VrmRuntimeException>().having(
  (error) => error.code,
  'code',
  'canceled',
);

Future<Object?> _captureOutcome(Future<void> operation) {
  return operation.then<Object?>((_) => null, onError: (Object error) => error);
}
