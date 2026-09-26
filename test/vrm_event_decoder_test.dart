import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/flutter_three_vrm.dart';
import 'package:flutter_three_vrm/src/bridge/vrm_event_decoder.dart';

void main() {
  group('VRM runtime event decoder', () {
    test('decodes every protocol event without fallback values', () {
      final cases = <(String, Map<String, dynamic>, Matcher)>[
        (
          'onModelLoaded',
          <String, dynamic>{'name': 'Avatar', 'version': '1.0'},
          isA<VrmModelLoadedEvent>(),
        ),
        (
          'onModelLoadProgress',
          <String, dynamic>{'percent': 50, 'loaded': 5, 'total': 10},
          isA<VrmModelLoadProgressEvent>(),
        ),
        ('onModelReport', _modelReport(), isA<VrmModelReportEvent>()),
        ('onModelUnloaded', <String, dynamic>{}, isA<VrmModelUnloadedEvent>()),
        (
          'onAnimationStarted',
          <String, dynamic>{'name': 'Wave', 'playbackId': 'playback-1'},
          isA<VrmAnimationStartedEvent>(),
        ),
        (
          'onAnimationFinished',
          <String, dynamic>{'name': 'Wave', 'playbackId': 'playback-1'},
          isA<VrmAnimationFinishedEvent>(),
        ),
        (
          'onExpressionChanged',
          <String, dynamic>{'expression': 'blinkLeft', 'layer': 'eyes'},
          isA<VrmExpressionChangedEvent>(),
        ),
        (
          'onSpeechFinished',
          <String, dynamic>{'sessionId': 'speech-1'},
          isA<VrmSpeechFinishedEvent>(),
        ),
        (
          'onError',
          <String, dynamic>{'message': 'Renderer failed.'},
          isA<VrmErrorEvent>(),
        ),
        (
          'onStateChanged',
          <String, dynamic>{'state': 'initialized'},
          isA<VrmStateChangedEvent>(),
        ),
        (
          'onCameraChanged',
          <String, dynamic>{
            'x': 0.1,
            'y': -0.2,
            'zoom': 1.5,
            'userInitiated': true,
          },
          isA<VrmCameraChangedEvent>(),
        ),
        ('onPerformance', _performance(), isA<VrmPerformanceEvent>()),
        (
          'onWebGLContextChanged',
          <String, dynamic>{'state': 'restored'},
          isA<VrmWebGlContextEvent>(),
        ),
        ('onTap', <String, dynamic>{'x': 12.5, 'y': 8.25}, isA<VrmTapEvent>()),
      ];

      for (final (name, payload, matcher) in cases) {
        expect(decodeVrmRuntimeEventEnvelope(_event(name, payload)), matcher);
      }
    });

    test('preserves exact enum and numeric event values', () {
      final expression =
          decodeVrmRuntimeEventEnvelope(
                _event('onExpressionChanged', <String, dynamic>{
                  'expression': 'blinkLeft',
                  'layer': 'eyes',
                }),
              )
              as VrmExpressionChangedEvent;
      expect(expression.expression, VrmExpression.blinkLeft);
      expect(expression.layer, ExpressionLayer.eyes);

      final camera =
          decodeVrmRuntimeEventEnvelope(
                _event('onCameraChanged', <String, dynamic>{
                  'x': 0.1,
                  'y': -0.2,
                  'zoom': 1.5,
                  'userInitiated': true,
                }),
              )
              as VrmCameraChangedEvent;
      expect(camera.x, 0.1);
      expect(camera.y, -0.2);
      expect(camera.zoom, 1.5);
      expect(camera.userInitiated, isTrue);
    });

    test('rejects values that the old decoder silently replaced', () {
      final invalidCases = <(String, Map<String, dynamic>)>[
        ('onModelLoaded', <String, dynamic>{'version': '1.0'}),
        (
          'onModelLoadProgress',
          <String, dynamic>{'percent': 1.5, 'loaded': 1, 'total': 2},
        ),
        (
          'onModelLoadProgress',
          <String, dynamic>{'percent': 50, 'loaded': 11, 'total': 10},
        ),
        ('onModelReport', <String, dynamic>{..._modelReport(), 'height': 0}),
        ('onModelUnloaded', <String, dynamic>{'stale': true}),
        ('onAnimationStarted', <String, dynamic>{'playbackId': 'playback-1'}),
        (
          'onExpressionChanged',
          <String, dynamic>{'expression': 'smirk', 'layer': 'eyes'},
        ),
        (
          'onExpressionChanged',
          <String, dynamic>{'expression': 'happy', 'layer': 'face'},
        ),
        ('onSpeechFinished', <String, dynamic>{'sessionId': ''}),
        ('onError', <String, dynamic>{'message': ''}),
        ('onStateChanged', <String, dynamic>{'state': 'ready'}),
        (
          'onCameraChanged',
          <String, dynamic>{'x': 0, 'y': 0, 'zoom': 0, 'userInitiated': false},
        ),
        ('onCameraChanged', <String, dynamic>{'x': 0, 'y': 0, 'zoom': 1}),
        (
          'onPerformance',
          <String, dynamic>{..._performance(), 'drawCalls': -1},
        ),
        ('onWebGLContextChanged', <String, dynamic>{'state': 'paused'}),
        ('onTap', <String, dynamic>{'x': 1}),
      ];

      for (final (name, payload) in invalidCases) {
        expect(
          () => decodeVrmRuntimeEventEnvelope(_event(name, payload)),
          throwsFormatException,
          reason: name,
        );
      }
    });

    test('rejects malformed event envelopes', () {
      expect(
        () => decodeVrmRuntimeEventEnvelope(<String, dynamic>{
          'version': 2,
          'type': 'event',
          'event': 'onTap',
          'payload': <String, dynamic>{'x': 1, 'y': 2},
        }),
        throwsFormatException,
      );
      expect(
        () => decodeVrmRuntimeEventEnvelope(<String, dynamic>{
          'version': 3,
          'type': 'event',
          'event': 'onTap',
          'payload': null,
        }),
        throwsFormatException,
      );
    });
  });
}

