import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';
import 'package:flutter_three_vrm/src/performance/vrm_host_resource_monitor.dart';

void main() {
  group('VrmHostResourceMonitor', () {
    test(
      'controller captures host resources without an attached runtime',
      () async {
        final controller = VrmController();

        final snapshot = controller.captureHostResourceSnapshot();

        expect(snapshot.currentRssBytes, greaterThanOrEqualTo(0));
        expect(snapshot.maxRssBytes, greaterThanOrEqualTo(0));
        expect(snapshot.memoryPressureCount, 0);
        expect(snapshot.thermalStatus, VrmThermalStatus.unavailable);

        await controller.dispose();
        expect(controller.captureHostResourceSnapshot, throwsStateError);
      },
    );

    test('captures injected host metrics', () {
      final capturedAt = DateTime.utc(2026, 9, 26, 12, 30);
      final monitor = VrmHostResourceMonitor(
        currentRssReader: () => 120,
        maxRssReader: () => 240,
        clock: () => capturedAt,
        thermalStatusReader: () => VrmThermalStatus.moderate,
      );

      final snapshot = monitor.capture();

      expect(snapshot.capturedAt, capturedAt);
      expect(snapshot.currentRssBytes, 120);
      expect(snapshot.maxRssBytes, 240);
      expect(snapshot.memoryPressureCount, 0);
      expect(snapshot.thermalStatus, VrmThermalStatus.moderate);
    });

    test('counts memory pressure and returns the matching snapshot', () {
      final monitor = VrmHostResourceMonitor(
        currentRssReader: () => 100,
        maxRssReader: () => 150,
      );

      expect(monitor.recordMemoryPressure().memoryPressureCount, 1);
      expect(monitor.recordMemoryPressure().memoryPressureCount, 2);
      expect(monitor.capture().memoryPressureCount, 2);
    });

    test('uses safe fallback values for unavailable signals', () {
      final monitor = VrmHostResourceMonitor(
        currentRssReader: () => -1,
        maxRssReader: () => -2,
      );

      final snapshot = monitor.capture();

      expect(snapshot.currentRssBytes, 0);
      expect(snapshot.maxRssBytes, 0);
      expect(snapshot.thermalStatus, VrmThermalStatus.unavailable);
    });
  });
}
