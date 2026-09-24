import type { VRM } from "@pixiv/three-vrm";
import {
  BoxGeometry,
  Group,
  Mesh,
  MeshStandardMaterial,
  ShaderMaterial,
  Texture,
} from "three";
import { describe, expect, it } from "vitest";

import { createRuntimeModelReport } from "../src/model-report";

describe("runtime model report", () => {
  it("counts shared resources once and reads Set-based spring bones", () => {
    const scene = new Group();
    const geometry = new BoxGeometry(1, 1, 1);
    const texture = new Texture();
    texture.image = {
      width: 1,
      height: 1,
      naturalWidth: 512,
      naturalHeight: 256,
    } as unknown as HTMLImageElement;
    const material = new MeshStandardMaterial({ map: texture });
    const uniformTexture = new Texture();
    uniformTexture.image = {
      width: 64,
      height: 32,
    } as unknown as HTMLImageElement;
    const shaderMaterial = new ShaderMaterial({
      uniforms: { map: { value: uniformTexture } },
    });
    scene.add(
      new Mesh(geometry, material),
      new Mesh(geometry, material),
      new Mesh(geometry, shaderMaterial),
    );
    const vrm = {
      scene,
      meta: { name: "Test Avatar", metaVersion: "1" },
      humanoid: {
        normalizedHumanBones: { head: {}, hips: {} },
      },
      springBoneManager: {
        joints: new Set([{}, {}, {}]),
      },
    } as unknown as VRM;

    const report = createRuntimeModelReport(vrm, 4096, 1.72);

    expect(report).toMatchObject({
      name: "Test Avatar",
      vrmVersion: "1",
      sourceBytes: 4096,
      height: 1.72,
      meshes: 3,
      skinnedMeshes: 0,
      geometries: 1,
      materials: 2,
      textures: 2,
      texturePixels: 512 * 256 + 64 * 32,
      estimatedTextureMemoryBytes: Math.round(
        (512 * 256 + 64 * 32) * 4 * 4 / 3,
      ),
      maxTextureWidth: 512,
      maxTextureHeight: 256,
      vertices: 24,
      triangles: 12,
      morphTargets: 0,
      humanoidBones: 2,
      springBoneJoints: 3,
    });
  });

  it("uses the detached spring-bone count when physics is disabled", () => {
    const vrm = {
      scene: new Group(),
      meta: {},
      humanoid: { normalizedHumanBones: {} },
    } as unknown as VRM;

    expect(createRuntimeModelReport(vrm, 0, 1.6, 7)).toMatchObject({
      name: "VRM Model",
      vrmVersion: "1.0",
      springBoneJoints: 7,
    });
  });

  it("uses the VRM 0 title when name metadata is unavailable", () => {
    const vrm = {
      scene: new Group(),
      meta: { title: "Legacy Avatar", metaVersion: "0" },
      humanoid: { normalizedHumanBones: {} },
    } as unknown as VRM;

    expect(createRuntimeModelReport(vrm, 0, 1.6)).toMatchObject({
      name: "Legacy Avatar",
      vrmVersion: "0",
    });
  });
});
