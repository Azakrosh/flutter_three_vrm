import 'vrm_animation_queue_state.dart';

/// Serializable playback position for [VrmAnimationQueue].
final class VrmAnimationQueueSnapshot {
  VrmAnimationQueueSnapshot({
    required this.state,
    required List<int> playOrder,
    required this.currentIndex,
    required this.pauseAfterInterrupt,
    this.interruptFolderPath,
    this.interruptFileName,
    this.interruptSpeed,
  }) : playOrder = List<int>.unmodifiable(playOrder) {
    _validate();
  }

  static const int currentVersion = 1;

  final VrmAnimationQueueState state;
  final List<int> playOrder;
  final int currentIndex;
  final bool pauseAfterInterrupt;
  final String? interruptFolderPath;
  final String? interruptFileName;
  final double? interruptSpeed;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': currentVersion,
    'state': state.name,
    'playOrder': playOrder,
    'currentIndex': currentIndex,
    'pauseAfterInterrupt': pauseAfterInterrupt,
    'interruptFolderPath': interruptFolderPath,
    'interruptFileName': interruptFileName,
    'interruptSpeed': interruptSpeed,
  };

  factory VrmAnimationQueueSnapshot.fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException(
        'Animation queue snapshot must be an object.',
      );
    }
    if (value['version'] != currentVersion) {
      throw FormatException(
        'Unsupported animation queue snapshot version: ${value['version']}.',
      );
    }
    final stateName = value['state'];
    final state = VrmAnimationQueueState.values
        .where((candidate) => candidate.name == stateName)
        .firstOrNull;
    if (state == null) {
      throw FormatException('Unknown animation queue state: $stateName.');
    }
    final rawOrder = value['playOrder'];
    if (rawOrder is! List<Object?>) {
      throw const FormatException('playOrder must be an array.');
    }
    final playOrder = rawOrder
        .map((entry) {
          if (entry case final int index when index >= 0) return index;
          throw const FormatException(
            'playOrder must contain non-negative integers.',
          );
        })
        .toList(growable: false);
    final currentIndex = value['currentIndex'];
    if (currentIndex is! int) {
      throw const FormatException('currentIndex must be an integer.');
    }
    final pauseAfterInterrupt = value['pauseAfterInterrupt'];
    if (pauseAfterInterrupt is! bool) {
      throw const FormatException('pauseAfterInterrupt must be a boolean.');
    }
    final rawSpeed = value['interruptSpeed'];
    if (rawSpeed != null && (rawSpeed is! num || !rawSpeed.isFinite)) {
      throw const FormatException('interruptSpeed must be a finite number.');
    }
    String? optionalString(String name) {
      final field = value[name];
      if (field == null) return null;
      if (field is String && field.isNotEmpty) return field;
      throw FormatException('$name must be a non-empty string or null.');
    }

    return VrmAnimationQueueSnapshot(
      state: state,
      playOrder: playOrder,
      currentIndex: currentIndex,
      pauseAfterInterrupt: pauseAfterInterrupt,
      interruptFolderPath: optionalString('interruptFolderPath'),
      interruptFileName: optionalString('interruptFileName'),
      interruptSpeed: (rawSpeed as num?)?.toDouble(),
    );
  }

  void _validate() {
    if (playOrder.isEmpty) {
      if (currentIndex != 0) {
        throw const FormatException(
          'currentIndex must be zero for an empty queue.',
        );
      }
      if (state != VrmAnimationQueueState.stopped) {
        throw const FormatException('An empty queue must be stopped.');
      }
    } else if (currentIndex < 0 || currentIndex >= playOrder.length) {
      throw const FormatException('currentIndex is outside playOrder.');
    }
    final expected = List<int>.generate(playOrder.length, (index) => index);
    final sorted = playOrder.toList(growable: false)..sort();
    for (var index = 0; index < expected.length; index += 1) {
      if (sorted[index] != expected[index]) {
        throw const FormatException(
          'playOrder must be a permutation of queue indexes.',
        );
      }
    }
    final hasInterruptFolder = interruptFolderPath != null;
    final hasInterruptFile = interruptFileName != null;
    if (interruptFolderPath?.isEmpty == true ||
        interruptFileName?.isEmpty == true) {
      throw const FormatException(
        'Interrupt folder and file must not be empty.',
      );
    }
    if (hasInterruptFolder != hasInterruptFile) {
      throw const FormatException(
        'Interrupt folder and file must either both be set or both be null.',
      );
    }
    if (state == VrmAnimationQueueState.interrupted && !hasInterruptFile) {
      throw const FormatException(
        'Interrupted queue snapshot requires an interrupt source.',
      );
    }
  }
}
