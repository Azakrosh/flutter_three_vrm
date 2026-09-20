import type { VRM } from "@pixiv/three-vrm";
import { VRMLoaderPlugin, VRMUtils } from "@pixiv/three-vrm";
import {
  GLTFLoader,
  type GLTF,
} from "three/addons/loaders/GLTFLoader.js";
import type { Object3D } from "three";

import {
  createRuntimeCanceledError,
  fetchRuntimeResource,
  isRuntimeCanceledError,
  type RuntimeResource,
  type RuntimeResourceProgress,
} from "./resource-loader";

export interface VrmModelLoadProgress {
  readonly percent: number;
  readonly loaded: number;
  readonly total: number;
}

export interface LoadedVrmDocument {
  readonly gltf: GLTF;
  readonly vrm: VRM;
  readonly sourceBytes: number;
}

interface VrmModelParser {
  parseAsync(data: ArrayBuffer, path: string): Promise<GLTF>;
}

export interface VrmModelLoaderDependencies {
  readonly fetchResource?: (
    url: string,
    signal: AbortSignal,
    onProgress?: RuntimeResourceProgress,
  ) => Promise<RuntimeResource>;
  readonly createParser?: () => VrmModelParser;
  readonly disposeScene?: (scene: Object3D) => void;
}

export class VrmModelLoader {
  private readonly fetchResource: NonNullable<
    VrmModelLoaderDependencies["fetchResource"]
  >;
  private readonly createParser: NonNullable<
    VrmModelLoaderDependencies["createParser"]
  >;
  private readonly disposeScene: NonNullable<
    VrmModelLoaderDependencies["disposeScene"]
  >;
  private activeController: AbortController | null = null;
  private generation = 0;
  private lastPercent = -1;

  public constructor(dependencies: VrmModelLoaderDependencies = {}) {
    this.fetchResource = dependencies.fetchResource ?? fetchRuntimeResource;
    this.createParser = dependencies.createParser ?? createVrmParser;
    this.disposeScene = dependencies.disposeScene ?? VRMUtils.deepDispose;
  }

  public get isLoading(): boolean {
    return this.activeController !== null;
  }

  public async load(
    url: string,
    onProgress?: (progress: VrmModelLoadProgress) => void,
  ): Promise<LoadedVrmDocument> {
    this.cancel();
    const generation = ++this.generation;
    const controller = new AbortController();
    this.activeController = controller;
    this.lastPercent = -1;

    try {
      const resource = await this.fetchResource(
        url,
        controller.signal,
        (loaded, total) => this.reportProgress(loaded, total, onProgress),
      );
      const gltf = await this.createParser().parseAsync(
        resource.data,
        new URL(".", url).href,
      );
      if (controller.signal.aborted || generation !== this.generation) {
        this.disposeScene(gltf.scene);
        throw createRuntimeCanceledError("Model loading was canceled.");
      }

      const vrm = gltf.userData.vrm as VRM | null | undefined;
      if (vrm == null) {
        this.disposeScene(gltf.scene);
        throw new Error("Failed to parse a VRM model from the glTF container.");
      }
      return { gltf, vrm, sourceBytes: resource.byteLength };
    } catch (error) {
      this.lastPercent = -1;
      if (controller.signal.aborted || isRuntimeCanceledError(error)) {
        throw createRuntimeCanceledError("Model loading was canceled.");
      }
      throw error;
    } finally {
      if (this.activeController === controller) {
        this.activeController = null;
      }
    }
  }

  public cancel(): void {
    this.activeController?.abort();
    this.activeController = null;
    this.generation += 1;
  }

  private reportProgress(
    loaded: number,
    total: number,
    onProgress: ((progress: VrmModelLoadProgress) => void) | undefined,
  ): void {
    if (total <= 0) return;
    const percent = Math.round((loaded / total) * 100);
    if (percent === this.lastPercent) return;
    this.lastPercent = percent;
    onProgress?.({ percent, loaded, total });
  }
}

function createVrmParser(): VrmModelParser {
  const loader = new GLTFLoader();
  loader.register((parser) => new VRMLoaderPlugin(parser));
  return loader;
}
