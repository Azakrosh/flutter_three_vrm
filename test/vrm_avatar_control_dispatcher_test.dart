import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/src/bridge/vrm_protocol_contract.dart';
import 'package:flutter_three_vrm/src/controller/vrm_avatar_control_dispatcher.dart';
import 'package:flutter_three_vrm/src/controller/vrm_speech_dispatcher.dart';
import 'package:flutter_three_vrm/src/models/vrm_expression.dart';
import 'package:flutter_three_vrm/src/models/vrm_pose.dart';

void main() {
  group('VrmAvatarControlDispatcher', () {
    test('serializes pose commands and decodes the queried pose', () async {
      final calls = <_CommandCall>[];
      final expectedPose = VrmPose({
        VrmHumanBone.head: const VrmPoseTransform(
          rotation: VrmQuaternion.identity(),
        ),
      });
      final dispatcher = VrmAvatarControlDispatcher(
        () {},
        (action, [payload]) async {
          calls.add(_CommandCall(action, payload));
        },
        (action, [payload]) async {
          expect(action, VrmProtocolCommand.getPose);
          expect(payload, isNull);
          return expectedPose.toJson();
        },
        (_, [_]) {},
        ({required channel, required action, required payload}) {},
        _speechDispatcher(),
      );

      final pose = await dispatcher.getPose();
      await dispatcher.setPose(pose, fadeDuration: 0.25);
      await dispatcher.resetPose(fadeDuration: 0);

      expect(pose.toJson(), expectedPose.toJson());
      expect(calls[0].action, VrmProtocolCommand.setPose);
      expect(calls[0].payload, <String, dynamic>{
        'pose': expectedPose.toJson(),
        'fadeDuration': 0.25,
      });
      expect(calls[1].action, VrmProtocolCommand.resetPose);
      expect(calls[1].payload, <String, dynamic>{'fadeDuration': 0.0});
      expect(
        () => dispatcher.setPose(pose, fadeDuration: double.nan),
        throwsArgumentError,
      );
    });

    test('coordinates mouth expressions with speech revisions', () {
      final emitted = <_CommandCall>[];
      final cleared = <String>[];
      final speech = VrmSpeechDispatcher(
        () {},
        (_, [_]) async {},
        ({required channel, required action, required payload}) {},
        cleared.add,
      );
      final dispatcher = VrmAvatarControlDispatcher(
        () {},
        (_, [_]) async {},
        (_, [_]) async => <String, Object>{},
        (action, [payload]) => emitted.add(_CommandCall(action, payload)),
        ({required channel, required action, required payload}) {},
        speech,
      );

      dispatcher.setExpression(VrmExpression.happy);
      dispatcher.setExpression(
        VrmExpression.aa,
        weight: 0.75,
        duration: const Duration(milliseconds: 400),
      );
      dispatcher.clearExpressionLayer(ExpressionLayer.mouth);
      dispatcher.clearAllExpressions();

      expect(emitted[0].payload, <String, dynamic>{
        'expression': 'happy',
        'layer': 'eyes',
        'weight': 1.0,
        'duration': 0.25,
        'disableAutoBlink': false,
      });
      expect(emitted[1].payload, <String, dynamic>{
        'expression': 'aa',
        'layer': 'mouth',
        'weight': 0.75,
        'duration': 0.4,
        'disableAutoBlink': false,
        'speechRevision': 1,
      });
      expect(emitted[2].payload?['speechRevision'], 2);
      expect(emitted[3].payload?['speechRevision'], 3);
      expect(cleared, hasLength(6));
    });

    test('validates custom blendshapes before emitting commands', () {
      final emitted = <_CommandCall>[];
      final dispatcher = VrmAvatarControlDispatcher(
        () {},
        (_, [_]) async {},
        (_, [_]) async => <String, Object>{},
        (action, [payload]) => emitted.add(_CommandCall(action, payload)),
        ({required channel, required action, required payload}) {},
        _speechDispatcher(),
      );

      dispatcher.setCustomBlendShape('smileWide', 0.6);

      expect(emitted.single.action, VrmProtocolCommand.setCustomBlendShape);
      expect(emitted.single.payload, <String, dynamic>{
        'name': 'smileWide',
        'weight': 0.6,
      });
      expect(
        () => dispatcher.setCustomBlendShape('  ', 0.5),
        throwsArgumentError,
      );
      expect(
        () => dispatcher.setExpression(VrmExpression.happy, weight: 1.1),
        throwsArgumentError,
      );
      expect(emitted, hasLength(1));
    });

    test('uses latest-value transport only for gaze targets', () {
      final emitted = <_CommandCall>[];
      final latest = <_LatestCall>[];
      var activeChecks = 0;
      final dispatcher = VrmAvatarControlDispatcher(
        () => activeChecks += 1,
        (_, [_]) async {},
        (_, [_]) async => <String, Object>{},
        (action, [payload]) => emitted.add(_CommandCall(action, payload)),
        ({required channel, required action, required payload}) {
          latest.add(_LatestCall(channel, action, payload));
        },
        _speechDispatcher(),
      );

      dispatcher.setAutoSaccades(enabled: false);
      dispatcher.setAutoBlink(true);
      dispatcher.setLookAtConfig(
        holdDuration: const Duration(milliseconds: 1500),
      );
      dispatcher.setLookAtTarget(const Offset(12.5, 8));

      expect(emitted.map((call) => call.action), <VrmProtocolCommand>[
        VrmProtocolCommand.setAutoSaccades,
        VrmProtocolCommand.setAutoBlink,
        VrmProtocolCommand.setLookAtConfig,
      ]);
      expect(emitted[2].payload, <String, dynamic>{'holdDurationSec': 1.5});
      expect(activeChecks, 1);
      expect(latest.single.channel, 'lookAtTarget');
      expect(latest.single.action, VrmProtocolCommand.setLookAtTarget);
      expect(latest.single.payload, <String, dynamic>{'x': 12.5, 'y': 8.0});

      expect(
        () => dispatcher.setLookAtTarget(const Offset(double.nan, 0)),
        throwsArgumentError,
      );
      expect(activeChecks, 2);
      expect(
        () => dispatcher.setLookAtConfig(
          holdDuration: const Duration(milliseconds: -1),
        ),
        throwsArgumentError,
      );
      expect(latest, hasLength(1));
    });
  });
}

VrmSpeechDispatcher _speechDispatcher() {
  return VrmSpeechDispatcher(
    () {},
    (_, [_]) async {},
    ({required channel, required action, required payload}) {},
    (_) {},
  );
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
