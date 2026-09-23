import type {
  RuntimeSpeechAmplitudeBatch,
  RuntimeSpeechBegin,
  RuntimeSpeechVisemeBatch,
} from "./speech-controller";
import {
  findSpeechCommandPayloadError,
} from "./speech-protocol-codec";
import type {
  SpeechAmplitudeFrame,
  SpeechVisemeFrame,
} from "./speech-timeline";
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
import {
  findPoseCameraGraphicsPayloadError,
} from "./pose-camera-graphics-codec";
import type { RuntimePose } from "./pose";
import {
  findAnimationLightingPayloadError,
} from "./animation-lighting-codec";
import type { RuntimeAnimationOptions } from "./motion-controller";
import type { RuntimeModelReport } from "./model-report";
import type { RuntimeHealth } from "./runtime-health";
import type { RuntimeLightingConfig } from "./scene-controller";

export const runtimeCommandNames = [
  "loadModelFromUrl",
  "cancelModelLoad",
  "getModelReport",
  "getRuntimeHealth",
  "unloadModel",
  "playAnimationFromUrl",
  "cancelAnimationLoad",
  "pauseAnimation",
  "resumeAnimation",
  "pauseRendering",
  "resumeRendering",
  "stopAnimation",
  "setAnimationSpeed",
  "getPose",
  "setPose",
  "resetPose",
  "setShadows",
  "setExpression",
  "clearExpressionLayer",
  "clearAllExpressions",
  "setCustomBlendShape",
  "setLipSyncAmplitude",
  "setViseme",
  "enqueueSpeechVisemes",
  "enqueueSpeechAmplitudes",
  "beginSpeech",
  "appendSpeechVisemes",
  "appendSpeechAmplitudes",
  "finishSpeech",
  "cancelSpeech",
  "setAutoBlink",
  "setLookAtTarget",
  "setAutoSaccades",
  "setLookAtConfig",
  "setCameraMode",
  "resetCamera",
  "getTransform",
  "setTransform",
  "setLighting",
  "setBackground",
  "setPhysics",
  "stopWind",
  "setWind",
  "setEnvironmentColor",
  "setGraphicsSettings",
  "setGraphicsPreset",
  "setAdaptiveQuality",
  "getPerformanceSnapshot",
  "setRenderQuality",
] as const;

export type RuntimeCommandName = (typeof runtimeCommandNames)[number];
export type RuntimeRecord = Readonly<Record<string, unknown>>;

export interface RuntimeCommandPayloadMap {
  readonly loadModelFromUrl: { readonly url: string };
  readonly cancelModelLoad: RuntimeRecord;
  readonly getModelReport: RuntimeRecord;
  readonly getRuntimeHealth: RuntimeRecord;
  readonly unloadModel: { readonly speechRevision: number };
  readonly playAnimationFromUrl: {
    readonly url: string;
    readonly options: RuntimeAnimationOptions;
  };
  readonly cancelAnimationLoad: RuntimeRecord;
  readonly pauseAnimation: RuntimeRecord;
  readonly resumeAnimation: { readonly speed: number };
  readonly pauseRendering: RuntimeRecord;
  readonly resumeRendering: RuntimeRecord;
  readonly stopAnimation: { readonly fadeDuration: number };
  readonly setAnimationSpeed: { readonly speed: number };
  readonly getPose: RuntimeRecord;
  readonly setPose: {
    readonly pose: RuntimePose;
    readonly fadeDuration: number;
  };
  readonly resetPose: { readonly fadeDuration: number };
  readonly setShadows: { readonly enabled: boolean };
  readonly setExpression: {
    readonly expression: string;
    readonly layer: string;
    readonly weight: number;
    readonly duration: number;
    readonly disableAutoBlink: boolean;
    readonly speechRevision?: number;
  };
  readonly clearExpressionLayer: {
    readonly layer: string;
    readonly speechRevision?: number;
  };
  readonly clearAllExpressions: { readonly speechRevision: number };
  readonly setCustomBlendShape: {
    readonly name: string;
    readonly weight: number;
  };
  readonly setLipSyncAmplitude: {
    readonly amplitude: number;
    readonly speechRevision: number;
  };
  readonly setViseme: {
    readonly viseme: string;
    readonly weight: number;
    readonly speechRevision: number;
  };
  readonly enqueueSpeechVisemes: RuntimeSpeechVisemeBatch & {
    readonly audioDurationMs?: number;
  };
  readonly enqueueSpeechAmplitudes: RuntimeSpeechAmplitudeBatch & {
    readonly audioDurationMs?: number;
  };
  readonly beginSpeech: RuntimeSpeechBegin;
  readonly appendSpeechVisemes: {
    readonly sessionId: string;
    readonly frames: readonly SpeechVisemeFrame[];
  };
  readonly appendSpeechAmplitudes: {
    readonly sessionId: string;
    readonly frames: readonly SpeechAmplitudeFrame[];
  };
  readonly finishSpeech: {
    readonly sessionId: string;
    readonly audioDurationMs: number;
  };
  readonly cancelSpeech: {
    readonly speechRevision: number;
    readonly sessionId?: string;
  };
  readonly setAutoBlink: { readonly enabled: boolean };
  readonly setLookAtTarget: {
    readonly x: number;
    readonly y: number;
    readonly z?: number;
  };
  readonly setAutoSaccades: { readonly enabled: boolean };
  readonly setLookAtConfig: {
    readonly holdDurationSec?: number;
  };
  readonly setCameraMode: { readonly mode: RuntimeCameraMode };
  readonly resetCamera: { readonly durationMs: number };
  readonly getTransform: RuntimeRecord;
  readonly setTransform: { readonly transform: RuntimeCameraTransform };
  readonly setLighting: RuntimeLightingConfig;
  readonly setBackground: {
    readonly color: string;
    readonly imageUrl?: string | null;
    readonly transparent: boolean;
    readonly hostedImage: boolean;
  };
  readonly setPhysics: {
    readonly stiffness: number;
    readonly gravity: number;
    readonly drag: number;
  };
  readonly stopWind: RuntimeRecord;
  readonly setWind: {
    readonly type: string;
    readonly direction: string;
  };
  readonly setEnvironmentColor: {
    readonly color: string;
    readonly intensity: number;
  };
  readonly setGraphicsSettings: { readonly settings: RuntimeGraphicsSettings };
  readonly setGraphicsPreset: { readonly preset: RuntimeGraphicsPreset };
  readonly setAdaptiveQuality: {
    readonly settings: Partial<AdaptiveQualityConfig>;
  };
  readonly getPerformanceSnapshot: RuntimeRecord;
  readonly setRenderQuality: { readonly pixelRatio: number };
}

