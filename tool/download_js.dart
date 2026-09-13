// ignore_for_file: avoid_print

import 'dart:io';

void main() async {
  final dir = Directory('assets/web/js');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  final files = {
    'assets/web/js/three.module.js':
        'https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.module.js',
    'assets/web/js/three-vrm.module.js':
        'https://cdn.jsdelivr.net/npm/@pixiv/three-vrm@2.1.0/lib/three-vrm.module.js',
    'assets/web/js/three-vrm-animation.module.js':
        'https://cdn.jsdelivr.net/npm/@pixiv/three-vrm-animation@2.1.0/lib/three-vrm-animation.module.js',
    'assets/web/js/GLTFLoader.js':
        'https://cdn.jsdelivr.net/npm/three@0.160.0/examples/jsm/loaders/GLTFLoader.js',
    'assets/web/js/OrbitControls.js':
        'https://cdn.jsdelivr.net/npm/three@0.160.0/examples/jsm/controls/OrbitControls.js',
    'assets/web/utils/BufferGeometryUtils.js':
        'https://cdn.jsdelivr.net/npm/three@0.160.0/examples/jsm/utils/BufferGeometryUtils.js',
  };

  // Создаем папку utils, если её нет
  final utilsDir = Directory('assets/web/utils');
  if (!utilsDir.existsSync()) {
    utilsDir.createSync(recursive: true);
  }

  final client = HttpClient();
  for (final entry in files.entries) {
    print('Downloading ${entry.key}...');
    try {
      final request = await client.getUrl(Uri.parse(entry.value));
      final response = await request.close();
      
      if (response.statusCode != 200) {
        print('Error downloading ${entry.key}: HTTP ${response.statusCode} - ${response.reasonPhrase}');
        continue;
      }
      
      final file = File(entry.key);
      await response.pipe(file.openWrite());
      print('Saved ${entry.key} (${file.lengthSync()} bytes)');
    } catch (e) {
      print('Error downloading ${entry.key}: $e');
    }
  }
  
  // Force close the client to immediately terminate the Dart process
  client.close(force: true);
}
