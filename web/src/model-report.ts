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
      for (const texture of findMaterialTextures(material)) {
        if (textures.has(texture)) continue;
        textures.add(texture);
        const { width, height: imageHeight } = readTextureDimensions(texture);
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

function* findMaterialTextures(material: Material): Generator<Texture> {
  for (const value of Object.values(material)) {
    yield* readTextureValues(value);
  }
  if (!("uniforms" in material) || !isRecord(material.uniforms)) return;
  for (const uniform of Object.values(material.uniforms)) {
    const value = isRecord(uniform) && "value" in uniform
      ? uniform.value
      : uniform;
    yield* readTextureValues(value);
  }
}

function* readTextureValues(value: unknown): Generator<Texture> {
  if (isTexture(value)) {
    yield value;
    return;
  }
  if (!Array.isArray(value)) return;
  for (const item of value) {
    if (isTexture(item)) yield item;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function readTextureDimensions(texture: Texture): {
  readonly width: number;
  readonly height: number;
} {
  const image = Array.isArray(texture.image)
    ? texture.image[0]
    : texture.image;
  const mipmap = texture.mipmaps[0];
  const width = readImageDimension(image, [
    "naturalWidth",
    "videoWidth",
    "displayWidth",
    "width",
  ]) || readImageDimension(mipmap, ["width"]);
  const height = readImageDimension(image, [
    "naturalHeight",
    "videoHeight",
    "displayHeight",
    "height",
  ]) || readImageDimension(mipmap, ["height"]);
  return { width, height };
}

function readImageDimension(
  image: unknown,
  fields: readonly string[],
): number {
  if (typeof image !== "object" || image === null) return 0;
  const record = image as Record<string, unknown>;
  for (const field of fields) {
    const value = Number(record[field]);
    if (Number.isFinite(value) && value > 0) return value;
  }
  return 0;
}

function readMetaString(meta: unknown, field: string): string | undefined {
  if (typeof meta !== "object" || meta === null || !(field in meta)) {
    return undefined;
  }
  const value = (meta as Record<string, unknown>)[field];
  return typeof value === "string" && value.length > 0 ? value : undefined;
}
