import type { VRM } from "@pixiv/three-vrm";
import type {
  BufferGeometry,
  Material,
  Mesh,
  Object3D,
  Texture,
} from "three";

export interface RuntimeModelReport {
  readonly name: string;
  readonly vrmVersion: string;
  readonly sourceBytes: number;
  readonly height: number;
  readonly meshes: number;
  readonly skinnedMeshes: number;
  readonly geometries: number;
  readonly materials: number;
  readonly textures: number;
  readonly texturePixels: number;
  readonly estimatedTextureMemoryBytes: number;
  readonly maxTextureWidth: number;
  readonly maxTextureHeight: number;
  readonly vertices: number;
  readonly triangles: number;
  readonly morphTargets: number;
  readonly humanoidBones: number;
  readonly springBoneJoints: number;
}

export function createRuntimeModelReport(
  vrm: VRM,
  sourceBytes: number,
  height: number,
  detachedSpringBoneJoints = 0,
): RuntimeModelReport {
  const geometries = new Set<BufferGeometry>();
  const materials = new Set<Material>();
  const textures = new Set<Texture>();
  let meshes = 0;
  let skinnedMeshes = 0;
  let vertices = 0;
  let triangles = 0;
  let morphTargets = 0;
  let maxTextureWidth = 0;
  let maxTextureHeight = 0;
  let texturePixels = 0;

  vrm.scene.traverse((object) => {
    if (!isMesh(object)) return;
    meshes += 1;
    if ("isSkinnedMesh" in object && object.isSkinnedMesh === true) {
      skinnedMeshes += 1;
    }

    const geometry = object.geometry;
    if (!geometries.has(geometry)) {
      geometries.add(geometry);
      const vertexCount = geometry.attributes.position?.count ?? 0;
      vertices += vertexCount;
      triangles += geometry.index?.count === undefined
        ? vertexCount / 3
        : geometry.index.count / 3;
      morphTargets += geometry.morphAttributes.position?.length ?? 0;
    }

    const objectMaterials = Array.isArray(object.material)
      ? object.material
      : [object.material];
    for (const material of objectMaterials) {
      if (material === undefined || materials.has(material)) continue;
      materials.add(material);
      for (const value of Object.values(material)) {
        if (!isTexture(value) || textures.has(value)) continue;
        textures.add(value);
        const width = readImageDimension(value.image, "width");
        const imageHeight = readImageDimension(value.image, "height");
        maxTextureWidth = Math.max(maxTextureWidth, width);
        maxTextureHeight = Math.max(maxTextureHeight, imageHeight);
        texturePixels += width * imageHeight;
      }
    }
  });

  return {
    name:
      readMetaString(vrm.meta, "name") ||
      readMetaString(vrm.meta, "title") ||
      "VRM Model",
    vrmVersion: readMetaString(vrm.meta, "metaVersion") || "1.0",
    sourceBytes,
    height,
    meshes,
    skinnedMeshes,
    geometries: geometries.size,
    materials: materials.size,
    textures: textures.size,
    texturePixels: Math.round(texturePixels),
    estimatedTextureMemoryBytes: Math.round(texturePixels * 4 * 4 / 3),
    maxTextureWidth,
    maxTextureHeight,
    vertices,
    triangles: Math.round(triangles),
    morphTargets,
    humanoidBones: Object.keys(
      vrm.humanoid?.normalizedHumanBones ?? {},
    ).length,
    springBoneJoints:
      vrm.springBoneManager?.joints.size ?? detachedSpringBoneJoints,
  };
}

function isMesh(object: Object3D): object is Mesh {
  return "isMesh" in object && object.isMesh === true;
}

function isTexture(value: unknown): value is Texture {
  return (
    typeof value === "object" &&
    value !== null &&
    "isTexture" in value &&
    value.isTexture === true
  );
}

function readImageDimension(
  image: unknown,
  dimension: "width" | "height",
): number {
  if (
    typeof image !== "object" ||
    image === null ||
    !(dimension in image)
  ) {
    return 0;
  }
  const value = Number((image as Record<string, unknown>)[dimension]);
  return Number.isFinite(value) && value > 0 ? value : 0;
}

function readMetaString(meta: unknown, field: string): string | undefined {
  if (typeof meta !== "object" || meta === null || !(field in meta)) {
    return undefined;
  }
  const value = (meta as Record<string, unknown>)[field];
  return typeof value === "string" && value.length > 0 ? value : undefined;
}
