import 'dart:async';
import 'dart:math';

import '../vrm_runtime.dart';
import '../models/vrm_animation_options.dart';
import '../models/vrm_events.dart';
import 'vrm_animation_queue_snapshot.dart';
import 'vrm_animation_queue_state.dart';

/// Asynchronous playback failure reported by [VrmAnimationQueue].
final class VrmAnimationQueueError {
  const VrmAnimationQueueError({
    required this.operation,
    required this.fileName,
    required this.error,
    required this.stackTrace,
  });

  final String operation;
  final String? fileName;
  final Object error;
  final StackTrace stackTrace;
}

/// Manages a queue of VRMA animations with sequential or random playback,
/// optional looping, and support for priority interrupts.
///
/// All crossfade transitions are handled by the JS engine automatically —
/// this class only decides *when* to call [VrmController.playAnimation].
///
/// ```dart
/// final queue = VrmAnimationQueue(
///   controller: vrmController,
///   folderPath: 'assets/vrma/',
///   fileNames: ['idle_01.vrma', 'idle_02.vrma', 'idle_03.vrma'],
///   random: true,
///   loop: true,
/// );
///
/// queue.start();
/// // Later: queue.interrupt(folderPath: 'assets/vrma/', fileName: 'happy.vrma');
/// // Later: queue.stop();
/// await queue.dispose();
/// ```
class VrmAnimationQueue {
  final VrmController _controller;
  final String _folderPath;
  final List<String> _fileNames;
  final bool _isRandom;
  final bool _isLooping;
  final double _speed;
  final double _fadeDuration;

  final Random _rng = Random();

  /// Pre-allocated play order array — reused on every shuffle to avoid GC.
  late final List<int> _playOrder;
  int _currentIndex = 0;

  VrmAnimationQueueState _state = VrmAnimationQueueState.stopped;
  bool _pauseAfterInterrupt = false;
  StreamSubscription<VrmAnimationFinishedEvent>? _subscription;
  StreamSubscription<VrmModelLoadedEvent>? _modelLoadedSubscription;
  StreamSubscription<VrmRuntimeUnavailableEvent>?
  _runtimeUnavailableSubscription;
  String? _interruptFolderPath;
  String? _interruptFileName;
  double? _interruptSpeed;
  int _operationGeneration = 0;
  String? _activePlaybackId;
  bool _playbackStartPending = false;
  final Set<String> _finishedWhileStarting = <String>{};
  bool _disposed = false;
  Future<void>? _disposeFuture;

  final StreamController<VrmAnimationQueueState> _stateController =
      StreamController<VrmAnimationQueueState>.broadcast();
  final StreamController<VrmAnimationQueueError> _errorController =
      StreamController<VrmAnimationQueueError>.broadcast();

