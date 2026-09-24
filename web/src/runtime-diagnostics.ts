export class RuntimeDiagnostics {
  private contextLossCountValue = 0;
  private lastModelLoadDurationMsValue = 0;

  public get contextLossCount(): number {
    return this.contextLossCountValue;
  }

  public get lastModelLoadDurationMs(): number {
    return this.lastModelLoadDurationMsValue;
  }

  public recordContextLoss(): void {
    this.contextLossCountValue += 1;
  }

  public recordSuccessfulModelLoad(
    startedAtMs: number,
    completedAtMs: number,
  ): void {
    if (!Number.isFinite(startedAtMs) || !Number.isFinite(completedAtMs)) {
      return;
    }
    this.lastModelLoadDurationMsValue = Math.max(
      0,
      completedAtMs - startedAtMs,
    );
  }
}
