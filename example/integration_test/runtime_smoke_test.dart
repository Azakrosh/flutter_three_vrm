import 'package:example/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('initializes, loads a VRM, and survives runtime reload', (
    tester,
  ) async {
    await tester.pumpWidget(const VrmExampleApp());
    await tester.pump();

    final view = tester.widget<VrmView>(find.byType(VrmView));
    final controller = view.controller;
    await controller.waitUntilReady(timeout: const Duration(seconds: 30));

    final initialHealth = await controller.getRuntimeHealth();
    expect(initialHealth.protocolVersion, 1);
    expect(initialHealth.threeRevision, '180');
    expect(initialHealth.threeVrmVersion, '3.5.5');
    expect(initialHealth.maxTextureSize, greaterThan(0));

    await _waitForModel(tester, controller);
    final report = await controller.getModelReport();
    expect(report.meshes, greaterThan(0));
    expect(report.triangles, greaterThan(0));
    expect(report.humanoidBones, greaterThan(0));

    const expectedTransform = VrmTransform(x: 0.2, y: -0.1, zoom: 1.4);
    await controller.setTransform(expectedTransform);

    await controller.reloadRuntime();
    await controller.waitUntilReady(timeout: const Duration(seconds: 30));
    await _waitForModel(tester, controller);

    final restoredHealth = await controller.getRuntimeHealth();
    expect(restoredHealth.modelLoaded, isTrue);
    expect(restoredHealth.contextLost, isFalse);

    final restoredTransform = await controller.getTransform();
    expect(restoredTransform.x, closeTo(expectedTransform.x, 0.001));
    expect(restoredTransform.y, closeTo(expectedTransform.y, 0.001));
    expect(restoredTransform.zoom, closeTo(expectedTransform.zoom, 0.001));
  });
}

Future<void> _waitForModel(
  WidgetTester tester,
  VrmController controller,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (!controller.isModelLoaded && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(controller.isModelLoaded, isTrue);
}
