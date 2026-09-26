import { runtimeExpressionNames } from "./interaction-protocol-codec";
import type {
  RuntimeEventName,
  RuntimeRecord,
} from "./protocol-contract";

const expressionNames = new Set<string>(runtimeExpressionNames);
const expressionLayers = new Set<string>(["eyes", "mouth", "brows"]);
const nonNegativeIntegerModelReportFields = [
  "sourceBytes",
  "meshes",
  "skinnedMeshes",
  "geometries",
  "materials",
  "textures",
  "texturePixels",
  "estimatedTextureMemoryBytes",
  "maxTextureWidth",
  "maxTextureHeight",
  "vertices",
  "triangles",
  "morphTargets",
  "humanoidBones",
  "springBoneJoints",
] as const;
const nonNegativeIntegerPerformanceFields = [
  "frameSampleCount",
  "longFrameCount",
  "adaptiveTargetFps",
  "adaptiveSlowWindowCount",
  "adaptiveFastWindowCount",
  "drawCalls",
  "triangles",
  "geometries",
  "textures",
] as const;

export function findRuntimeEventDomainError(
  eventName: RuntimeEventName,
  payload: RuntimeRecord,
): string | null {
  try {
    validateRuntimeEventDomain(eventName, payload);
    return null;
  } catch (error) {
    return `Event payload ${eventName} is invalid: ${readErrorMessage(error)}`;
  }
}

function validateRuntimeEventDomain(
  eventName: RuntimeEventName,
  payload: RuntimeRecord,
): void {
  switch (eventName) {
    case "onModelLoaded":
    case "onAnimationStarted":
    case "onAnimationFinished":
    case "onSpeechFinished":
    case "onError":
      return;
    case "onModelLoadProgress": {
      const percent = requireNonNegativeSafeInteger(payload.percent, "percent");
      const loaded = requireNonNegativeSafeInteger(payload.loaded, "loaded");
      const total = requireNonNegativeSafeInteger(payload.total, "total");
      if (percent > 100) {
        throw new TypeError("percent must not exceed 100.");
      }
      if (total > 0 && loaded > total) {
        throw new TypeError("loaded must not exceed total.");
      }
      return;
    }
    case "onModelReport":
      if (!isPositiveFinite(payload.height)) {
        throw new TypeError("height must be a positive finite number.");
      }
      for (const field of nonNegativeIntegerModelReportFields) {
        requireNonNegativeSafeInteger(payload[field], field);
      }
      return;
    case "onModelUnloaded":
      if (Object.keys(payload).length !== 0) {
        throw new TypeError("payload must be empty.");
      }
      return;
    case "onExpressionChanged":
      if (!expressionNames.has(String(payload.expression))) {
        throw new TypeError("expression must be a supported VRM expression.");
      }
      if (!expressionLayers.has(String(payload.layer))) {
        throw new TypeError('layer must be "eyes", "mouth", or "brows".');
      }
      return;
    case "onStateChanged":
      if (payload.state !== "initialized") {
        throw new TypeError('state must be "initialized".');
      }
      return;
    case "onCameraChanged":
      if (!isPositiveFinite(payload.zoom)) {
        throw new TypeError("zoom must be a positive finite number.");
      }
      return;
    case "onPerformance":
      for (const field of [
        "fps",
        "frameTimeMs",
        "frameTimeP50Ms",
        "frameTimeP95Ms",
        "longestFrameMs",
        "longFrameThresholdMs",
        "updateTimeP95Ms",
        "renderTimeP95Ms",
        "adaptiveCooldownRemainingMs",
        "fpsCap",
      ] as const) {
        if (!isNonNegativeFinite(payload[field])) {
          throw new TypeError(`${field} must be a non-negative finite number.`);
        }
      }
      if (!isPositiveFinite(payload.pixelRatio)) {
        throw new TypeError("pixelRatio must be a positive finite number.");
      }
      if (
        Number(payload.frameTimeP50Ms) > Number(payload.frameTimeP95Ms)
      ) {
        throw new TypeError("frameTimeP50Ms must not exceed frameTimeP95Ms.");
      }
      for (const field of nonNegativeIntegerPerformanceFields) {
        requireNonNegativeSafeInteger(payload[field], field);
      }
      if (Number(payload.longFrameCount) > Number(payload.frameSampleCount)) {
        throw new TypeError("longFrameCount must not exceed frameSampleCount.");
      }
      if (!["none", "runtimeUpdate", "renderSubmission", "externalScheduling"]
        .includes(String(payload.longFrameSource))) {
        throw new TypeError("longFrameSource must be a supported source.");
      }
      if (![
        "disabled",
        "stable",
        "collectingSlow",
        "collectingFast",
        "cooldown",
        "atMinimum",
        "atMaximum",
        "decrease",
        "increase",
      ].includes(String(payload.adaptiveDecision))) {
        throw new TypeError("adaptiveDecision must be a supported decision.");
      }
      if (![
        "initialized",
        "configurationChanged",
        "sample",
        "performanceDown",
        "performanceUp",
      ].includes(String(payload.reason))) {
        throw new TypeError("reason must be a supported performance reason.");
      }
      return;
    case "onWebGLContextChanged":
      if (payload.state !== "lost" && payload.state !== "restored") {
        throw new TypeError('state must be "lost" or "restored".');
      }
      return;
    case "onTap":
      return;
  }
}

function requireNonNegativeSafeInteger(value: unknown, name: string): number {
  if (
    typeof value !== "number" ||
    !Number.isSafeInteger(value) ||
    value < 0
  ) {
    throw new TypeError(`${name} must be a non-negative safe integer.`);
  }
  return value;
}

function isNonNegativeFinite(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}

function isPositiveFinite(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value > 0;
}

function readErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