export type RuntimeCommandPayload<
  Name extends RuntimeCommandName = RuntimeCommandName,
> = RuntimeCommandPayloadMap[Name];

export interface RuntimeTypedQueryResultMap {
  readonly getModelReport: RuntimeModelReport;
  readonly getRuntimeHealth: RuntimeHealth;
  readonly getPose: RuntimePose;
  readonly getTransform: RuntimeCameraTransform;
  readonly getPerformanceSnapshot: RuntimePerformanceSnapshot;
}

export type RuntimeTypedQueryName = keyof RuntimeTypedQueryResultMap;
export type RuntimeTypedQueryResult<Name extends RuntimeTypedQueryName> =
  RuntimeTypedQueryResultMap[Name];

export type RuntimeCommandRequest = {
  readonly [Name in RuntimeCommandName]: {
    readonly action: Name;
    readonly payload: RuntimeCommandPayload<Name>;
  };
}[RuntimeCommandName];

const runtimeCommandNameSet = new Set<string>(runtimeCommandNames);

export function isRuntimeCommandName(value: string): value is RuntimeCommandName {
  return runtimeCommandNameSet.has(value);
}

type RequiredFieldKind = "string" | "number" | "boolean" | "record" | "array";

const requiredCommandFields = {
  loadModelFromUrl: { url: "string" },
  unloadModel: { speechRevision: "number" },
  playAnimationFromUrl: { url: "string", options: "record" },
  resumeAnimation: { speed: "number" },
  stopAnimation: { fadeDuration: "number" },
  setAnimationSpeed: { speed: "number" },
  setPose: { pose: "record", fadeDuration: "number" },
  resetPose: { fadeDuration: "number" },
  setShadows: { enabled: "boolean" },
  setExpression: {
    expression: "string",
    layer: "string",
    weight: "number",
    duration: "number",
    disableAutoBlink: "boolean",
  },
  clearExpressionLayer: { layer: "string" },
  clearAllExpressions: { speechRevision: "number" },
  setCustomBlendShape: { name: "string", weight: "number" },
  setLipSyncAmplitude: { amplitude: "number", speechRevision: "number" },
  setViseme: {
    viseme: "string",
    weight: "number",
    speechRevision: "number",
  },
  enqueueSpeechVisemes: {
    sessionId: "string",
    mode: "string",
    timelineOriginEpochMs: "number",
    speechRevision: "number",
    frames: "array",
  },
  enqueueSpeechAmplitudes: {
    sessionId: "string",
    mode: "string",
    timelineOriginEpochMs: "number",
    speechRevision: "number",
    frames: "array",
  },
  beginSpeech: {
    sessionId: "string",
    mode: "string",
    timelineOriginEpochMs: "number",
    speechRevision: "number",
  },
  appendSpeechVisemes: { sessionId: "string", frames: "array" },
  appendSpeechAmplitudes: { sessionId: "string", frames: "array" },
  finishSpeech: { sessionId: "string", audioDurationMs: "number" },
  cancelSpeech: { speechRevision: "number" },
  setAutoBlink: { enabled: "boolean" },
  setLookAtTarget: { x: "number", y: "number" },
  setAutoSaccades: { enabled: "boolean" },
  setCameraMode: { mode: "string" },
  resetCamera: { durationMs: "number" },
  setTransform: { transform: "record" },
  setBackground: {
    color: "string",
    transparent: "boolean",
    hostedImage: "boolean",
  },
  setPhysics: {
    stiffness: "number",
    gravity: "number",
    drag: "number",
  },
  setWind: { type: "string", direction: "string" },
  setEnvironmentColor: { color: "string", intensity: "number" },
  setGraphicsSettings: { settings: "record" },
  setGraphicsPreset: { preset: "string" },
  setAdaptiveQuality: { settings: "record" },
  setRenderQuality: { pixelRatio: "number" },
} as const satisfies Partial<
  Record<RuntimeCommandName, Readonly<Record<string, RequiredFieldKind>>>
