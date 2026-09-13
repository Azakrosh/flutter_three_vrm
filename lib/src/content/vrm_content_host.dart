import 'dart:io';
import 'dart:typed_data';

/// Serves only resources explicitly registered for one [VrmView] session.
abstract interface class VrmContentHost {
  bool get isStarted;

  Uri get runtimeUri;

  Future<void> start();

  Uri exposeAsset(String assetKey);

  Uri exposeFile(File file);

  Uri exposeBytes(Uint8List bytes, {required String fileName});

  void release(Uri uri);

  Future<void> close();
}
