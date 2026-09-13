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

  Uri exposeFileBundle(
    Map<String, File> files, {
    required String entryFileName,
  });

  Uri exposeBytesBundle(
    Map<String, Uint8List> files, {
    required String entryFileName,
  });

  void release(Uri uri);

  Future<void> close();
}
