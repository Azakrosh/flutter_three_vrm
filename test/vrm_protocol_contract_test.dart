import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_three_vrm/src/bridge/vrm_protocol_contract.dart';

void main() {
  test('Dart command and event names match the shared contract manifest', () {
    final manifest =
        jsonDecode(File('tool/protocol_contract.json').readAsStringSync())
            as Map<String, dynamic>;

    expect(manifest['protocolVersion'], 3);
    expect(
      VrmProtocolCommand.values.map((value) => value.name).toSet(),
      (manifest['commands'] as List<dynamic>).cast<String>().toSet(),
    );
    expect(
      VrmProtocolEvent.values.map((value) => value.wireName).toSet(),
      (manifest['events'] as List<dynamic>).cast<String>().toSet(),
    );
  });

  test('event wire names preserve protocol capitalization', () {
    expect(
      vrmProtocolEventFromWireName('onWebGLContextChanged'),
      VrmProtocolEvent.onWebGlContextChanged,
    );
    expect(vrmProtocolEventFromWireName('onWebGlContextChanged'), isNull);
    expect(vrmProtocolEventFromWireName('unknownEvent'), isNull);
  });
}
