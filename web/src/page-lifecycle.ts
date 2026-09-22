export interface RuntimePageViewport {
  readonly width: number;
  readonly height: number;
}

export interface RuntimePageLifecycleDependencies {
  readonly page: EventTarget;
  readonly getViewport: () => RuntimePageViewport;
  readonly resizeScene: (width: number, height: number) => void;
  readonly hasCustomCameraTransform: () => boolean;
  readonly frameAvatar: () => void;
  readonly cleanupSteps: readonly (() => void)[];
  readonly onCleanupError?: (error: unknown) => void;
}

/** Owns page listeners and an idempotent, best-effort cleanup sequence. */
export class RuntimePageLifecycle {
  private attached = false;
  private disposed = false;
  private readonly onResize = (): void => this.handleResize();
  private readonly onPageHide = (): void => this.dispose();

  public constructor(
    private readonly dependencies: RuntimePageLifecycleDependencies,
  ) {}

  public get isDisposed(): boolean {
    return this.disposed;
  }

  public attach(): void {
    if (this.attached || this.disposed) return;
    this.attached = true;
    this.dependencies.page.addEventListener("resize", this.onResize);
    this.dependencies.page.addEventListener("pagehide", this.onPageHide);
  }

  public dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.detach();
    for (const cleanup of this.dependencies.cleanupSteps) {
      try {
        cleanup();
      } catch (error) {
        (this.dependencies.onCleanupError ?? console.error)(error);
      }
    }
  }

  private detach(): void {
    if (!this.attached) return;
    this.attached = false;
    this.dependencies.page.removeEventListener("resize", this.onResize);
    this.dependencies.page.removeEventListener("pagehide", this.onPageHide);
  }

  private handleResize(): void {
    if (this.disposed) return;
    const viewport = this.dependencies.getViewport();
    this.dependencies.resizeScene(viewport.width, viewport.height);
    if (!this.dependencies.hasCustomCameraTransform()) {
      this.dependencies.frameAvatar();
    }
  }
}
