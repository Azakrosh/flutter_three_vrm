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
  });
}

final class _FakeVrmController extends VrmController {
  final StreamController<VrmModelLoadedEvent> _modelLoaded =
      StreamController<VrmModelLoadedEvent>.broadcast();
  final StreamController<VrmAnimationFinishedEvent> _animationFinished =
      StreamController<VrmAnimationFinishedEvent>.broadcast();

  final List<String> playedFiles = <String>[];

  @override
  bool get isModelLoaded => false;

  @override
  Stream<VrmModelLoadedEvent> get onModelLoaded => _modelLoaded.stream;

  @override
  Stream<VrmAnimationFinishedEvent> get onAnimationFinished =>
      _animationFinished.stream;

  void emitModelLoaded() {
    _modelLoaded.add(VrmModelLoadedEvent(name: 'Avatar', version: '1'));
  }

  @override
  Future<void> playAnimation(
    String folderPath,
    String fileName, {
    bool loop = true,
    double speed = 1,
    double fadeDuration = 0.5,
    VrmRootMotion rootMotion = VrmRootMotion.inPlace,
    String? clipName,
  }) async {
    playedFiles.add(fileName);
  }

  @override
  Future<void> dispose() async {
    await _modelLoaded.close();
    await _animationFinished.close();
    await super.dispose();
  }
}
