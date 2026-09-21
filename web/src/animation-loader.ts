import { VRMUtils } from "@pixiv/three-vrm";
import { VRMAnimationLoaderPlugin } from "@pixiv/three-vrm-animation";
import type { Object3D } from "three";
import {
  GLTFLoader,
  type GLTF,
} from "three/addons/loaders/GLTFLoader.js";

import {
  createRuntimeCanceledError,
  fetchRuntimeResource,
  isRuntimeCanceledError,
  type RuntimeResource,
} from "./resource-loader";

interface AnimationParser {
  parseAsync(data: ArrayBuffer | string, path: string): Promise<GLTF>;
}

export interface VrmAnimationLoaderDependencies {
  readonly fetchResource?: (
    url: string,
    signal: AbortSignal,
  ) => Promise<RuntimeResource>;
  readonly createParser?: () => AnimationParser;
  readonly disposeScene?: (scene: Object3D) => void;
}

/** Owns transfer, parsing, cancellation, and parsed-scene cleanup. */
export class VrmAnimationLoader {
  private readonly fetchResource: NonNullable<
    VrmAnimationLoaderDependencies["fetchResource"]
  >;
  private readonly createParser: NonNullable<
    VrmAnimationLoaderDependencies["createParser"]
  >;
  private readonly disposeScene: NonNullable<
    VrmAnimationLoaderDependencies["disposeScene"]
  >;
  private activeController: AbortController | null = null;
  private generation = 0;

  public constructor(dependencies: VrmAnimationLoaderDependencies = {}) {
    this.fetchResource = dependencies.fetchResource ?? fetchRuntimeResource;
    this.createParser = dependencies.createParser ?? createAnimationParser;
    this.disposeScene = dependencies.disposeScene ?? VRMUtils.deepDispose;
  }

  public get isLoading(): boolean {
    return this.activeController !== null;
  }

  public async load(
    url: string,
    consume: (gltf: GLTF) => void,
  ): Promise<void> {
    this.cancel();
    const generation = ++this.generation;
    const controller = new AbortController();
    this.activeController = controller;

    try {
      const resource = await this.fetchResource(url, controller.signal);
      this.throwIfCanceled(controller, generation);
      const isJson = resource.contentType.includes("json") ||
        new URL(url).pathname.toLowerCase().endsWith(".gltf");
      const input = isJson
        ? new TextDecoder().decode(resource.data)
        : resource.data;
      const gltf = await this.createParser().parseAsync(
        input,
        new URL(".", url).href,
      );
      try {
        this.throwIfCanceled(controller, generation);
        consume(gltf);
      } finally {
        if (gltf.scene) this.disposeScene(gltf.scene);
      }
    } catch (error) {
      if (
        controller.signal.aborted ||
        generation !== this.generation ||
        isRuntimeCanceledError(error)
      ) {
        throw createRuntimeCanceledError("Animation loading was canceled.");
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

  private throwIfCanceled(
    controller: AbortController,
    generation: number,
  ): void {
    if (controller.signal.aborted || generation !== this.generation) {
      throw createRuntimeCanceledError("Animation loading was canceled.");
    }
  }
}

function createAnimationParser(): AnimationParser {
  const loader = new GLTFLoader();
  loader.register((parser) => new VRMAnimationLoaderPlugin(parser));
  return loader;
}
