import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';
import 'package:flutter_three_vrm/src/performance/vrm_platform_thermal_monitor.dart';

void main() {
  test('maps every Android thermal status and rejects unknown values', () {
    expect(vrmThermalStatusFromAndroidCode(0), VrmThermalStatus.none);
    expect(vrmThermalStatusFromAndroidCode(1), VrmThermalStatus.light);
    expect(vrmThermalStatusFromAndroidCode(2), VrmThermalStatus.moderate);
    expect(vrmThermalStatusFromAndroidCode(3), VrmThermalStatus.severe);
    expect(vrmThermalStatusFromAndroidCode(4), VrmThermalStatus.critical);
    expect(vrmThermalStatusFromAndroidCode(5), VrmThermalStatus.emergency);
    expect(vrmThermalStatusFromAndroidCode(6), VrmThermalStatus.shutdown);
    expect(vrmThermalStatusFromAndroidCode(7), VrmThermalStatus.unavailable);
    expect(vrmThermalStatusFromAndroidCode(null), VrmThermalStatus.unavailable);
  });

  test(
    'monitor deduplicates events and returns to fallback after stop',
    () async {
      final events = StreamController<Object?>.broadcast();
      final changes = <VrmThermalStatus>[];
      final monitor = VrmPlatformThermalMonitor(
        isAndroid: true,
        eventStreamFactory: () => events.stream,
        onStatusChanged: changes.add,
      );

      monitor.start();
      monitor.start();
      events
        ..add(0)
        ..add(0)
        ..add(3);
      await Future<void>.delayed(Duration.zero);

      expect(changes, [VrmThermalStatus.none, VrmThermalStatus.severe]);
      expect(monitor.status, VrmThermalStatus.severe);

      await monitor.stop();
      expect(monitor.status, VrmThermalStatus.unavailable);
      await events.close();
    },
  );

  test('monitor does not open the channel outside Android', () async {
    var opened = false;
    final monitor = VrmPlatformThermalMonitor(
      isAndroid: false,
      eventStreamFactory: () {
        opened = true;
        return const Stream<Object?>.empty();
      },
      onStatusChanged: (_) {},
    );

    monitor.start();

    expect(opened, isFalse);
    expect(monitor.status, VrmThermalStatus.unavailable);
    await monitor.stop();
  });

  test('serializes stop and restart without stale status updates', () async {
    final cancellationStarted = Completer<void>();
    final releaseCancellation = Completer<void>();
    final firstEvents = StreamController<Object?>.broadcast();
    final secondEvents = StreamController<Object?>.broadcast();
    final streams = [firstEvents.stream, secondEvents.stream];
    var opened = 0;
    var cancellations = 0;
    final changes = <VrmThermalStatus>[];
    final monitor = VrmPlatformThermalMonitor(
      isAndroid: true,
      eventStreamFactory: () => streams[opened++],
      cancelSubscription: (subscription) async {
        if (cancellations++ == 0) {
          cancellationStarted.complete();
          await releaseCancellation.future;
        }
        await subscription.cancel();
      },
      onStatusChanged: changes.add,
    );

    monitor.start();
    firstEvents.add(3);
    await Future<void>.delayed(Duration.zero);
    expect(monitor.status, VrmThermalStatus.severe);

    final stopping = monitor.stop();
    await cancellationStarted.future;
    monitor.start();
    firstEvents.add(0);
    await Future<void>.delayed(Duration.zero);
    expect(opened, 1);
    expect(monitor.status, VrmThermalStatus.severe);

    releaseCancellation.complete();
    await stopping;
    expect(opened, 2);

    secondEvents.add(1);
    await Future<void>.delayed(Duration.zero);
    expect(monitor.status, VrmThermalStatus.light);
    expect(changes, [VrmThermalStatus.severe, VrmThermalStatus.light]);

    await monitor.stop();
    await firstEvents.close();
    await secondEvents.close();
  });
}
