import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';

void main() {
  group('VrmAnimationQueueSnapshot', () {
    test('round-trips queue and interrupt state', () {
      final snapshot = VrmAnimationQueueSnapshot(
        state: VrmAnimationQueueState.interrupted,
        playOrder: const <int>[2, 0, 1],
        currentIndex: 1,
        pauseAfterInterrupt: true,
        interruptFolderPath: 'assets/vrma/',
        interruptFileName: 'reaction.vrma',
        interruptSpeed: 1.25,
      );

      final restored = VrmAnimationQueueSnapshot.fromJson(snapshot.toJson());

      expect(restored.state, VrmAnimationQueueState.interrupted);
      expect(restored.playOrder, <int>[2, 0, 1]);
      expect(restored.currentIndex, 1);
      expect(restored.pauseAfterInterrupt, isTrue);
      expect(restored.interruptFileName, 'reaction.vrma');
      expect(restored.interruptSpeed, 1.25);
    });

    test('rejects malformed play order and incomplete interrupt source', () {
      expect(
        () => VrmAnimationQueueSnapshot(
          state: VrmAnimationQueueState.playing,
          playOrder: const <int>[0, 0],
          currentIndex: 0,
          pauseAfterInterrupt: false,
        ),
        throwsFormatException,
      );
      expect(
        () => VrmAnimationQueueSnapshot.fromJson(<String, Object?>{
          'version': VrmAnimationQueueSnapshot.currentVersion,
          'state': 'playing',
          'playOrder': <int>[0],
          'currentIndex': 0,
          'pauseAfterInterrupt': false,
          'interruptFolderPath': 42,
        }),
        throwsFormatException,
      );
      expect(
        () => VrmAnimationQueueSnapshot(
          state: VrmAnimationQueueState.interrupted,
          playOrder: const <int>[0],
          currentIndex: 0,
          pauseAfterInterrupt: false,
        ),
        throwsFormatException,
      );
    });

    test('restores position into a compatible queue without playback', () {
      final controller = VrmController();
      final queue = VrmAnimationQueue(
        controller: controller,
        folderPath: 'assets/vrma/',
        fileNames: const <String>['a.vrma', 'b.vrma', 'c.vrma'],
      );
      addTearDown(() async {
        queue.dispose();
        await controller.dispose();
      });

      queue.restore(
        VrmAnimationQueueSnapshot(
          state: VrmAnimationQueueState.paused,
          playOrder: const <int>[2, 0, 1],
          currentIndex: 1,
          pauseAfterInterrupt: false,
        ),
        resumePlayback: false,
      );

      expect(queue.state, VrmAnimationQueueState.paused);
      expect(queue.currentFile, 'a.vrma');
      expect(queue.snapshot().playOrder, <int>[2, 0, 1]);
    });

    test('rejects a snapshot created for a different queue length', () {
      final controller = VrmController();
      final queue = VrmAnimationQueue(
        controller: controller,
        folderPath: 'assets/vrma/',
        fileNames: const <String>['a.vrma'],
      );
      addTearDown(() async {
        queue.dispose();
        await controller.dispose();
      });

      expect(
        () => queue.restore(
          VrmAnimationQueueSnapshot(
            state: VrmAnimationQueueState.paused,
            playOrder: const <int>[0, 1],
            currentIndex: 0,
            pauseAfterInterrupt: false,
          ),
          resumePlayback: false,
        ),
        throwsArgumentError,
      );
    });

    test(
      'replays the current item after a recreated model is loaded',
      () async {
        final controller = _FakeVrmController();
        final queue = VrmAnimationQueue(
          controller: controller,
          folderPath: 'assets/vrma/',
          fileNames: const <String>['idle.vrma'],
        );
        addTearDown(() async {
          queue.dispose();
          await controller.dispose();
        });

        queue.restore(
          VrmAnimationQueueSnapshot(
            state: VrmAnimationQueueState.playing,
            playOrder: const <int>[0],
            currentIndex: 0,
            pauseAfterInterrupt: false,
          ),
        );
        expect(controller.playedFiles, isEmpty);

        controller.emitModelLoaded();
        await pumpEventQueue();

        expect(controller.playedFiles, <String>['idle.vrma']);
      },
    );

    test(
      'runtime loss cancels a stale transition and resumes without queue error',
      () async {
        final controller = _FakeVrmController()..delayNextPlayback = true;
        final queue = VrmAnimationQueue(
          controller: controller,
          folderPath: 'assets/vrma/',
          fileNames: const <String>['idle.vrma'],
        );
        final errors = <VrmAnimationQueueError>[];
        final errorSubscription = queue.onError.listen(errors.add);
        addTearDown(() async {
          await errorSubscription.cancel();
          queue.dispose();
          await controller.dispose();
        });

        queue.start();
        await pumpEventQueue();
        controller.emitRuntimeUnavailable();
        controller.completeDelayedPlayback(error: StateError('runtime lost'));
        await pumpEventQueue();

        expect(queue.state, VrmAnimationQueueState.playing);
        expect(errors, isEmpty);

        controller.emitModelLoaded();
        await pumpEventQueue();
        expect(controller.playedFiles, <String>['idle.vrma', 'idle.vrma']);
      },
    );

    test('ignores completion events from unrelated playback', () async {
      final controller = _FakeVrmController();
      final queue = VrmAnimationQueue(
        controller: controller,
        folderPath: 'assets/vrma/',
        fileNames: const <String>['idle.vrma', 'talk.vrma'],
      );
      addTearDown(() async {
        queue.dispose();
        await controller.dispose();
      });

      queue.start();
      await pumpEventQueue();
      final queuePlaybackId = controller.playbackIds.single;

      controller.emitAnimationFinished('external-playback');
      await pumpEventQueue();
      expect(controller.playedFiles, <String>['idle.vrma']);

      controller.emitAnimationFinished(queuePlaybackId);
      await pumpEventQueue();
      expect(controller.playedFiles, <String>['idle.vrma', 'talk.vrma']);
    });

    test('handles a completion delivered before play returns', () async {
      final controller = _FakeVrmController()..delayNextPlayback = true;
      final queue = VrmAnimationQueue(
        controller: controller,
        folderPath: 'assets/vrma/',
        fileNames: const <String>['first.vrma', 'second.vrma'],
      );
      addTearDown(() async {
        queue.dispose();
        await controller.dispose();
      });

      queue.start();
      await pumpEventQueue();
      final firstPlaybackId = controller.playbackIds.single;
      controller.emitAnimationFinished(firstPlaybackId);
      await pumpEventQueue();
      expect(controller.playedFiles, <String>['first.vrma']);

      controller.completeDelayedPlayback();
      await pumpEventQueue();
      expect(controller.playedFiles, <String>['first.vrma', 'second.vrma']);
    });

    test('reports the interrupt as the current file', () async {
      final controller = _FakeVrmController();
      final queue = VrmAnimationQueue(
        controller: controller,
        folderPath: 'assets/vrma/',
        fileNames: const <String>['idle.vrma'],
      );
      addTearDown(() async {
        queue.dispose();
        await controller.dispose();
      });

      queue.start();
      await pumpEventQueue();
      queue.interrupt(folderPath: 'assets/reactions/', fileName: 'happy.vrma');

      expect(queue.currentFile, 'happy.vrma');
    });

    test('validates queue and interrupt playback inputs', () async {
      final controller = _FakeVrmController();
      addTearDown(controller.dispose);

      expect(
        () => VrmAnimationQueue(
          controller: controller,
          folderPath: ' ',
          fileNames: const <String>['idle.vrma'],
        ),
        throwsArgumentError,
      );
      expect(
        () => VrmAnimationQueue(
          controller: controller,
          folderPath: 'assets/vrma/',
          fileNames: const <String>['idle.vrma'],
          speed: 0,
        ),
        throwsArgumentError,
      );

      final queue = VrmAnimationQueue(
        controller: controller,
        folderPath: 'assets/vrma/',
        fileNames: const <String>['idle.vrma'],
      );
      addTearDown(queue.dispose);
      expect(
        () => queue.interrupt(
          folderPath: 'assets/reactions/',
          fileName: 'happy.vrma',
          speed: double.nan,
        ),
        throwsArgumentError,
      );
      expect(
        () => VrmAnimationQueueSnapshot(
          state: VrmAnimationQueueState.interrupted,
          playOrder: const <int>[0],
          currentIndex: 0,
          pauseAfterInterrupt: false,
          interruptFolderPath: 'assets/reactions/',
          interruptFileName: 'happy.vrma',
          interruptSpeed: 0,
        ),
        throwsFormatException,
      );
    });
  });
}

