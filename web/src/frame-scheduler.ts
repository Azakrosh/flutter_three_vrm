export interface RuntimeFrame {
  readonly now: number;
  readonly delta: number;
  readonly elapsedTime: number;
}

export interface RuntimeFrameSchedulerDependencies {
  readonly now: () => number;
  readonly requestFrame: (callback: FrameRequestCallback) => number;
  readonly cancelFrame: (id: number) => void;
  readonly shouldRender: (now: number) => boolean;
  readonly isContextLost: () => boolean;
  readonly resetGraphicsTiming: (now: number) => void;
  readonly onFrame: (frame: RuntimeFrame) => void;
}

/** Owns frame scheduling and timing; the runtime facade owns frame contents. */
export class RuntimeFrameScheduler {
  private pendingFrameId: number | null = null;
  private paused = false;
  private disposed = false;
  private generation = 0;
  private lastTime: number;
  private elapsed = 0;

  public constructor(
    private readonly dependencies: RuntimeFrameSchedulerDependencies,
    initialTime = dependencies.now(),
  ) {
    this.lastTime = initialTime;
  }

  public get isPaused(): boolean {
    return this.paused;
  }

  public get elapsedTime(): number {
    return this.elapsed;
  }

  public start(): void {
    if (this.disposed || this.paused || this.pendingFrameId !== null) return;
    this.scheduleNext();
  }

  public pause(): void {
    if (this.disposed || this.paused) return;
    this.paused = true;
    this.generation += 1;
    this.cancelPending();
  }

  public resume(): void {
    if (this.disposed || !this.paused) return;
    this.paused = false;
    this.resetTiming();
    this.scheduleNext();
  }

  public resetTiming(): void {
    if (this.disposed) return;
    const now = this.dependencies.now();
    this.lastTime = now;
    this.dependencies.resetGraphicsTiming(now);
  }

  public dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.paused = true;
    this.generation += 1;
    this.cancelPending();
  }

  private cancelPending(): void {
    if (this.pendingFrameId === null) return;
    this.dependencies.cancelFrame(this.pendingFrameId);
    this.pendingFrameId = null;
  }

  private scheduleNext(): void {
    const generation = this.generation;
    this.pendingFrameId = this.dependencies.requestFrame(
      () => this.tick(generation),
    );
  }

  private tick(generation: number): void {
    if (generation !== this.generation) return;
    this.pendingFrameId = null;
    if (this.paused || this.disposed) return;
    this.scheduleNext();

    const now = this.dependencies.now();
    if (this.dependencies.isContextLost()) return;
    if (!this.dependencies.shouldRender(now)) return;

    const delta = Math.max(0, Math.min((now - this.lastTime) / 1000, 0.1));
    this.lastTime = now;
    this.elapsed += delta;
    this.dependencies.onFrame({ now, delta, elapsedTime: this.elapsed });
  }
}
