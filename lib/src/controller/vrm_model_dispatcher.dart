import '../bridge/vrm_protocol_contract.dart';
import '../content/vrm_content_host.dart';
import '../recovery/vrm_model_session_state.dart';
import 'vrm_hosted_resource_dispatcher.dart';

typedef VrmModelCommandSender =
    Future<void> Function(
      VrmProtocolCommand action, [
      Map<String, dynamic>? payload,
    ]);

/// Owns model transfer commands and their generation-safe session state.
final class VrmModelDispatcher {
  VrmModelDispatcher(this._hostedResources, this._sendCommand);

  final VrmHostedResourceDispatcher _hostedResources;
  final VrmModelCommandSender _sendCommand;
  final VrmModelSessionState _state = VrmModelSessionState();

  bool get isLoading => _state.isLoading;
  bool get isLoaded => _state.isLoaded;

  void restoreLoaded(bool loaded) => _state.setLoaded(loaded);

  void invalidateRuntime() => _state.invalidateRuntime();

  Future<void> loadHosted({
    required Uri Function(VrmContentHost host) expose,
    required String fileName,
  }) {
    return _runLoad(
      () => _hostedResources.send(
        expose: expose,
        action: VrmProtocolCommand.loadModelFromUrl,
        fileName: fileName,
      ),
    );
  }

  Future<void> loadUrl(String url) {
    return _runLoad(
      () => _sendCommand(VrmProtocolCommand.loadModelFromUrl, {
        'url': url,
        'fileName': Uri.parse(url).pathSegments.lastOrNull ?? 'avatar.vrm',
      }),
    );
  }

  Future<void> cancelLoad() {
    _state.cancelLoad();
    return _sendCommand(VrmProtocolCommand.cancelModelLoad);
  }

  Future<void> unload({required int speechRevision}) async {
    _state.cancelLoad();
    await _sendCommand(VrmProtocolCommand.unloadModel, {
      'speechRevision': speechRevision,
    });
    _state.setLoaded(false);
  }

  Future<void> _runLoad(Future<void> Function() command) async {
    final generation = _state.beginLoad();
    try {
      await command();
      _state.completeLoad(generation);
    } finally {
      _state.finishLoad(generation);
    }
  }
}
