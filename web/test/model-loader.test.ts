import type { VRM } from "@pixiv/three-vrm";
import { Group } from "three";
import type { GLTF } from "three/addons/loaders/GLTFLoader.js";
import { describe, expect, it, vi } from "vitest";

import { VrmModelLoader } from "../src/model-loader";
import type { RuntimeResource } from "../src/resource-loader";

describe("VRM model loader", () => {
  it("loads a VRM and deduplicates integer progress updates", async () => {
    const { gltf, vrm } = createGltf(true);
    const parseAsync = vi.fn(async () => gltf);
    const fetchResource = vi.fn(async (_url, _signal, onProgress) => {
      onProgress?.(49, 100);
      onProgress?.(49.4, 100);
      onProgress?.(100, 100);
      return {
        data: new ArrayBuffer(8),
        byteLength: 8,
        contentType: "model/gltf-binary",
      };
    });
    const progress = vi.fn();
    const loader = new VrmModelLoader({
      fetchResource,
      createParser: () => ({ parseAsync }),
    });

    const loaded = await loader.load(
      "https://example.test/models/avatar.vrm",
      progress,
    );

    expect(loaded).toEqual({ gltf, vrm, sourceBytes: 8 });
    expect(parseAsync).toHaveBeenCalledWith(
      expect.any(ArrayBuffer),
      "https://example.test/models/",
    );
    expect(progress.mock.calls).toEqual([
      [{ percent: 49, loaded: 49, total: 100 }],
      [{ percent: 100, loaded: 100, total: 100 }],
    ]);
    expect(loader.isLoading).toBe(false);
  });

  it("disposes a parsed scene when cancellation wins the race", async () => {
    const { gltf } = createGltf(true);
    let resolveParse!: (value: GLTF) => void;
    const parsePromise = new Promise<GLTF>((resolve) => {
      resolveParse = resolve;
    });
    const parseAsync = vi.fn(() => parsePromise);
    const disposeScene = vi.fn();
    const loader = new VrmModelLoader({
      fetchResource: async () => ({
        data: new ArrayBuffer(1),
        byteLength: 1,
        contentType: "model/gltf-binary",
      }),
      createParser: () => ({ parseAsync }),
      disposeScene,
    });

    const pending = loader.load("https://example.test/avatar.vrm");
    await vi.waitFor(() => expect(parseAsync).toHaveBeenCalledOnce());
    loader.cancel();
    resolveParse(gltf);

    await expect(pending).rejects.toMatchObject({ code: "canceled" });
    expect(disposeScene).toHaveBeenCalledWith(gltf.scene);
    expect(loader.isLoading).toBe(false);
  });

  it("lets the newest request win when an older fetch ignores abort", async () => {
    const olderResource = deferred<RuntimeResource>();
    const olderDocument = createGltf(true);
    const newerDocument = createGltf(true);
    const oldData = new ArrayBuffer(1);
    const newData = new ArrayBuffer(2);
    const parseAsync = vi.fn(async (data: ArrayBuffer) =>
      data === oldData ? olderDocument.gltf : newerDocument.gltf
    );
    const disposeScene = vi.fn();
    const loader = new VrmModelLoader({
      fetchResource: (url) => url.endsWith("old.vrm")
        ? olderResource.promise
        : Promise.resolve(resource(newData)),
      createParser: () => ({ parseAsync }),
      disposeScene,
    });

    const olderLoad = loader.load("https://example.test/old.vrm");
    const newerLoad = loader.load("https://example.test/new.vrm");
    await expect(newerLoad).resolves.toMatchObject({
      vrm: newerDocument.vrm,
    });

    olderResource.resolve(resource(oldData));
    await expect(olderLoad).rejects.toMatchObject({ code: "canceled" });
    expect(disposeScene).toHaveBeenCalledOnce();
    expect(disposeScene).toHaveBeenCalledWith(olderDocument.gltf.scene);
    expect(loader.isLoading).toBe(false);
  });

  it("disposes glTF content that does not contain a VRM", async () => {
    const { gltf } = createGltf(false);
    const disposeScene = vi.fn();
    const loader = new VrmModelLoader({
      fetchResource: async () => ({
        data: new ArrayBuffer(1),
        byteLength: 1,
        contentType: "model/gltf-binary",
      }),
      createParser: () => ({ parseAsync: async () => gltf }),
      disposeScene,
    });

    await expect(
      loader.load("https://example.test/not-vrm.glb"),
    ).rejects.toThrow("Failed to parse a VRM model from the glTF container.");
    expect(disposeScene).toHaveBeenCalledWith(gltf.scene);
  });
});

function createGltf(withVrm: boolean): { gltf: GLTF; vrm: VRM } {
  const scene = new Group();
  const vrm = { scene } as VRM;
  const gltf = {
    scene,
    scenes: [scene],
    animations: [],
    cameras: [],
    asset: {},
    parser: {},
    userData: withVrm ? { vrm } : {},
  } as unknown as GLTF;
  return { gltf, vrm };
}

function resource(data: ArrayBuffer): RuntimeResource {
  return {
    data,
    byteLength: data.byteLength,
    contentType: "model/gltf-binary",
  };
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((complete) => { resolve = complete; });
  return { promise, resolve };
}
