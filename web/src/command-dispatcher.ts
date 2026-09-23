import type {
  RuntimeCommandPayload,
} from "./protocol-contract";
import type { CommandEnvelope } from "./protocol";
import type {
  SpeechAmplitudeFrame,
  SpeechTimeline,
  SpeechVisemeFrame,
} from "./speech-timeline";
import type { RuntimeGazeController } from "./gaze-controller";
import type {
  RuntimeCameraMode,
  RuntimeCameraTransform,
} from "./camera-controller";
import type {
  RuntimeGraphicsPreset,
  RuntimeGraphicsSettings,
  RuntimePerformanceSnapshot,
} from "./graphics-controller";
import type { AdaptiveQualityConfig } from "./performance";
import type { RuntimePose } from "./pose";
import type { RuntimeAnimationOptions } from "./motion-controller";
import type { RuntimeModelReport } from "./model-report";
import type { RuntimeHealth } from "./runtime-health";
import type { RuntimeLightingConfig } from "./scene-controller";
import type {
  RuntimeExpressionLayer,
  RuntimeExpressionName,
  RuntimeWindDirection,
  RuntimeWindType,
} from "./interaction-protocol-codec";

export type RuntimeCommandDispatcher = (
  command: CommandEnvelope,
) => Promise<unknown>;

/**
 * The narrow surface that command routing may use on the runtime facade.
 * Keeping it explicit prevents the protocol layer from depending on the full
 * renderer implementation while the runner facade is migrated module by module.
 */
export interface RuntimeCommandHost {
  modelReport: RuntimeModelReport | null;
  speechTimeline: Pick<SpeechTimeline, "acceptInputRevision">;
  customBlendShapes: Map<string, number>;
  gazeController: Pick<
    RuntimeGazeController,
    "setTarget" | "setAutoSaccades" | "setHoldDuration"
  >;
  lipSyncAmplitude: number;
  autoBlinkEnabled: boolean;

  loadModelFromUrl(url: string): Promise<void>;
  cancelModelLoad(): void;
  getRuntimeHealth(): RuntimeHealth;
  unloadModel(): void;
  playAnimationFromUrl(
    url: string,
    options: RuntimeAnimationOptions,
  ): Promise<void>;
  cancelAnimationLoad(): void;
  pauseRendering(): void;
  resumeRendering(): void;
  transitionToRest(fadeDuration: number): void;
  pauseAnimation(): void;
  resumeAnimation(speed: number): void;
  setAnimationSpeed(speed: number): void;
  getPose(): RuntimePose;
  setPose(pose: RuntimePose, fadeDuration: number): void;
  setShadows(enabled: boolean): void;
  setExpression(
    expression: RuntimeExpressionName,
    layer: RuntimeExpressionLayer,
    weight: number,
    duration: number,
    disableAutoBlink: boolean,
  ): void;
  clearExpressionLayer(layer: RuntimeExpressionLayer): void;
  clearAllExpressions(): void;
  setViseme(viseme: string, weight: number): void;
  enqueueSpeechVisemes(
    payload: RuntimeCommandPayload<"enqueueSpeechVisemes">,
  ): void;
  enqueueSpeechAmplitudes(
    payload: RuntimeCommandPayload<"enqueueSpeechAmplitudes">,
  ): void;
  beginSpeech(payload: RuntimeCommandPayload<"beginSpeech">): boolean;
  appendSpeechVisemes(
    sessionId: string,
    frames: readonly SpeechVisemeFrame[],
  ): void;
  appendSpeechAmplitudes(
    sessionId: string,
    frames: readonly SpeechAmplitudeFrame[],
  ): void;
  finishSpeech(sessionId: string, audioDurationMs: number): void;
  cancelSpeech(sessionId?: string): void;
  setCameraMode(mode: RuntimeCameraMode): void;
  resetCamera(durationMs: number): void;
  getAvatarTransform(): RuntimeCameraTransform;
  setAvatarTransform(transform: RuntimeCameraTransform): void;
  setLighting(config: RuntimeLightingConfig): void;
  setBackground(
    color: string,
    imageUrl: string | null | undefined,
    transparent: boolean,
    hostedImage: boolean,
  ): Promise<void>;
  setPhysics(stiffness: number, gravity: number, drag: number): void;
  stopWind(): void;
  setWind(type: RuntimeWindType, direction: RuntimeWindDirection): void;
  setEnvironmentColor(color: string, intensity: number): void;
  setGraphicsSettings(settings: RuntimeGraphicsSettings): void;
  setGraphicsPreset(preset: RuntimeGraphicsPreset): void;
  setAdaptiveQuality(settings: Partial<AdaptiveQualityConfig>): void;
  getPerformanceSnapshot(): RuntimePerformanceSnapshot;
  setRenderQuality(pixelRatio: number): void;
}

