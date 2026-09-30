import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/src/bridge/vrm_protocol_contract.dart';
import 'package:flutter_three_vrm/src/controller/vrm_speech_dispatcher.dart';
import 'package:flutter_three_vrm/src/models/vrm_lip_sync_data.dart';

void main() {
  group('VrmSpeechDispatcher', () {
    test('serializes direct inputs with monotonic revisions', () {
      final latest = <_LatestCall>[];
      final cleared = <String>[];
      var activeChecks = 0;
      final dispatcher = VrmSpeechDispatcher(
        () => activeChecks += 1,
        (_, [_]) async {},
        ({required channel, required action, required payload}) {
          latest.add(_LatestCall(channel, action, payload));
        },
        cleared.add,
      );

      dispatcher.setAmplitude(1.5);
      dispatcher.setViseme(VrmViseme.oh, weight: -0.5);
      final mouthRevision = dispatcher.takeMouthControl();

      expect(activeChecks, 2);
      expect(cleared, <String>[
        'directViseme',
        'lipSyncAmplitude',
        'lipSyncAmplitude',
        'directViseme',
      ]);
      expect(latest[0].channel, 'lipSyncAmplitude');
      expect(latest[0].action, VrmProtocolCommand.setLipSyncAmplitude);
      expect(latest[0].payload, <String, dynamic>{
        'amplitude': 1.0,
        'speechRevision': 1,
      });
      expect(latest[1].channel, 'directViseme');
      expect(latest[1].action, VrmProtocolCommand.setViseme);
      expect(latest[1].payload, <String, dynamic>{
        'viseme': 'oh',
        'weight': 0.0,
        'speechRevision': 2,
      });
      expect(mouthRevision, 3);
    });

    test(
      'replacement makes stale handles inert and finishing rejects frames',
      () async {
        final calls = <_CommandCall>[];
        final dispatcher = VrmSpeechDispatcher(
          () {},
          (action, [payload]) async {
            calls.add(_CommandCall(action, payload));
          },
          ({required channel, required action, required payload}) {},
          (_) {},
        );

        final first = await dispatcher.begin();
        final second = await dispatcher.begin(mode: VrmSpeechMode.amplitude);

        expect(dispatcher.isActive(first.id), isFalse);
        expect(dispatcher.isActive(second.id), isTrue);
        expect(
          await dispatcher.appendVisemes(first.id, <VisemeFrame>[
            VisemeFrame(viseme: VrmViseme.aa, timestamp: Duration.zero),
          ]),
          isFalse,
        );

        expect(
          await dispatcher.appendAmplitudes(second.id, const <AmplitudeFrame>[
            AmplitudeFrame(
              amplitude: 0.8,
              timestamp: Duration(milliseconds: 20),
            ),
            AmplitudeFrame(
              amplitude: 0.4,
              timestamp: Duration(milliseconds: 10),
            ),
          ]),
          isTrue,
        );
        final appendPayload = calls
            .lastWhere(
              (call) =>
                  call.action == VrmProtocolCommand.appendSpeechAmplitudes,
            )
            .payload!;
        final frames = appendPayload['frames'] as List<dynamic>;
        expect((frames.first as Map<String, dynamic>)['timestampMs'], 10);

        expect(
          await dispatcher.finish(second.id, const Duration(milliseconds: 240)),
          isTrue,
        );
        expect(
          await dispatcher.appendAmplitudes(
            second.id,
            const <AmplitudeFrame>[],
          ),
          isFalse,
        );

        dispatcher.handleFinished(second.id);
        expect(dispatcher.isActive(second.id), isFalse);
      },
    );

    test('failed stale begin cannot abandon its replacement', () async {
      final completions = <Completer<void>>[];
      final dispatcher = VrmSpeechDispatcher(
        () {},
        (action, [payload]) {
          final completion = Completer<void>();
          completions.add(completion);
          return completion.future;
        },
        ({required channel, required action, required payload}) {},
        (_) {},
      );

      final firstFuture = dispatcher.begin();
      final firstFailure = expectLater(firstFuture, throwsStateError);
      final secondFuture = dispatcher.begin(mode: VrmSpeechMode.amplitude);

      completions[1].complete();
      final second = await secondFuture;
      completions[0].completeError(StateError('stale command failed'));
      await firstFailure;

      expect(dispatcher.isActive(second.id), isTrue);
      expect(dispatcher.activeMode, VrmSpeechMode.amplitude);
    });

    test(
      'validates batch frames and cancels only the active session',
      () async {
        final calls = <_CommandCall>[];
        final dispatcher = VrmSpeechDispatcher(
          () {},
          (action, [payload]) async {
            calls.add(_CommandCall(action, payload));
          },
          ({required channel, required action, required payload}) {},
          (_) {},
        );

        await expectLater(
          dispatcher.enqueueVisemes(<VisemeFrame>[
            VisemeFrame(
              viseme: VrmViseme.aa,
              weight: double.nan,
              timestamp: Duration.zero,
            ),
          ]),
          throwsArgumentError,
        );

        final first = await dispatcher.begin();
        final second = await dispatcher.begin(mode: VrmSpeechMode.amplitude);

        expect(await dispatcher.cancelSession(first.id), isFalse);
        expect(await dispatcher.cancelSession(second.id), isTrue);
        expect(dispatcher.isActive(second.id), isFalse);

        final cancel = calls.last;
        expect(cancel.action, VrmProtocolCommand.cancelSpeech);
        expect(cancel.payload?['sessionId'], second.id);
        expect(cancel.payload?['speechRevision'], isA<int>());
      },
    );
  });
}

final class _CommandCall {
  const _CommandCall(this.action, this.payload);

  final VrmProtocolCommand action;
  final Map<String, dynamic>? payload;
}

final class _LatestCall {
  const _LatestCall(this.channel, this.action, this.payload);

  final String channel;
  final VrmProtocolCommand action;
  final Map<String, dynamic> payload;
}