final class _FakeVrmController extends VrmController {
  final StreamController<VrmModelLoadedEvent> _modelLoaded =
      StreamController<VrmModelLoadedEvent>.broadcast();
  final StreamController<VrmAnimationFinishedEvent> _animationFinished =
      StreamController<VrmAnimationFinishedEvent>.broadcast();
  final StreamController<VrmRuntimeUnavailableEvent> _runtimeUnavailable =
      StreamController<VrmRuntimeUnavailableEvent>.broadcast();

  final List<String> playedFiles = <String>[];
  final List<String> playbackIds = <String>[];
  bool delayNextPlayback = false;
  Completer<VrmAnimationPlayback>? _delayedPlayback;
  int _playbackSequence = 0;

  @override
  bool get isModelLoaded => false;

  @override
  Stream<VrmModelLoadedEvent> get onModelLoaded => _modelLoaded.stream;

  @override
  Stream<VrmAnimationFinishedEvent> get onAnimationFinished =>
      _animationFinished.stream;

  @override
  Stream<VrmRuntimeUnavailableEvent> get onRuntimeUnavailable =>
      _runtimeUnavailable.stream;

  void emitModelLoaded() {
    _modelLoaded.add(VrmModelLoadedEvent(name: 'Avatar', version: '1'));
  }

