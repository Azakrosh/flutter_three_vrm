import '../bridge/vrm_protocol_contract.dart';
import '../content/vrm_content_host.dart';

typedef VrmHostedResourceCommandSender =
    Future<void> Function(
      VrmProtocolCommand action,
      Map<String, dynamic> payload,
    );

/// Owns temporary loopback-resource exposure for controller commands.
///
/// This is internal package infrastructure. It keeps the content-host lifetime
/// separate from the public [VrmController] facade and always releases an
/// exposed URI after the runtime command settles.
final class VrmHostedResourceDispatcher {
  VrmHostedResourceDispatcher(this._ensureActive, this._sendCommand);

  final void Function() _ensureActive;
  final VrmHostedResourceCommandSender _sendCommand;

  VrmContentHost? _contentHost;

  void attach(VrmContentHost contentHost) {
    _ensureActive();
    _contentHost = contentHost;
  }

  /// Detaches [contentHost] only when it is the currently attached host.
  ///
  /// Returns whether the active host was detached.
  bool detach(VrmContentHost contentHost) {
    if (!identical(_contentHost, contentHost)) return false;
    _contentHost = null;
    return true;
  }

  Future<void> send({
    required Uri Function(VrmContentHost host) expose,
    required VrmProtocolCommand action,
    required String fileName,
    String urlField = 'url',
    Map<String, dynamic>? payload,
  }) async {
    _ensureActive();
    final host = _requiredContentHost;
    final uri = expose(host);
    try {
      await _sendCommand(action, <String, dynamic>{
        ...?payload,
        urlField: uri.toString(),
        'fileName': fileName,
      });
    } finally {
      host.release(uri);
    }
  }

  VrmContentHost get _requiredContentHost {
    final contentHost = _contentHost;
    if (contentHost == null || !contentHost.isStarted) {
      throw StateError(
        'VrmView is not ready. Wait for VrmView.onCreated before loading '
        'assets or local files.',
      );
    }
    return contentHost;
  }
}
