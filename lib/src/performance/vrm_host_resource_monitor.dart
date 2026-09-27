import 'dart:io' as io;

import '../models/vrm_host_resources.dart';

typedef VrmResourceBytesReader = int Function();
typedef VrmResourceClock = DateTime Function();
typedef VrmThermalStatusReader = VrmThermalStatus Function();

/// Collects host-process diagnostics independently from the WebView protocol.
final class VrmHostResourceMonitor {
  VrmHostResourceMonitor({
    VrmResourceBytesReader? currentRssReader,
    VrmResourceBytesReader? maxRssReader,
    VrmResourceClock? clock,
    VrmThermalStatusReader? thermalStatusReader,
  }) : _currentRssReader = currentRssReader ?? _readCurrentRss,
       _maxRssReader = maxRssReader ?? _readMaxRss,
       _clock = clock ?? DateTime.now,
       _thermalStatusReader =
           thermalStatusReader ?? _readUnavailableThermalStatus;

  final VrmResourceBytesReader _currentRssReader;
  final VrmResourceBytesReader _maxRssReader;
  final VrmResourceClock _clock;
  final VrmThermalStatusReader _thermalStatusReader;
  int _memoryPressureCount = 0;
  int _observedMaxRssBytes = 0;

  VrmHostResourceSnapshot capture() {
    final currentRssBytes = _nonNegative(_currentRssReader());
    final platformMaxRssBytes = _nonNegative(_maxRssReader());
    _observedMaxRssBytes = _max(
      _observedMaxRssBytes,
      _max(currentRssBytes, platformMaxRssBytes),
    );
    return VrmHostResourceSnapshot(
      capturedAt: _clock(),
      currentRssBytes: currentRssBytes,
      maxRssBytes: _observedMaxRssBytes,
      memoryPressureCount: _memoryPressureCount,
      thermalStatus: _thermalStatusReader(),
    );
  }

  VrmHostResourceSnapshot recordMemoryPressure() {
    _memoryPressureCount += 1;
    return capture();
  }

  static int _readCurrentRss() => io.ProcessInfo.currentRss;

  static int _readMaxRss() => io.ProcessInfo.maxRss;

  static VrmThermalStatus _readUnavailableThermalStatus() =>
      VrmThermalStatus.unavailable;

  static int _nonNegative(int value) => value < 0 ? 0 : value;

  static int _max(int first, int second) => first > second ? first : second;
}