>;

export function findRuntimeCommandPayloadError(
  action: RuntimeCommandName,
  payload: RuntimeRecord,
): string | null {
  const fields =
    requiredCommandFields[action as keyof typeof requiredCommandFields];
  if (fields !== undefined) {
    for (const [field, kind] of Object.entries(fields)) {
      const value = payload[field];
      if (!matchesFieldKind(value, kind)) {
        const article = kind === "array" ? "an" : "a";
        return `Command payload ${action}.${field} must be ${article} ${kind}.`;
      }
    }
  }
  return findSpeechCommandPayloadError(action, payload) ??
    findPoseCameraGraphicsPayloadError(action, payload) ??
    findAnimationLightingPayloadError(action, payload);
}

function matchesFieldKind(value: unknown, kind: RequiredFieldKind): boolean {
  switch (kind) {
    case "string":
      return typeof value === "string" && value.length > 0;
    case "number":
      return typeof value === "number" && Number.isFinite(value);
    case "boolean":
      return typeof value === "boolean";
    case "record":
      return typeof value === "object" && value !== null && !Array.isArray(value);
    case "array":
      return Array.isArray(value);
  }
}

export const runtimeEventNames = [
  "onModelLoaded",
  "onModelLoadProgress",
  "onModelReport",
  "onModelUnloaded",
  "onAnimationStarted",
  "onAnimationFinished",
  "onExpressionChanged",
  "onSpeechFinished",
  "onError",
  "onStateChanged",
  "onCameraChanged",
  "onPerformance",
  "onWebGLContextChanged",
  "onTap",
] as const;

export type RuntimeEventName = (typeof runtimeEventNames)[number];
export type RuntimeEventPayload = Readonly<Record<string, unknown>>;

const runtimeEventNameSet = new Set<string>(runtimeEventNames);

export function isRuntimeEventName(value: string): value is RuntimeEventName {
  return runtimeEventNameSet.has(value);
}

const requiredEventFields = {
  onModelLoaded: { name: "string", version: "string" },
  onModelLoadProgress: {
    percent: "number",
    loaded: "number",
    total: "number",
  },
  onModelReport: {},
  onModelUnloaded: {},
  onAnimationStarted: { name: "string", playbackId: "string" },
  onAnimationFinished: { name: "string", playbackId: "string" },
  onExpressionChanged: { expression: "string", layer: "string" },
  onSpeechFinished: { sessionId: "string" },
  onError: { message: "string" },
  onStateChanged: { state: "string" },
  onCameraChanged: {
    x: "number",
    y: "number",
    zoom: "number",
    userInitiated: "boolean",
  },
  onPerformance: {},
  onWebGLContextChanged: { state: "string" },
  onTap: { x: "number", y: "number" },
} as const satisfies Record<
  RuntimeEventName,
  Readonly<Record<string, RequiredFieldKind>>
>;

export function findRuntimeEventPayloadError(
  eventName: RuntimeEventName,
  payload: RuntimeEventPayload,
): string | null {
  for (const [field, rawKind] of Object.entries(
    requiredEventFields[eventName],
  )) {
    const kind = rawKind as RequiredFieldKind;
    const value = payload[field];
    if (!matchesFieldKind(value, kind)) {
      const article = kind === "array" ? "an" : "a";
      return `Event payload ${eventName}.${field} must be ${article} ${kind}.`;
    }
  }
  return null;
}