  /// Creates an animation queue.
  ///
  /// [_controller] — the VRM controller to play animations on.
  /// [_folderPath] — asset folder path (e.g. `'assets/vrma/'`).
  /// [fileNames] — list of `.vrma` file names to queue.
  /// [random] — if `true`, shuffles play order each cycle (Fisher-Yates).
  /// [loop] — if `true`, restarts from the beginning after the last track.
  /// [_speed] — playback speed multiplier for all queued animations.
  /// [_fadeDuration] — crossfade duration in seconds between animations.
  VrmAnimationQueue({
    required this._controller,
    required this._folderPath,
    required List<String> fileNames,
    bool random = false,
    bool loop = true,
    this._speed = 1.0,
    this._fadeDuration = 0.5,
  }) : _fileNames = List<String>.unmodifiable(fileNames),
       _isRandom = random,
       _isLooping = loop {
    if (_folderPath.trim().isEmpty) {
      throw ArgumentError.value(
        _folderPath,
        'folderPath',
        'Must not be empty.',
      );
    }
    for (final fileName in _fileNames) {
      if (fileName.trim().isEmpty) {
        throw ArgumentError.value(
          fileNames,
          'fileNames',
          'File names must not be empty.',
        );
      }
    }
    if (!_speed.isFinite || _speed <= 0) {
      throw ArgumentError.value(
        _speed,
        'speed',
        'Must be positive and finite.',
      );
    }
    if (!_fadeDuration.isFinite || _fadeDuration < 0) {
      throw ArgumentError.value(
        _fadeDuration,
        'fadeDuration',
        'Must be non-negative and finite.',
      );
    }
    // Pre-allocate the index array once
    _playOrder = List<int>.generate(fileNames.length, (i) => i);
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Current queue state.
  VrmAnimationQueueState get state => _state;

  /// File name of the currently playing track, or `null` if stopped.
  String? get currentFile {
    if (_state == VrmAnimationQueueState.stopped ||
        _currentIndex < 0 ||
        _currentIndex >= _playOrder.length) {
      return null;
    }
    if (_state == VrmAnimationQueueState.interrupted) {
      return _interruptFileName;
    }
    return _fileNames[_playOrder[_currentIndex]];
  }

  /// `true` when the queue is in any active state (playing, paused, interrupted).
  bool get isActive => _state != VrmAnimationQueueState.stopped;

  /// Emits whenever the queue state changes.
  Stream<VrmAnimationQueueState> get onStateChanged => _stateController.stream;

  /// Reports loading or playback failures that occurred in fire-and-forget
  /// queue operations.
  Stream<VrmAnimationQueueError> get onError => _errorController.stream;

  /// Captures the exact order and playback position for persistence.
  VrmAnimationQueueSnapshot snapshot() => VrmAnimationQueueSnapshot(
    state: _state,
    playOrder: _playOrder,
    currentIndex: _currentIndex,
    pauseAfterInterrupt: _pauseAfterInterrupt,
    interruptFolderPath: _interruptFolderPath,
    interruptFileName: _interruptFileName,
    interruptSpeed: _interruptSpeed,
  );

  /// Restores a snapshot created for a queue with the same [fileNames].
  ///
  /// When a model is already loaded, active playback is restarted immediately.
  /// Otherwise it is restarted after the controller reports the next model.
  void restore(
    VrmAnimationQueueSnapshot snapshot, {
    bool resumePlayback = true,
  }) {
    _ensureNotDisposed();
    if (snapshot.playOrder.length != _playOrder.length) {
      throw ArgumentError.value(
        snapshot.playOrder.length,
        'snapshot',
        'Snapshot queue length does not match this queue.',
      );
    }
    _operationGeneration += 1;
    _resetPlaybackTracking();
    for (var index = 0; index < _playOrder.length; index += 1) {
      _playOrder[index] = snapshot.playOrder[index];
    }
    _currentIndex = snapshot.currentIndex;
    _pauseAfterInterrupt = snapshot.pauseAfterInterrupt;
    _interruptFolderPath = snapshot.interruptFolderPath;
    _interruptFileName = snapshot.interruptFileName;
    _interruptSpeed = snapshot.interruptSpeed;

    if (snapshot.state != VrmAnimationQueueState.stopped) {
      _ensureSubscription();
    }
    _setState(snapshot.state);
    if (resumePlayback && _controller.isModelLoaded) {
      _restoreCurrentPlayback();
    }
  }

  /// Starts playing the queue from the beginning.
  ///
  /// If the queue is [VrmAnimationQueueState.paused], acts as [resume].
  /// If already [VrmAnimationQueueState.playing], restarts from the beginning.
  void start() {
    _ensureNotDisposed();
    if (_fileNames.isEmpty) return;

    if (_state == VrmAnimationQueueState.paused) {
      resume();
      return;
    }

    _ensureSubscription();
    _currentIndex = 0;
    _clearInterrupt();
    _generatePlayOrder();
    _setState(VrmAnimationQueueState.playing);
    _playCurrentTrack();
  }

  /// Pauses the queue — the current animation plays to completion,
  /// but the next one won't start until [resume] is called.
  ///
  /// If called during an [interrupt], the queue will pause after
  /// the priority animation finishes instead of resuming.
  void pause() {
    _ensureNotDisposed();
    if (_state == VrmAnimationQueueState.playing) {
      _setState(VrmAnimationQueueState.paused);
    } else if (_state == VrmAnimationQueueState.interrupted) {
      _pauseAfterInterrupt = true;
    }
  }

  /// Resumes a paused queue — plays the next track in the order.
  void resume() {
    _ensureNotDisposed();
    if (_state == VrmAnimationQueueState.paused) {
      _setState(VrmAnimationQueueState.playing);
      _advanceToNext();
    }
  }

  /// Stops the queue completely and resets position.
  ///
  /// Calls [VrmController.stopAnimation] to immediately halt playback
  /// and reset the model to its default pose.
  void stop() {
    _ensureNotDisposed();
    _operationGeneration += 1;
    _resetPlaybackTracking();
    _currentIndex = 0;
    _pauseAfterInterrupt = false;
    _clearInterrupt();
    if (_state != VrmAnimationQueueState.stopped) {
      _setState(VrmAnimationQueueState.stopped);
    }
    _runOperation('stop', null, _controller.stopAnimation);
  }

  /// Interrupts the queue with a priority animation.
  ///
  /// The current animation crossfades into [fileName], and after it finishes,
  /// the queue automatically resumes from where it was interrupted.
  ///
  /// If called while another interrupt is already playing, replaces it
  /// with a crossfade (stays in `interrupted` state).
  void interrupt({
    required String folderPath,
    required String fileName,
    double? speed,
  }) {
    _ensureNotDisposed();
    if (folderPath.trim().isEmpty) {
      throw ArgumentError.value(folderPath, 'folderPath', 'Must not be empty.');
    }
    if (fileName.trim().isEmpty) {
      throw ArgumentError.value(fileName, 'fileName', 'Must not be empty.');
    }
    final resolvedSpeed = speed ?? _speed;
    if (!resolvedSpeed.isFinite || resolvedSpeed <= 0) {
      throw ArgumentError.value(
        resolvedSpeed,
        'speed',
        'Must be positive and finite.',
      );
    }
    if (_state == VrmAnimationQueueState.stopped) return;

    _ensureSubscription();
    _interruptFolderPath = folderPath;
    _interruptFileName = fileName;
    _interruptSpeed = resolvedSpeed;
    _setState(VrmAnimationQueueState.interrupted);
    _playInterrupt();
  }

  /// Releases subscriptions and event streams.
  ///
  /// Repeated calls return the same cleanup future.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _operationGeneration += 1;
    _resetPlaybackTracking();
    final cancellations = <Future<void>>[];
    if (_subscription != null) {
      cancellations.add(_subscription!.cancel());
      _subscription = null;
    }
    if (_modelLoadedSubscription != null) {
      cancellations.add(_modelLoadedSubscription!.cancel());
      _modelLoadedSubscription = null;
    }
    if (_runtimeUnavailableSubscription != null) {
      cancellations.add(_runtimeUnavailableSubscription!.cancel());
      _runtimeUnavailableSubscription = null;
    }
    try {
      await Future.wait<void>(cancellations);
    } finally {
      await Future.wait<void>([
        _stateController.close(),
        _errorController.close(),
      ]);
    }
  }
  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _playCurrentTrack() {
    final fileName = _fileNames[_playOrder[_currentIndex]];
    _runPlaybackOperation(
      'play',
      fileName,
      () => _controller.playAnimation(
        _folderPath,
        fileName,
        loop: false,
        speed: _speed,
        fadeDuration: _fadeDuration,
      ),
    );
  }

