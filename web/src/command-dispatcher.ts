import type { VRM } from "@pixiv/three-vrm";
import type { Vector3 } from "three";

import type { MotionTransitionController } from "./motion-transition";
import { createNormalizedPoseClip, getNormalizedPose } from "./pose";
import type {
  RuntimeCommandPayload,
  RuntimeRecord,
} from "./protocol-contract";
import type { CommandEnvelope } from "./protocol";
import type { SpeechTimeline } from "./speech-timeline";

export type RuntimeCommandDispatcher = (
  command: CommandEnvelope,
) => Promise<unknown>;

/**
 * The narrow surface that command routing may use on the runtime facade.
 * Keeping it explicit prevents the protocol layer from depending on the full
 * renderer implementation while runner.js is migrated module by module.
 */
export interface RuntimeCommandHost {
  modelReport: unknown | null;
  currentVrm: VRM | null;
  motionTransitions: MotionTransitionController | null;
  speechTimeline: Pick<SpeechTimeline, "acceptInputRevision">;
  customBlendShapes: Map<string, number>;
  desiredLookAtPos: Pick<Vector3, "set">;
  targetSaccadeOffset: Pick<Vector3, "set">;
  poseSequence: number;
  pendingRestPoseReset: boolean;
  isAnimationPaused: boolean;
  baseBonesSaved: boolean;
  lipSyncAmplitude: number;
  autoBlinkEnabled: boolean;
  saccadeEnabled: boolean;
  lookAtTimer: number;
  lookAtHoldDurationSec: number;
  lookAtBodyDeadZoneX: number;

  loadModelFromUrl(url: string): Promise<void>;
  cancelModelLoad(): void;
  getRuntimeHealth(): unknown;
  unloadModel(): void;
  playAnimationFromUrl(url: string, options: RuntimeRecord): Promise<void>;
  cancelAnimationLoad(): void;
  pauseRendering(): void;
  resumeRendering(): void;
  transitionToRest(fadeDuration: number): void;
  resetProceduralMotion(): void;
  setShadows(enabled: boolean): void;
  setExpression(
    expression: string,
    layer: string,
    weight: number,
    duration: number,
    disableAutoBlink: boolean,
  ): void;
  clearExpressionLayer(layer: string): void;
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
    frames: readonly RuntimeRecord[],
  ): void;
  appendSpeechAmplitudes(
    sessionId: string,
    frames: readonly RuntimeRecord[],
  ): void;
  finishSpeech(sessionId: string, audioDurationMs: number): void;
  cancelSpeech(sessionId?: string): void;
  setCameraMode(mode: string): void;
  resetCamera(durationMs: number): void;
  getAvatarTransform(): unknown;
  setAvatarTransform(transform: RuntimeRecord): void;
  setLighting(config: RuntimeRecord): void;
  setBackground(
    color: string,
    imageUrl: string | null | undefined,
    transparent: boolean,
    hostedImage: boolean,
  ): Promise<void>;
  setPhysics(stiffness: number, gravity: number, drag: number): void;
  stopWind(): void;
  setWind(type: string, direction: string): void;
  setEnvironmentColor(color: string, intensity: number): void;
  setGraphicsSettings(settings: RuntimeRecord): void;
  setGraphicsPreset(preset: string): void;
  setAdaptiveQuality(settings: RuntimeRecord): void;
  getPerformanceSnapshot(): unknown;
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
        host.isAnimationPaused = true;
        host.motionTransitions?.pause();
        return null;
      case "resumeAnimation":
        host.isAnimationPaused = false;
        host.motionTransitions?.resume(command.payload.speed || 1);
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
        host.motionTransitions?.setSpeed(command.payload.speed);
        return null;
      case "getPose":
        return getNormalizedPose(host.currentVrm);
      case "setPose": {
        const vrm = host.currentVrm;
        if (host.motionTransitions === null || vrm === null) {
          throw new Error("Load a VRM model before using the Pose API.");
        }
        const clip = createNormalizedPoseClip(
          vrm,
          command.payload.pose,
          `Pose ${++host.poseSequence}`,
        );
        if (clip.tracks.length === 0) {
          host.transitionToRest(command.payload.fadeDuration);
        } else {
          host.motionTransitions.transitionTo(clip, {
            source: "pose",
            fadeDuration: command.payload.fadeDuration,
            loop: true,
            speed: 1,
          });
          host.pendingRestPoseReset = false;
          host.isAnimationPaused = false;
          host.resetProceduralMotion();
          host.motionTransitions.update(0);
        }
        host.baseBonesSaved = false;
        vrm.update(0);
        vrm.scene.updateMatrixWorld(true);
        return null;
      }
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
        host.desiredLookAtPos.set(
          -command.payload.x,
          command.payload.y,
          command.payload.z || 2.1,
        );
        host.lookAtTimer = host.lookAtHoldDurationSec;
        return null;
      case "setAutoSaccades":
        host.saccadeEnabled = command.payload.enabled;
        if (!command.payload.enabled) host.targetSaccadeOffset.set(0, 0, 0);
        return null;
      case "setLookAtConfig":
        if (command.payload.deadZoneX !== undefined) {
          host.lookAtBodyDeadZoneX = command.payload.deadZoneX;
        }
        if (command.payload.holdDurationSec !== undefined) {
          host.lookAtHoldDurationSec = command.payload.holdDurationSec;
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
