import {
  parseRuntimeAnimationOptions,
} from "./motion-controller";
import { parseRuntimeLightingConfig } from "./scene-controller";

type RuntimeRecord = Readonly<Record<string, unknown>>;

export function findAnimationLightingPayloadError(
  action: string,
  payload: RuntimeRecord,
): string | null {
  try {
    switch (action) {
      case "playAnimationFromUrl":
        parseRuntimeAnimationOptions(payload.options);
        return null;
      case "setLighting":
        parseRuntimeLightingConfig(payload);
        return null;
      default:
        return null;
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return `Command payload ${action} is invalid: ${message}`;
  }
}
