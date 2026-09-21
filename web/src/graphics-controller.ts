import { MathUtils } from "three";
import { AdaptiveQualityController, type AdaptiveQualityConfig } from "./performance";
import type { RuntimeSceneController } from "./scene-controller";

export interface RuntimeGraphicsSettings {
  readonly antialias?: boolean;
  readonly enablePhysics?: boolean;
  readonly fpsCap?: number;
  readonly pixelRatio?: number;
}

export interface RuntimePerformanceSnapshot {
  readonly fps: number;
  readonly frameTimeMs: number;
  readonly pixelRatio: number;
  readonly fpsCap: number;
  readonly physicsEnabled: boolean;
  readonly adaptiveQualityEnabled: boolean;
  readonly drawCalls: number;
  readonly triangles: number;
  readonly geometries: number;
  readonly textures: number;
  readonly reason: string;
}

export interface RuntimeGraphicsDependencies {
  readonly scene: Pick<RuntimeSceneController,
    "renderer" | "antialias" | "setPixelRatio" | "setShadows">;
  readonly recreateRenderer: (antialias: boolean) => void;
  readonly setPhysicsEnabled: (enabled: boolean) => void;
  readonly onPerformance: (snapshot: RuntimePerformanceSnapshot) => void;
  readonly devicePixelRatio: () => number;
}

export class RuntimeGraphicsController {
  private readonly adaptiveQuality = new AdaptiveQualityController();
  private physicsEnabledValue = true;
  private fpsCapValue = 60;
  private lastFrameTime = 0;
  private performanceWindowStart: number;
  private performanceFrameCount = 0;
  private lastPerformanceReport = 0;
  private snapshot: RuntimePerformanceSnapshot;

  public constructor(
    private readonly dependencies: RuntimeGraphicsDependencies,
    now = performance.now(),
  ) {
    this.performanceWindowStart = now;
    this.snapshot = {
      fps: 0,
      frameTimeMs: 0,
      pixelRatio: Math.min(dependencies.devicePixelRatio(), 1.5),
      fpsCap: this.fpsCapValue,
      physicsEnabled: this.physicsEnabledValue,
      adaptiveQualityEnabled: this.adaptiveQuality.config.enabled,
      drawCalls: 0,
      triangles: 0,
      geometries: 0,
      textures: 0,
      reason: "initialized",
    };
  }

  public get physicsEnabled(): boolean {
    return this.physicsEnabledValue;
  }

  public get fpsCap(): number {
    return this.fpsCapValue;
  }

  public shouldRender(now: number): boolean {
    if (this.fpsCapValue <= 0) return true;
    if (this.lastFrameTime <= 0) {
      this.lastFrameTime = now;
      return true;
    }
    const frameInterval = 1000 / this.fpsCapValue;
    const elapsedSinceFrame = now - this.lastFrameTime;
    if (this.lastFrameTime > 0 && elapsedSinceFrame < frameInterval * 0.9) return false;
    this.lastFrameTime = now - (elapsedSinceFrame % frameInterval);
    return true;
  }

  public resetTiming(now: number): void {
    this.lastFrameTime = 0;
    this.performanceWindowStart = now;
    this.performanceFrameCount = 0;
  }

  public setSettings(settings: RuntimeGraphicsSettings | null | undefined): void {
    if (settings == null) return;
    const { antialias, enablePhysics, fpsCap, pixelRatio } = settings;
    // Validate the complete request before mutating any settings.
    if (antialias !== undefined && typeof antialias !== "boolean") {
      throw new TypeError("antialias must be a boolean.");
    }
    if (enablePhysics !== undefined && typeof enablePhysics !== "boolean") {
      throw new TypeError("enablePhysics must be a boolean.");
    }
    if (fpsCap !== undefined && (!Number.isFinite(fpsCap) || fpsCap < 0)) {
      throw new TypeError("fpsCap must be zero or a positive finite number.");
    }
    if (pixelRatio !== undefined && (!Number.isFinite(pixelRatio) || pixelRatio <= 0)) {
      throw new TypeError("pixelRatio must be a positive finite number.");
    }

    if (antialias !== undefined && antialias !== this.dependencies.scene.antialias) {
      this.dependencies.recreateRenderer(antialias);
    }
    if (enablePhysics !== undefined) {
      this.physicsEnabledValue = enablePhysics;
      this.dependencies.setPhysicsEnabled(enablePhysics);
    }
    if (fpsCap !== undefined) {
      this.fpsCapValue = fpsCap === 0 ? 0 : MathUtils.clamp(Math.round(fpsCap), 1, 120);
      this.lastFrameTime = 0;
    }
    if (pixelRatio !== undefined) {
      this.dependencies.scene.setPixelRatio(MathUtils.clamp(pixelRatio, 0.5, 3));
    }
  }

  public setPreset(preset: string): void {
    if (preset !== "performance" && preset !== "balanced" && preset !== "quality") {
      throw new TypeError(`Unknown graphics preset: ${preset}.`);
    }
    this.dependencies.scene.setShadows(preset === "quality");
    this.setSettings({
      pixelRatio: preset === "performance"
        ? 1 : preset === "balanced" ? 1.5 : Math.min(this.dependencies.devicePixelRatio(), 2),
      antialias: preset !== "performance",
      enablePhysics: true,
      fpsCap: preset === "performance" ? 30 : 60,
    });
    if (this.adaptiveQuality.config.enabled) {
      this.setAdaptiveQuality(this.adaptiveQuality.config);
    }
  }

  public setAdaptiveQuality(settings: unknown): void {
    const config: AdaptiveQualityConfig = this.adaptiveQuality.configure(settings);
    this.dependencies.scene.setPixelRatio(MathUtils.clamp(
      this.dependencies.scene.renderer.getPixelRatio(),
      config.minPixelRatio,
      config.maxPixelRatio,
    ));
    this.snapshot = this.getSnapshot("configurationChanged");
  }

  public getSnapshot(reason = this.snapshot.reason): RuntimePerformanceSnapshot {
    const renderer = this.dependencies.scene.renderer;
    const info = renderer.info;
    return {
      fps: this.snapshot.fps,
      frameTimeMs: this.snapshot.frameTimeMs,
      pixelRatio: renderer.getPixelRatio(),
      fpsCap: this.fpsCapValue,
      physicsEnabled: this.physicsEnabledValue,
      adaptiveQualityEnabled: this.adaptiveQuality.config.enabled,
      drawCalls: info?.render.calls ?? 0,
      triangles: info?.render.triangles ?? 0,
      geometries: info?.memory.geometries ?? 0,
      textures: info?.memory.textures ?? 0,
      reason,
    };
  }

  public recordFrame(now: number): void {
    this.performanceFrameCount += 1;
    const windowDuration = now - this.performanceWindowStart;
    if (windowDuration < 1000) return;
    const fps = this.performanceFrameCount * 1000 / windowDuration;
    const frameTimeMs = windowDuration / this.performanceFrameCount;
    const adjustment = this.adaptiveQuality.evaluate(
      fps, this.dependencies.scene.renderer.getPixelRatio(), this.fpsCapValue, now,
    );
    if (adjustment) this.dependencies.scene.setPixelRatio(adjustment.pixelRatio);
    this.snapshot = {
      ...this.getSnapshot(adjustment?.reason ?? "sample"),
      fps,
      frameTimeMs,
    };
    if (adjustment || now - this.lastPerformanceReport >= 2000) {
      this.dependencies.onPerformance(this.snapshot);
      this.lastPerformanceReport = now;
    }
    this.performanceFrameCount = 0;
    this.performanceWindowStart = now;
  }
}
