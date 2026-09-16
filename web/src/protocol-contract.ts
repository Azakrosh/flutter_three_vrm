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
export type RuntimeCommandPayload = Readonly<Record<string, unknown>>;

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
  payload: RuntimeCommandPayload,
): string | null {
  const fields =
    requiredCommandFields[action as keyof typeof requiredCommandFields];
  if (fields === undefined) return null;

  for (const [field, kind] of Object.entries(fields)) {
    const value = payload[field];
    if (!matchesFieldKind(value, kind)) {
      const article = kind === "array" ? "an" : "a";
      return `Command payload ${action}.${field} must be ${article} ${kind}.`;
    }
  }
  return null;
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
