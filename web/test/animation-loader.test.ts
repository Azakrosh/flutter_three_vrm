import { Group } from "three";
import type { GLTF } from "three/addons/loaders/GLTFLoader.js";
import { describe, expect, it, vi } from "vitest";

import { VrmAnimationLoader } from "../src/animation-loader";
import type { RuntimeResource } from "../src/resource-loader";

describe("VRM animation loader", () => {
  it("parses binary animation data and releases the source scene after playback", async () => {
    const gltf = createGltf();
    const parseAsync = vi.fn(async () => gltf);
    const disposeScene = vi.fn();
    const consume = vi.fn();
    const data = new ArrayBuffer(8);
    const loader = new VrmAnimationLoader({
      fetchResource: async () => resource(data, "model/gltf-binary"),
      createParser: () => ({ parseAsync }),
      disposeScene,
    });

    await loader.load("https://example.test/motions/wave.vrma", consume);

    expect(parseAsync).toHaveBeenCalledWith(data, "https://example.test/motions/");
    expect(consume).toHaveBeenCalledOnce();
    expect(consume).toHaveBeenCalledWith(gltf);
    expect(disposeScene).toHaveBeenCalledOnce();
    expect(disposeScene).toHaveBeenCalledWith(gltf.scene);
    expect(loader.isLoading).toBe(false);
  });

  it("decodes external-resource glTF as text before parsing", async () => {
    const parseAsync = vi.fn(async () => createGltf());
    const data = new TextEncoder().encode('{"asset":{"version":"2.0"}}').buffer;
    const loader = new VrmAnimationLoader({
      fetchResource: async () => resource(data, "application/octet-stream"),
      createParser: () => ({ parseAsync }),
      disposeScene: vi.fn(),
    });

    await loader.load("https://example.test/walk.GLTF?token=opaque", vi.fn());

    expect(parseAsync).toHaveBeenCalledWith(
      '{"asset":{"version":"2.0"}}',
      "https://example.test/",
    );
  });

  it("disposes a parsed scene and never plays it after cancellation", async () => {
    const gltf = createGltf();
    const parsed = deferred<GLTF>();
    const parseAsync = vi.fn(() => parsed.promise);
    const consume = vi.fn();
    const disposeScene = vi.fn();
    const loader = new VrmAnimationLoader({
      fetchResource: async () => resource(new ArrayBuffer(1), "model/gltf-binary"),
      createParser: () => ({ parseAsync }),
      disposeScene,
    });

    const pending = loader.load("https://example.test/idle.vrma", consume);
    await vi.waitFor(() => expect(parseAsync).toHaveBeenCalledOnce());
    loader.cancel();
    parsed.resolve(gltf);

    await expect(pending).rejects.toMatchObject({ code: "canceled" });
    expect(consume).not.toHaveBeenCalled();
    expect(disposeScene).toHaveBeenCalledOnce();
    expect(disposeScene).toHaveBeenCalledWith(gltf.scene);
    expect(loader.isLoading).toBe(false);
  });

  it("lets the newest request win even when an old fetch ignores abort", async () => {
    const older = deferred<RuntimeResource>();
    const gltf = createGltf();
    const parseAsync = vi.fn(async () => gltf);
    const oldConsumer = vi.fn();
    const newConsumer = vi.fn();
    const disposeScene = vi.fn();
    const loader = new VrmAnimationLoader({
      fetchResource: (url) => url.endsWith("old.vrma")
        ? older.promise
        : Promise.resolve(resource(new ArrayBuffer(1), "model/gltf-binary")),
      createParser: () => ({ parseAsync }),
      disposeScene,
    });

    const oldRequest = loader.load("https://example.test/old.vrma", oldConsumer);
    await loader.load("https://example.test/new.vrma", newConsumer);
    older.resolve(resource(new ArrayBuffer(1), "model/gltf-binary"));

    await expect(oldRequest).rejects.toMatchObject({ code: "canceled" });
    expect(oldConsumer).not.toHaveBeenCalled();
    expect(newConsumer).toHaveBeenCalledOnce();
    expect(parseAsync).toHaveBeenCalledOnce();
    expect(disposeScene).toHaveBeenCalledOnce();
  });

  it("releases parsed content when playback throws and preserves the error", async () => {
    const gltf = createGltf();
    const disposeScene = vi.fn();
    const loader = new VrmAnimationLoader({
      fetchResource: async () => resource(new ArrayBuffer(1), "model/gltf-binary"),
      createParser: () => ({ parseAsync: async () => gltf }),
      disposeScene,
    });

    await expect(loader.load("https://example.test/bad.vrma", () => {
      throw new Error("Playback failed.");
    })).rejects.toThrow("Playback failed.");
    expect(disposeScene).toHaveBeenCalledWith(gltf.scene);
    expect(loader.isLoading).toBe(false);
  });
});

function resource(data: ArrayBuffer, contentType: string): RuntimeResource {
  return { data, byteLength: data.byteLength, contentType };
}

function createGltf(): GLTF {
  return {
    scene: new Group(),
    animations: [],
    userData: {},
  } as unknown as GLTF;
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((complete) => { resolve = complete; });
  return { promise, resolve };
}
