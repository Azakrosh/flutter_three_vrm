import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/services.dart';

import '../models/vrm_host_resources.dart';

typedef VrmThermalEventStreamFactory = Stream<Object?> Function();

/// Observes Android thermal status without exposing the platform channel.
final class VrmPlatformThermalMonitor {
  VrmPlatformThermalMonitor({
    required this.onStatusChanged,
    bool? isAndroid,
    VrmThermalEventStreamFactory? eventStreamFactory,
  }) : _isAndroid = isAndroid ?? io.Platform.isAndroid,
       _eventStreamFactory = eventStreamFactory ?? _defaultEventStream;

  static const EventChannel _thermalChannel = EventChannel(
    'dev.flutter_three_vrm/thermal_status',
  );
  static Stream<Object?>? _sharedAndroidEventStream;

  final void Function(VrmThermalStatus status) onStatusChanged;
  final bool _isAndroid;
  final VrmThermalEventStreamFactory _eventStreamFactory;
  // Lifecycle ownership is explicit: [stop] cancels this subscription.
  // ignore: cancel_subscriptions
  StreamSubscription<Object?>? _subscription;
  VrmThermalStatus _status = VrmThermalStatus.unavailable;

  VrmThermalStatus get status => _status;

  void start() {
    if (!_isAndroid || _subscription != null) return;
    _subscription = _eventStreamFactory().listen(
      (value) => _update(vrmThermalStatusFromAndroidCode(value)),
      onError: (Object _) => _update(VrmThermalStatus.unavailable),
    );
  }

  Future<void> stop() async {
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      await subscription.cancel();
    }
    _status = VrmThermalStatus.unavailable;
  }

  void _update(VrmThermalStatus next) {
    if (next == _status) return;
    _status = next;
    onStatusChanged(next);
  }

  static Stream<Object?> _defaultEventStream() => _sharedAndroidEventStream ??=
      _thermalChannel.receiveBroadcastStream().cast<Object?>();
}

VrmThermalStatus vrmThermalStatusFromAndroidCode(Object? value) =>
    switch (value) {
      0 => VrmThermalStatus.none,
      1 => VrmThermalStatus.light,
      2 => VrmThermalStatus.moderate,
      3 => VrmThermalStatus.severe,
      4 => VrmThermalStatus.critical,
      5 => VrmThermalStatus.emergency,
      6 => VrmThermalStatus.shutdown,
      _ => VrmThermalStatus.unavailable,
    };