export function createRuntimeCommandDispatcher(
  host: RuntimeCommandHost,
): RuntimeCommandDispatcher {
  return async (command): Promise<unknown> => {
    switch (command.action) {
      case "loadModelFromUrl":
        await host.loadModelFromUrl(command.payload.url);
        return null;
      case "cancelModelLoad":
        host.cancelModelLoad();
        return null;
      case "getModelReport":
        if (host.modelReport === null) {
          throw new Error("Load a VRM model before requesting its report.");
        }
        return host.modelReport;
      case "getRuntimeHealth":
        return host.getRuntimeHealth();
      case "unloadModel":
        host.cancelModelLoad();
        host.cancelAnimationLoad();
        host.speechTimeline.acceptInputRevision(command.payload.speechRevision);
        host.unloadModel();
        return null;
      case "playAnimationFromUrl":
        await host.playAnimationFromUrl(
          command.payload.url,
          command.payload.options,
        );
        return null;
      case "cancelAnimationLoad":
        host.cancelAnimationLoad();
        return null;
      case "pauseAnimation":
        host.pauseAnimation();
        return null;
      case "resumeAnimation":
        host.resumeAnimation(command.payload.speed);
        return null;
      case "pauseRendering":
        host.pauseRendering();
        return null;
      case "resumeRendering":
        host.resumeRendering();
        return null;
      case "stopAnimation":
        host.cancelAnimationLoad();
        host.transitionToRest(command.payload.fadeDuration);
        return null;
      case "setAnimationSpeed":
        host.setAnimationSpeed(command.payload.speed);
        return null;
      case "getPose":
        return host.getPose();
      case "setPose":
        host.setPose(command.payload.pose, command.payload.fadeDuration);
        return null;
      case "resetPose":
        host.transitionToRest(command.payload.fadeDuration);
        return null;
      case "setShadows":
        host.setShadows(command.payload.enabled);
        return null;
      case "setExpression":
        if (command.payload.layer === "mouth") {
          if (
            !host.speechTimeline.acceptInputRevision(
              requireSpeechRevision(command.payload.speechRevision),
            )
          ) {
            return null;
          }
          host.cancelSpeech();
        }
        host.setExpression(
          command.payload.expression,
          command.payload.layer,
          command.payload.weight,
          command.payload.duration,
          command.payload.disableAutoBlink,
        );
        return null;
      case "clearExpressionLayer":
        if (command.payload.layer === "mouth") {
          if (
            !host.speechTimeline.acceptInputRevision(
              requireSpeechRevision(command.payload.speechRevision),
            )
          ) {
            return null;
          }
          host.cancelSpeech();
        }
        host.clearExpressionLayer(command.payload.layer);
        return null;
      case "clearAllExpressions":
        if (
          !host.speechTimeline.acceptInputRevision(
            command.payload.speechRevision,
          )
        ) {
          return null;
        }
        host.cancelSpeech();
        host.clearAllExpressions();
        return null;
      case "setCustomBlendShape":
        host.customBlendShapes.set(
          command.payload.name,
          command.payload.weight,
        );
        return null;
      case "setLipSyncAmplitude":
        if (
          !host.speechTimeline.acceptInputRevision(
            command.payload.speechRevision,
          )
        ) {
          return null;
        }
        host.cancelSpeech();
        host.lipSyncAmplitude = command.payload.amplitude;
        return null;
      case "setViseme":
        if (
          !host.speechTimeline.acceptInputRevision(
            command.payload.speechRevision,
          )
        ) {
          return null;
        }
        host.cancelSpeech();
        host.setViseme(command.payload.viseme, command.payload.weight);
        return null;
      case "enqueueSpeechVisemes":
        host.enqueueSpeechVisemes(command.payload);
        return null;
      case "enqueueSpeechAmplitudes":
        host.enqueueSpeechAmplitudes(command.payload);
        return null;
      case "beginSpeech":
        host.beginSpeech(command.payload);
        return null;
      case "appendSpeechVisemes":
        host.appendSpeechVisemes(
          command.payload.sessionId,
          command.payload.frames,
        );
        return null;
      case "appendSpeechAmplitudes":
        host.appendSpeechAmplitudes(
          command.payload.sessionId,
          command.payload.frames,
        );
        return null;
      case "finishSpeech":
        host.finishSpeech(
          command.payload.sessionId,
          command.payload.audioDurationMs,
        );
        return null;
      case "cancelSpeech":
        if (
          host.speechTimeline.acceptInputRevision(
            command.payload.speechRevision,
          )
        ) {
          host.cancelSpeech(command.payload.sessionId);
        }
        return null;
      case "setAutoBlink":
        host.autoBlinkEnabled = command.payload.enabled;
        return null;
      case "setLookAtTarget":
        host.gazeController.setTarget(
          command.payload.x,
          command.payload.y,
          command.payload.z,
        );
        return null;
      case "setAutoSaccades":
        host.gazeController.setAutoSaccades(command.payload.enabled);
        return null;
      case "setLookAtConfig":
        if (command.payload.holdDurationSec !== undefined) {
          host.gazeController.setHoldDuration(
            command.payload.holdDurationSec,
          );
        }
        return null;
      case "setCameraMode":
        host.setCameraMode(command.payload.mode);
        return null;
      case "resetCamera":
        host.resetCamera(command.payload.durationMs);
        return null;
      case "getTransform":
        return host.getAvatarTransform();
      case "setTransform":
        host.setAvatarTransform(command.payload.transform);
        return null;
      case "setLighting":
        host.setLighting(command.payload);
        return null;
      case "setBackground":
        await host.setBackground(
          command.payload.color,
          command.payload.imageUrl,
          command.payload.transparent,
          command.payload.hostedImage,
        );
        return null;
      case "setPhysics":
        host.setPhysics(
          command.payload.stiffness,
          command.payload.gravity,
          command.payload.drag,
        );
        return null;
      case "stopWind":
        host.stopWind();
        return null;
      case "setWind":
        host.setWind(command.payload.type, command.payload.direction);
        return null;
      case "setEnvironmentColor":
        host.setEnvironmentColor(
          command.payload.color,
          command.payload.intensity,
        );
        return null;
      case "setGraphicsSettings":
        host.setGraphicsSettings(command.payload.settings);
        return null;
      case "setGraphicsPreset":
        host.setGraphicsPreset(command.payload.preset);
        return null;
      case "setAdaptiveQuality":
        host.setAdaptiveQuality(command.payload.settings);
        return null;
      case "getPerformanceSnapshot":
        return host.getPerformanceSnapshot();
      case "setRenderQuality":
        host.setRenderQuality(command.payload.pixelRatio);
        return null;
      default:
        return assertNever(command);
    }
  };
}

function requireSpeechRevision(value: number | undefined): number {
  if (value === undefined) {
    throw new TypeError("speechRevision is required for mouth expressions.");
  }
  return value;
}

function assertNever(value: never): never {
  throw new Error(`Unhandled VRM command: ${JSON.stringify(value)}.`);
}
