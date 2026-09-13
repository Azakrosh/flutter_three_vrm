import 'dart:async';
import 'dart:math';

import '../vrm_runtime.dart';
import '../models/vrm_events.dart';
import 'vrm_animation_queue_state.dart';

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
/// queue.dispose();
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

  final StreamController<VrmAnimationQueueState> _stateController =
      StreamController<VrmAnimationQueueState>.broadcast();

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
    return _fileNames[_playOrder[_currentIndex]];
  }

  /// `true` when the queue is in any active state (playing, paused, interrupted).
  bool get isActive => _state != VrmAnimationQueueState.stopped;

  /// Emits whenever the queue state changes.
  Stream<VrmAnimationQueueState> get onStateChanged => _stateController.stream;

  /// Starts playing the queue from the beginning.
  ///
  /// If the queue is [VrmAnimationQueueState.paused], acts as [resume].
  /// If already [VrmAnimationQueueState.playing], restarts from the beginning.
  void start() {
    if (_fileNames.isEmpty) return;

    if (_state == VrmAnimationQueueState.paused) {
      resume();
      return;
    }

    _ensureSubscription();
    _currentIndex = 0;
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
    if (_state == VrmAnimationQueueState.playing) {
      _setState(VrmAnimationQueueState.paused);
    } else if (_state == VrmAnimationQueueState.interrupted) {
      _pauseAfterInterrupt = true;
    }
  }

  /// Resumes a paused queue — plays the next track in the order.
  void resume() {
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
    _cancelSubscription();
    _currentIndex = 0;
    _pauseAfterInterrupt = false;
    if (_state != VrmAnimationQueueState.stopped) {
      _setState(VrmAnimationQueueState.stopped);
    }
    unawaited(_controller.stopAnimation());
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
    if (_state == VrmAnimationQueueState.stopped) return;

    _ensureSubscription();
    _setState(VrmAnimationQueueState.interrupted);
    unawaited(
      _controller.playAnimation(
        folderPath,
        fileName,
        loop: false,
        speed: speed ?? _speed,
      ),
    );
  }

  /// Releases resources. Must be called when the queue is no longer needed.
  void dispose() {
    _cancelSubscription();
    unawaited(_stateController.close());
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _playCurrentTrack() {
    final fileName = _fileNames[_playOrder[_currentIndex]];
    unawaited(
      _controller.playAnimation(
        _folderPath,
        fileName,
        loop: false,
        speed: _speed,
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
        _cancelSubscription();
        _setState(VrmAnimationQueueState.stopped);
        unawaited(_controller.stopAnimation());
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
    switch (_state) {
      case VrmAnimationQueueState.playing:
        _advanceToNext();
        break;
      case VrmAnimationQueueState.interrupted:
        // Priority animation finished
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
  }

  void _cancelSubscription() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void _setState(VrmAnimationQueueState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateController.add(newState);
  }
}
