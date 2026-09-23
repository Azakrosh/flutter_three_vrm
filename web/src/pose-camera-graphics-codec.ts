import {
  parseRuntimeCameraTransform,
} from "./camera-controller";
import {
  parseRuntimeGraphicsSettings,
} from "./graphics-controller";
import {
  parseAdaptiveQualityConfig,
} from "./performance";
import { parseNormalizedPose } from "./pose";

type RuntimeRecord = Readonly<Record<string, unknown>>;

/**
 * Validates structured Pose, camera, and graphics payloads at the protocol
 * boundary while reusing the parsers owned by their runtime domains.
 */
export function findPoseCameraGraphicsPayloadError(
  action: string,
  payload: RuntimeRecord,
): string | null {
  try {
    switch (action) {
      case "setPose":
        parseNormalizedPose(payload.pose);
        requireNonNegativeFinite(payload.fadeDuration, "fadeDuration");
        return null;
      case "resetPose":
        requireNonNegativeFinite(payload.fadeDuration, "fadeDuration");
        return null;
      case "setCameraMode":
        if (payload.mode !== "constrained" && payload.mode !== "free") {
          throw new TypeError('mode must be "constrained" or "free".');
        }
        return null;
      case "resetCamera":
        requireNonNegativeFinite(payload.durationMs, "durationMs");
        return null;
      case "setTransform":
        parseRuntimeCameraTransform(payload.transform);
        return null;
      case "setGraphicsSettings":
        parseRuntimeGraphicsSettings(payload.settings);
        return null;
      case "setGraphicsPreset":
        if (
          payload.preset !== "performance" &&
          payload.preset !== "balanced" &&
          payload.preset !== "quality"
        ) {
          throw new TypeError(
            'preset must be "performance", "balanced", or "quality".',
          );
        }
        return null;
      case "setAdaptiveQuality":
        parseAdaptiveQualityConfig(payload.settings);
        return null;
      case "setRenderQuality":
        requirePositiveFinite(payload.pixelRatio, "pixelRatio");
        return null;
      default:
        return null;
    }
  } catch (error) {
    return `Command payload ${action} is invalid: ${readMessage(error)}`;
  }
}

function requireNonNegativeFinite(value: unknown, field: string): void {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    throw new TypeError(`${field} must be a non-negative finite number.`);
  }
}

function requirePositiveFinite(value: unknown, field: string): void {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    throw new TypeError(`${field} must be a positive finite number.`);
  }
}

function readMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