  void _playInterrupt() {
    final folderPath = _interruptFolderPath;
    final fileName = _interruptFileName;
    if (folderPath == null || fileName == null) return;
    _runPlaybackOperation(
      'interrupt',
      fileName,
      () => _controller.playAnimation(
        folderPath,
        fileName,
        loop: false,
        speed: _interruptSpeed ?? _speed,
        fadeDuration: _fadeDuration,
      ),
    );
  }

  void _advanceToNext() {
    _currentIndex++;

    if (_currentIndex >= _playOrder.length) {
      if (_isLooping) {
        _generatePlayOrder();
        _currentIndex = 0;
      } else {
        _setState(VrmAnimationQueueState.stopped);
        _runOperation('stop', null, _controller.stopAnimation);
        return;
      }
    }

    _playCurrentTrack();
  }

  /// Generates play order — sequential or shuffled.
  /// Reuses the pre-allocated [_playOrder] list (zero allocations).
  void _generatePlayOrder() {
    // Reset to sequential
    for (int i = 0; i < _playOrder.length; i++) {
      _playOrder[i] = i;
    }

    if (_isRandom && _playOrder.length > 1) {
      // Remember last played track to avoid immediate repeat
      final int lastPlayed =
          _currentIndex > 0 && _currentIndex <= _playOrder.length
          ? _playOrder[_currentIndex - 1]
          : -1;

      // Fisher-Yates in-place shuffle
      for (int i = _playOrder.length - 1; i > 0; i--) {
        final j = _rng.nextInt(i + 1);
        final tmp = _playOrder[i];
        _playOrder[i] = _playOrder[j];
        _playOrder[j] = tmp;
      }

      // Anti-repeat: if first track equals last played, swap with another
      if (_playOrder.length > 1 && _playOrder[0] == lastPlayed) {
        final swapIdx = 1 + _rng.nextInt(_playOrder.length - 1);
        final tmp = _playOrder[0];
        _playOrder[0] = _playOrder[swapIdx];
        _playOrder[swapIdx] = tmp;
      }
    }
  }