  void emitAnimationFinished(String playbackId) {
    _animationFinished.add(
      VrmAnimationFinishedEvent(name: 'Animation', playbackId: playbackId),
    );
  }

  void emitRuntimeUnavailable() {
    _runtimeUnavailable.add(
      VrmRuntimeUnavailableEvent(reason: 'test runtime lost'),
    );
  }

  void completeDelayedPlayback({Object? error}) {
    final completer = _delayedPlayback;
    if (completer == null) {
      throw StateError('No delayed animation playback.');
    }
    _delayedPlayback = null;
    delayNextPlayback = false;
    if (error != null) {
      completer.completeError(error);
    } else {
      completer.complete(VrmAnimationPlayback(id: playbackIds.last));
    }
  }

  @override
  Future<VrmAnimationPlayback> playAnimation(
    String folderPath,
    String fileName, {
    bool loop = true,
    double speed = 1,
    double fadeDuration = 0.5,
    VrmRootMotion rootMotion = VrmRootMotion.inPlace,
    String? clipName,
  }) {
    playedFiles.add(fileName);
    final playbackId = 'fake-playback-${_playbackSequence++}';
    playbackIds.add(playbackId);
    if (delayNextPlayback) {
      final completer = Completer<VrmAnimationPlayback>();
      _delayedPlayback = completer;
      return completer.future;
    }
    return Future<VrmAnimationPlayback>.value(
      VrmAnimationPlayback(id: playbackId),
    );
  }

  @override
  Future<void> dispose() async {
    await _modelLoaded.close();
    await _animationFinished.close();
    await _runtimeUnavailable.close();
    await super.dispose();
  }
}