Map<String, dynamic> _event(String name, Map<String, dynamic> payload) {
  return <String, dynamic>{
    'version': 3,
    'type': 'event',
    'event': name,
    'payload': payload,
  };
}

Map<String, dynamic> _modelReport() {
  return <String, dynamic>{
    'name': 'Avatar',
    'vrmVersion': '1.0',
    'sourceBytes': 1024,
    'height': 1.7,
    'meshes': 1,
    'skinnedMeshes': 1,
    'geometries': 1,
    'materials': 1,
    'textures': 1,
    'texturePixels': 1024,
    'estimatedTextureMemoryBytes': 4096,
    'maxTextureWidth': 32,
    'maxTextureHeight': 32,
    'vertices': 3,
    'triangles': 1,
    'morphTargets': 0,
    'humanoidBones': 1,
    'springBoneJoints': 0,
  };
}

Map<String, dynamic> _performance() {
  return <String, dynamic>{
    'fps': 60,
    'frameTimeMs': 16.67,
    'frameTimeP50Ms': 16.5,
    'frameTimeP95Ms': 18.2,
    'frameSampleCount': 60,
    'longFrameCount': 0,
    'longestFrameMs': 0.0,
    'longFrameThresholdMs': 25.0,
    'updateTimeP95Ms': 2.0,
    'renderTimeP95Ms': 3.0,
    'longFrameSource': 'none',
    'pixelRatio': 1,
    'fpsCap': 60,
    'physicsEnabled': true,
    'adaptiveQualityEnabled': true,
    'adaptiveTargetFps': 60,
    'adaptiveSlowWindowCount': 0,
    'adaptiveFastWindowCount': 1,
    'adaptiveCooldownRemainingMs': 0.0,
    'adaptiveDecision': 'collectingFast',
    'drawCalls': 1,
    'triangles': 1,
    'geometries': 1,
    'textures': 1,
    'reason': 'sample',
  };
}