  void _onAnimationFinished(VrmAnimationFinishedEvent event) {
    if (event.playbackId != _activePlaybackId) {
      if (_playbackStartPending) {
        _finishedWhileStarting.add(event.playbackId);
        if (_finishedWhileStarting.length > 16) {
          _finishedWhileStarting.remove(_finishedWhileStarting.first);
        }
      }
      return;
    }
    _activePlaybackId = null;
    _handleActivePlaybackFinished();
  }

  void _handleActivePlaybackFinished() {
    switch (_state) {
      case VrmAnimationQueueState.playing:
        _advanceToNext();
        break;
      case VrmAnimationQueueState.interrupted:
        // Priority animation finished
        _clearInterrupt();
        if (_pauseAfterInterrupt) {
          _pauseAfterInterrupt = false;
          _setState(VrmAnimationQueueState.paused);
        } else {
          _setState(VrmAnimationQueueState.playing);
          _playCurrentTrack();
        }
        break;
      case VrmAnimationQueueState.paused:
      case VrmAnimationQueueState.stopped:
        // Ignore
        break;
    }
  }

  void _ensureSubscription() {
    _subscription ??= _controller.onAnimationFinished.listen(
      _onAnimationFinished,
    );
    _modelLoadedSubscription ??= _controller.onModelLoaded.listen((_) {
      if (_state == VrmAnimationQueueState.playing ||
          _state == VrmAnimationQueueState.interrupted) {
        _restoreCurrentPlayback();
      }
    });
    _runtimeUnavailableSubscription ??= _controller.onRuntimeUnavailable.listen(
      (_) {
        _operationGeneration += 1;
        _resetPlaybackTracking();
      },
    );
  }

  void _setState(VrmAnimationQueueState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateController.add(newState);
  }

  void _restoreCurrentPlayback() {
    switch (_state) {
      case VrmAnimationQueueState.playing:
        _playCurrentTrack();
      case VrmAnimationQueueState.interrupted:
        _playInterrupt();
      case VrmAnimationQueueState.paused:
      case VrmAnimationQueueState.stopped:
        break;
    }
  }

  void _clearInterrupt() {
    _interruptFolderPath = null;
    _interruptFileName = null;
    _interruptSpeed = null;
  }

  void _resetPlaybackTracking() {
    _activePlaybackId = null;
    _playbackStartPending = false;
    _finishedWhileStarting.clear();
  }

  void _runPlaybackOperation(
    String operation,
    String fileName,
    Future<VrmAnimationPlayback> Function() callback,
  ) {
    final generation = ++_operationGeneration;
    _resetPlaybackTracking();
    _playbackStartPending = true;
    unawaited(() async {
      try {
        final playback = await callback();
        if (_disposed || generation != _operationGeneration) return;
        _activePlaybackId = playback.id;
        _playbackStartPending = false;
        final alreadyFinished = _finishedWhileStarting.remove(playback.id);
        _finishedWhileStarting.clear();
        if (alreadyFinished) {
          _activePlaybackId = null;
          _handleActivePlaybackFinished();
        }
      } on Object catch (error, stackTrace) {
        if (!_disposed && generation == _operationGeneration) {
          _resetPlaybackTracking();
          _errorController.add(
            VrmAnimationQueueError(
              operation: operation,
              fileName: fileName,
              error: error,
              stackTrace: stackTrace,
            ),
          );
        }
      }
    }());
  }

  void _runOperation(
    String operation,
    String? fileName,
    Future<void> Function() callback,
  ) {
    final generation = ++_operationGeneration;
    unawaited(() async {
      try {
        await callback();
      } on Object catch (error, stackTrace) {
        if (!_disposed && generation == _operationGeneration) {
          _errorController.add(
            VrmAnimationQueueError(
              operation: operation,
              fileName: fileName,
              error: error,
              stackTrace: stackTrace,
            ),
          );
        }
      }
    }());
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('VrmAnimationQueue has already been disposed.');
    }
  }
}
