export interface AdaptiveQualityConfig {
  readonly enabled: boolean;
  readonly targetFps: number;
  readonly minPixelRatio: number;
  readonly maxPixelRatio: number;
}

export interface QualityAdjustment {
  readonly pixelRatio: number;
  readonly reason: "performanceDown" | "performanceUp";
}

const defaultConfig: AdaptiveQualityConfig = {
  enabled: true,
  targetFps: 55,
  minPixelRatio: 0.75,
  maxPixelRatio: 1.5,
};

export class AdaptiveQualityController {
  private _config: AdaptiveQualityConfig = defaultConfig;
  private slowWindows = 0;
  private fastWindows = 0;
  private lastAdjustmentMs = Number.NEGATIVE_INFINITY;

  public get config(): AdaptiveQualityConfig {
    return this._config;
  }

  public configure(value: unknown): AdaptiveQualityConfig {
    if (!isRecord(value)) throw new TypeError("Adaptive quality settings must be an object.");

    const config: AdaptiveQualityConfig = {
      enabled: readBoolean(value.enabled, defaultConfig.enabled, "enabled"),
      targetFps: readNumber(value.targetFps, defaultConfig.targetFps, 15, 120, "targetFps"),
      minPixelRatio: readNumber(
        value.minPixelRatio,
        defaultConfig.minPixelRatio,
        0.5,
        3,
        "minPixelRatio",
      ),
      maxPixelRatio: readNumber(
        value.maxPixelRatio,
        defaultConfig.maxPixelRatio,
        0.5,
        3,
        "maxPixelRatio",
      ),
    };
    if (config.minPixelRatio > config.maxPixelRatio) {
      throw new RangeError("minPixelRatio must not exceed maxPixelRatio.");
    }

    this._config = config;
    this.slowWindows = 0;
    this.fastWindows = 0;
    this.lastAdjustmentMs = Number.NEGATIVE_INFINITY;
    return config;
  }

  public evaluate(
    measuredFps: number,
    currentPixelRatio: number,
    fpsCap: number,
    nowMs: number,
  ): QualityAdjustment | null {
    const config = this._config;
    if (!config.enabled || !Number.isFinite(measuredFps) || measuredFps <= 0) return null;

    const effectiveTarget = fpsCap > 0
      ? Math.min(config.targetFps, fpsCap)
      : config.targetFps;
    if (measuredFps < effectiveTarget * 0.82) {
      this.slowWindows += 1;
      this.fastWindows = 0;
    } else if (measuredFps >= effectiveTarget * 0.97) {
      this.fastWindows += 1;
      this.slowWindows = 0;
    } else {
      this.slowWindows = 0;
      this.fastWindows = 0;
    }

    if (nowMs - this.lastAdjustmentMs < 4000) return null;

    if (this.slowWindows >= 3 && currentPixelRatio > config.minPixelRatio + 0.01) {
      this.slowWindows = 0;
      this.lastAdjustmentMs = nowMs;
      return {
        pixelRatio: roundRatio(Math.max(config.minPixelRatio, currentPixelRatio - 0.15)),
        reason: "performanceDown",
      };
    }
    if (this.fastWindows >= 8 && currentPixelRatio < config.maxPixelRatio - 0.01) {
      this.fastWindows = 0;
      this.lastAdjustmentMs = nowMs;
      return {
        pixelRatio: roundRatio(Math.min(config.maxPixelRatio, currentPixelRatio + 0.1)),
        reason: "performanceUp",
      };
    }
    return null;
  }
}

function roundRatio(value: number): number {
  return Math.round(value * 100) / 100;
}

function readBoolean(value: unknown, fallback: boolean, field: string): boolean {
  if (value === undefined) return fallback;
  if (typeof value !== "boolean") throw new TypeError(`${field} must be a boolean.`);
  return value;
}

function readNumber(
  value: unknown,
  fallback: number,
  minimum: number,
  maximum: number,
  field: string,
): number {
  if (value === undefined) return fallback;
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new TypeError(`${field} must be a finite number.`);
  }
  if (value < minimum || value > maximum) {
    throw new RangeError(`${field} must be between ${minimum} and ${maximum}.`);
  }
  return value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
