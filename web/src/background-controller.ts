import {
  createRuntimeCanceledError,
  fetchRuntimeResource,
  isRuntimeCanceledError,
  type RuntimeResource,
} from "./resource-loader";

export interface RuntimeBackgroundStyle {
  backgroundColor: string;
  backgroundImage: string;
  backgroundSize: string;
  backgroundPosition: string;
}

export interface RuntimeBackgroundDependencies {
  readonly style: RuntimeBackgroundStyle;
  readonly setCanvasBackground: (
    colorHex: string | null,
    transparent: boolean,
  ) => void;
  readonly fetchResource?: (
    url: string,
    signal: AbortSignal,
  ) => Promise<RuntimeResource>;
  readonly createObjectUrl?: (blob: Blob) => string;
  readonly revokeObjectUrl?: (url: string) => void;
}

/** Owns background transfers, CSS presentation, and WebView-owned Blob URLs. */
export class RuntimeBackgroundController {
  private readonly fetchResource: NonNullable<
    RuntimeBackgroundDependencies["fetchResource"]
  >;
  private readonly createObjectUrl: NonNullable<
    RuntimeBackgroundDependencies["createObjectUrl"]
  >;
  private readonly revokeObjectUrl: NonNullable<
    RuntimeBackgroundDependencies["revokeObjectUrl"]
  >;
  private activeController: AbortController | null = null;
  private generation = 0;
  private objectUrl: string | null = null;
  private disposed = false;

  public constructor(
    private readonly dependencies: RuntimeBackgroundDependencies,
  ) {
    this.fetchResource = dependencies.fetchResource ?? fetchRuntimeResource;
    this.createObjectUrl =
      dependencies.createObjectUrl ?? ((blob) => URL.createObjectURL(blob));
    this.revokeObjectUrl =
      dependencies.revokeObjectUrl ?? ((url) => URL.revokeObjectURL(url));
  }

  public async setBackground(
    colorHex: string,
    imageUrl: string | null | undefined,
    transparent: boolean,
    hostedImage = false,
  ): Promise<void> {
    if (this.disposed) {
      throw createRuntimeCanceledError("Background controller was disposed.");
    }
    this.cancelLoad();

    if (!imageUrl || !hostedImage) {
      this.applyBackground(colorHex, imageUrl, transparent);
      this.replaceObjectUrl(null);
      return;
    }

    const generation = this.generation;
    const controller = new AbortController();
    this.activeController = controller;
    let pendingObjectUrl: string | null = null;
    try {
      const resource = await this.fetchResource(imageUrl, controller.signal);
      this.throwIfCanceled(controller, generation);
      const blob = new Blob([resource.data], {
        type: resource.contentType || "application/octet-stream",
      });
      pendingObjectUrl = this.createObjectUrl(blob);
      this.throwIfCanceled(controller, generation);

      this.applyBackground(colorHex, pendingObjectUrl, transparent);
      this.replaceObjectUrl(pendingObjectUrl);
      pendingObjectUrl = null;
    } catch (error) {
      if (pendingObjectUrl !== null) {
        this.revokeObjectUrl(pendingObjectUrl);
      }
      if (
        controller.signal.aborted ||
        generation !== this.generation ||
        isRuntimeCanceledError(error)
      ) {
        throw createRuntimeCanceledError("Background loading was canceled.");
      }
      throw error;
    } finally {
      if (this.activeController === controller) {
        this.activeController = null;
      }
    }
  }

  public cancelLoad(): void {
    this.activeController?.abort();
    this.activeController = null;
    this.generation += 1;
  }

  public dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.cancelLoad();
    this.replaceObjectUrl(null);
    this.dependencies.style.backgroundImage = "none";
  }

  private applyBackground(
    colorHex: string,
    imageUrl: string | null | undefined,
    transparent: boolean,
  ): void {
    const style = this.dependencies.style;
    if (imageUrl) {
      style.backgroundColor = colorHex || "#000000";
      style.backgroundImage = `url(${JSON.stringify(imageUrl)})`;
      style.backgroundSize = "cover";
      style.backgroundPosition = "center";
      this.dependencies.setCanvasBackground(null, true);
      return;
    }
    style.backgroundImage = "none";
    if (transparent) {
      style.backgroundColor = "transparent";
      this.dependencies.setCanvasBackground(null, true);
    } else {
      style.backgroundColor = colorHex;
      this.dependencies.setCanvasBackground(colorHex, false);
    }
  }

  private replaceObjectUrl(nextUrl: string | null): void {
    const previous = this.objectUrl;
    this.objectUrl = nextUrl;
    if (previous !== null && previous !== nextUrl) {
      this.revokeObjectUrl(previous);
    }
  }

  private throwIfCanceled(
    controller: AbortController,
    generation: number,
  ): void {
    if (controller.signal.aborted || generation !== this.generation) {
      throw createRuntimeCanceledError("Background loading was canceled.");
    }
  }
}
