import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/services.dart';

import '../models/vrm_host_resources.dart';

typedef VrmThermalEventStreamFactory = Stream<Object?> Function();
typedef VrmThermalSubscriptionCanceler =
    Future<void> Function(StreamSubscription<Object?> subscription);

/// Observes Android thermal status without exposing the platform channel.
final class VrmPlatformThermalMonitor {
  VrmPlatformThermalMonitor({
    required this.onStatusChanged,
    bool? isAndroid,
    VrmThermalEventStreamFactory? eventStreamFactory,
    VrmThermalSubscriptionCanceler? cancelSubscription,
  }) : _isAndroid = isAndroid ?? io.Platform.isAndroid,
       _eventStreamFactory = eventStreamFactory ?? _defaultEventStream,
       _cancelSubscription = cancelSubscription ?? _defaultCancelSubscription;

  static const EventChannel _thermalChannel = EventChannel(
    'dev.flutter_three_vrm/thermal_status',
  );
  static Stream<Object?>? _sharedAndroidEventStream;

  final void Function(VrmThermalStatus status) onStatusChanged;
  final bool _isAndroid;
  final VrmThermalEventStreamFactory _eventStreamFactory;
  final VrmThermalSubscriptionCanceler _cancelSubscription;
  // Lifecycle ownership is explicit: [stop] cancels this subscription.
  // ignore: cancel_subscriptions
  StreamSubscription<Object?>? _subscription;
  VrmThermalStatus _status = VrmThermalStatus.unavailable;
  bool _shouldRun = false;
  bool _isReconciling = false;
  int _subscriptionGeneration = 0;
  Completer<void> _idleCompleter = Completer<void>()..complete();

  VrmThermalStatus get status => _status;

  void start() {
    if (!_isAndroid) return;
    _shouldRun = true;
    if (!_isReconciling && _subscription == null) {
      _startSubscription();
      return;
    }
    _scheduleReconciliation();
  }

  Future<void> stop() {
    _shouldRun = false;
    _scheduleReconciliation();
    return _idleCompleter.future;
  }

  bool get _needsReconciliation => _shouldRun != (_subscription != null);

  void _scheduleReconciliation() {
    if (_isReconciling || !_needsReconciliation) return;
    _isReconciling = true;
    if (_idleCompleter.isCompleted) {
      _idleCompleter = Completer<void>();
    }
    unawaited(_reconcile());
  }

  Future<void> _reconcile() async {
    Object? failure;
    StackTrace? failureStackTrace;
    try {
      while (_needsReconciliation) {
        if (_shouldRun) {
          _startSubscription();
        } else {
          await _stopSubscription();
        }
      }
    } on Object catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
    } finally {
      _isReconciling = false;
      if (failure != null) {
        if (!_idleCompleter.isCompleted) {
          _idleCompleter.completeError(failure, failureStackTrace!);
        }
      } else if (!_idleCompleter.isCompleted) {
        _idleCompleter.complete();
      }
      if (failure == null && _needsReconciliation) {
        _scheduleReconciliation();
      }
    }
  }

  void _startSubscription() {
    final generation = ++_subscriptionGeneration;
    _subscription = _eventStreamFactory().listen(
      (value) {
        if (_isCurrent(generation)) {
          _update(vrmThermalStatusFromAndroidCode(value));
        }
      },
      onError: (Object _) {
        if (_isCurrent(generation)) {
          _update(VrmThermalStatus.unavailable);
        }
      },
    );
  }

  Future<void> _stopSubscription() async {
    final subscription = _subscription;
    _subscription = null;
    _subscriptionGeneration += 1;
    if (subscription != null) {
      await _cancelSubscription(subscription);
    }
    if (!_shouldRun) _status = VrmThermalStatus.unavailable;
  }

  bool _isCurrent(int generation) =>
      _shouldRun && generation == _subscriptionGeneration;

  void _update(VrmThermalStatus next) {
    if (next == _status) return;
    _status = next;
    onStatusChanged(next);
  }

  static Future<void> _defaultCancelSubscription(
    StreamSubscription<Object?> subscription,
  ) => subscription.cancel();

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
