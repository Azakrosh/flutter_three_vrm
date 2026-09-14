/// Geometry, texture, and rig characteristics of the loaded VRM avatar.
final class VrmModelReport {
  const VrmModelReport({
    required this.name,
    required this.vrmVersion,
    required this.sourceBytes,
    required this.height,
    required this.meshes,
    required this.skinnedMeshes,
    required this.geometries,
    required this.materials,
    required this.textures,
    required this.texturePixels,
    required this.estimatedTextureMemoryBytes,
    required this.maxTextureWidth,
    required this.maxTextureHeight,
    required this.vertices,
    required this.triangles,
    required this.morphTargets,
    required this.humanoidBones,
    required this.springBoneJoints,
  });

  final String name;
  final String vrmVersion;
  final int sourceBytes;
  final double height;
  final int meshes;
  final int skinnedMeshes;
  final int geometries;
  final int materials;
  final int textures;

  /// Sum of decoded texture width multiplied by height.
  final int texturePixels;

  /// Approximate upper bound for RGBA GPU allocation with a full mip chain.
  final int estimatedTextureMemoryBytes;

  final int maxTextureWidth;
  final int maxTextureHeight;
  final int vertices;
  final int triangles;
  final int morphTargets;
  final int humanoidBones;
  final int springBoneJoints;

  factory VrmModelReport.fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('VRM model report must be an object.');
    }
    int integer(String name) {
      final component = value[name];
      if (component case final num number when number.isFinite) {
        return number.toInt();
      }
      throw FormatException('$name must be a finite number.');
    }

    final rawHeight = value['height'];
    if (rawHeight is! num || !rawHeight.isFinite) {
      throw const FormatException('height must be a finite number.');
    }
    return VrmModelReport(
      name: value['name'] as String? ?? 'VRM Model',
      vrmVersion: value['vrmVersion'] as String? ?? '1.0',
      sourceBytes: integer('sourceBytes'),
      height: rawHeight.toDouble(),
      meshes: integer('meshes'),
      skinnedMeshes: integer('skinnedMeshes'),
      geometries: integer('geometries'),
      materials: integer('materials'),
      textures: integer('textures'),
      texturePixels: integer('texturePixels'),
      estimatedTextureMemoryBytes: integer('estimatedTextureMemoryBytes'),
      maxTextureWidth: integer('maxTextureWidth'),
      maxTextureHeight: integer('maxTextureHeight'),
      vertices: integer('vertices'),
      triangles: integer('triangles'),
      morphTargets: integer('morphTargets'),
      humanoidBones: integer('humanoidBones'),
      springBoneJoints: integer('springBoneJoints'),
    );
  }
}
