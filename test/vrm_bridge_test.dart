import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/src/bridge/vrm_bridge.dart';
import 'package:flutter_three_vrm/src/bridge/vrm_protocol_contract.dart';
import 'package:flutter_three_vrm/src/models/vrm_events.dart';
import 'package:flutter_three_vrm/src/models/vrm_exception.dart';

void main() {
  group('VrmBridge', () {
    test('completes successful and runtime-error responses', () async {
      final scripts = <String>[];
      final bridge = _attachedBridge(scripts.add);
      addTearDown(bridge.dispose);

      final success = bridge.requestCommand(
        VrmProtocolCommand.getRuntimeHealth,
      );
      final successCommand = _decodeCommand(scripts.removeAt(0));
      bridge.handleJsMessage(
        jsonEncode(<String, Object?>{
          'version': vrmProtocolVersion,
          'id': successCommand['id'],
          'type': 'response',
          'ok': true,
          'result': <String, Object>{'ready': true},
        }),
      );

      expect(await success, <String, Object>{'ready': true});

      final failure = bridge.requestCommand(VrmProtocolCommand.getModelReport);
      final failureCommand = _decodeCommand(scripts.removeAt(0));
      final failureExpectation = expectLater(
        failure,
        throwsA(
          isA<VrmRuntimeException>()
              .having((error) => error.code, 'code', 'modelMissing')
              .having((error) => error.message, 'message', 'No model loaded.'),
        ),
      );
      bridge.handleJsMessage(
        jsonEncode(<String, Object?>{
          'version': vrmProtocolVersion,
          'id': failureCommand['id'],
          'type': 'response',
          'ok': false,
          'error': <String, Object>{
            'code': 'modelMissing',
            'message': 'No model loaded.',
          },
        }),
      );
      await failureExpectation;
    });

    test('fails a correlated malformed response immediately', () async {
      final scripts = <String>[];
      final bridge = _attachedBridge(
        scripts.add,
        commandTimeout: const Duration(days: 1),
      );
      addTearDown(bridge.dispose);

      final result = bridge.requestCommand(VrmProtocolCommand.getPose);
      final command = _decodeCommand(scripts.single);
      final expectation = expectLater(result, throwsA(isA<FormatException>()));

      bridge.handleJsMessage(
        jsonEncode(<String, Object?>{
          'version': vrmProtocolVersion + 1,
          'id': command['id'],
          'type': 'response',
          'ok': true,
          'result': const <String, Object>{},
        }),
      );

      await expectation;
    });

    test('times out once and consumes a predictable late response', () async {
      final scripts = <String>[];
      final bridge = _attachedBridge(
        scripts.add,
        commandTimeout: const Duration(milliseconds: 5),
      );
      addTearDown(bridge.dispose);
      final asyncErrors = <VrmErrorEvent>[];
      final subscription = bridge.eventStream
          .where((event) => event is VrmErrorEvent)
          .cast<VrmErrorEvent>()
          .listen(asyncErrors.add);
      addTearDown(subscription.cancel);

      final result = bridge.requestCommand(VrmProtocolCommand.getTransform);
      final command = _decodeCommand(scripts.single);
      await expectLater(result, throwsA(isA<TimeoutException>()));

      bridge.handleJsMessage(
        jsonEncode(<String, Object?>{
          'version': vrmProtocolVersion,
          'id': command['id'],
          'type': 'response',
          'ok': true,
          'result': <String, Object>{'x': 0, 'y': 0, 'zoom': 1},
        }),
      );
      await Future<void>.delayed(Duration.zero);

      expect(asyncErrors, isEmpty);
    });

    test(
      'reports uncorrelated malformed input and fails pending on detach',
      () async {
        final scripts = <String>[];
        final owner = Object();
        final bridge = VrmBridge(commandTimeout: const Duration(seconds: 1));
        bridge.attachTransport(
          owner: owner,
          runJavaScript: (source) async => scripts.add(source),
          reloadRuntime: () async {},
          runtimeReady: true,
        );
        addTearDown(bridge.dispose);

        final malformedEvent = bridge.eventStream
            .where((event) => event is VrmErrorEvent)
            .cast<VrmErrorEvent>()
            .first;
        bridge.handleJsMessage('[]');
        expect((await malformedEvent).message, contains('Bridge message'));

        final pending = bridge.requestCommand(VrmProtocolCommand.getPose);
        final expectation = expectLater(pending, throwsA(isA<StateError>()));
        await bridge.detachTransport(owner);
        await expectation;

        expect(scripts, hasLength(1));
        expect(bridge.isRuntimeReady, isFalse);
      },
    );
    test(
      'dispatch failure completes once and consumes a late response',
      () async {
        final scripts = <String>[];
        final dispatch = Completer<void>();
        final bridge = VrmBridge(commandTimeout: const Duration(seconds: 1));
        bridge.attachTransport(
          owner: Object(),
          runJavaScript: (source) {
            scripts.add(source);
            return dispatch.future;
          },
          reloadRuntime: () async {},
          runtimeReady: true,
        );
        addTearDown(bridge.dispose);
        final asyncErrors = <VrmErrorEvent>[];
        final subscription = bridge.eventStream
            .where((event) => event is VrmErrorEvent)
            .cast<VrmErrorEvent>()
            .listen(asyncErrors.add);
        addTearDown(subscription.cancel);

        final result = bridge.requestCommand(VrmProtocolCommand.getPose);
        final command = _decodeCommand(scripts.single);
        final expectation = expectLater(result, throwsA(isA<StateError>()));
        dispatch.completeError(StateError('WebView dispatch failed'));
        await expectation;

        bridge.handleJsMessage(
          jsonEncode(<String, Object?>{
            'version': vrmProtocolVersion,
            'id': command['id'],
            'type': 'response',
            'ok': true,
            'result': const <String, Object>{},
          }),
        );
        await Future<void>.delayed(Duration.zero);

        expect(asyncErrors, isEmpty);
      },
    );

    test('detach waits for the active native dispatch', () async {
      final owner = Object();
      final dispatch = Completer<void>();
      final bridge = VrmBridge(commandTimeout: const Duration(seconds: 1));
      bridge.attachTransport(
        owner: owner,
        runJavaScript: (_) => dispatch.future,
        reloadRuntime: () async {},
        runtimeReady: true,
      );
      addTearDown(bridge.dispose);

      final response = bridge.requestCommand(VrmProtocolCommand.getPose);
      final responseExpectation = expectLater(
        response,
        throwsA(isA<StateError>()),
      );
      final detach = bridge.detachTransport(owner);
      expect(await _isCompleted(detach), isFalse);

      dispatch.complete();
      await detach;
      await responseExpectation;
    });

    test('detach waits for an active runtime reload', () async {
      final owner = Object();
      final reload = Completer<void>();
      final bridge = VrmBridge(commandTimeout: const Duration(seconds: 1));
      bridge.attachTransport(
        owner: owner,
        runJavaScript: (_) async {},
        reloadRuntime: () => reload.future,
        runtimeReady: true,
      );
      addTearDown(bridge.dispose);

      final reloadOperation = bridge.reloadRuntime();
      final detach = bridge.detachTransport(owner);
      expect(await _isCompleted(detach), isFalse);

      reload.complete();
      await Future.wait<void>([reloadOperation, detach]);
    });

    test('dispose shares one future and waits for native dispatch', () async {
      final dispatch = Completer<void>();
      final bridge = VrmBridge(commandTimeout: const Duration(seconds: 1));
      bridge.attachTransport(
        owner: Object(),
        runJavaScript: (_) => dispatch.future,
        reloadRuntime: () async {},
        runtimeReady: true,
      );

      final response = bridge.requestCommand(VrmProtocolCommand.getPose);
      final responseExpectation = expectLater(
        response,
        throwsA(isA<StateError>()),
      );
      final first = bridge.dispose();
      final second = bridge.dispose();
      expect(identical(first, second), isTrue);
      expect(await _isCompleted(first), isFalse);

      dispatch.complete();
      await first;
      await responseExpectation;
    });
  });
}

Future<bool> _isCompleted(Future<void> future) async {
  var completed = false;
  unawaited(future.then<void>((_) => completed = true, onError: (_) {}));
  await Future<void>.delayed(Duration.zero);
  return completed;
}

VrmBridge _attachedBridge(
  void Function(String source) onScript, {
  Duration commandTimeout = const Duration(seconds: 1),
}) {
  final bridge = VrmBridge(commandTimeout: commandTimeout);
  bridge.attachTransport(
    owner: Object(),
    runJavaScript: (source) async => onScript(source),
    reloadRuntime: () async {},
    runtimeReady: true,
  );
  return bridge;
}

Map<String, dynamic> _decodeCommand(String source) {
  const prefix = 'window.flutterVrmDispatch(';
  const suffix = ');';
  expect(source, startsWith(prefix));
  expect(source, endsWith(suffix));
  final encodedCommand = source.substring(
    prefix.length,
    source.length - suffix.length,
  );
  final commandJson = jsonDecode(encodedCommand) as String;
  return jsonDecode(commandJson) as Map<String, dynamic>;
}
