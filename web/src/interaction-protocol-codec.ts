type RuntimeRecord = Readonly<Record<string, unknown>>;

export const runtimeExpressionNames = [
  "happy",
  "sad",
  "angry",
  "relaxed",
  "surprised",
  "neutral",
  "blink",
  "blinkLeft",
  "blinkRight",
  "aa",
  "ih",
  "ou",
  "ee",
  "oh",
] as const;

export type RuntimeExpressionName = (typeof runtimeExpressionNames)[number];
export type RuntimeExpressionLayer = "eyes" | "mouth" | "brows";
export type RuntimeWindType = "none" | "light" | "strong" | "storm";
export type RuntimeWindDirection = "left" | "right" | "front" | "back";

export interface RuntimeExpressionConfig {
  readonly expression: RuntimeExpressionName;
  readonly layer: RuntimeExpressionLayer;
  readonly weight: number;
  readonly duration: number;
  readonly disableAutoBlink: boolean;
  readonly speechRevision?: number;
}

export interface RuntimeExpressionLayerConfig {
  readonly layer: RuntimeExpressionLayer;
  readonly speechRevision?: number;
}

export interface RuntimeCustomBlendShapeConfig {
  readonly name: string;
  readonly weight: number;
}

export interface RuntimeLookAtTarget {
  readonly x: number;
  readonly y: number;
  readonly z?: number;
}

export interface RuntimeLookAtConfig {
  readonly holdDurationSec?: number;
}

export interface RuntimePhysicsConfig {
  readonly stiffness: number;
  readonly gravity: number;
  readonly drag: number;
}

export interface RuntimeWindConfig {
  readonly type: RuntimeWindType;
  readonly direction: RuntimeWindDirection;
}

export interface RuntimeBackgroundConfig {
  readonly color: string;
  readonly imageUrl?: string | null;
  readonly transparent: boolean;
  readonly hostedImage: boolean;
}

export interface RuntimeEnvironmentColorConfig {
  readonly color: string;
  readonly intensity: number;
}

const expressionNameSet = new Set<string>(runtimeExpressionNames);
const expressionLayerSet = new Set<string>(["eyes", "mouth", "brows"]);
const windTypeSet = new Set<string>(["none", "light", "strong", "storm"]);
const windDirectionSet = new Set<string>(["left", "right", "front", "back"]);

export function findInteractionCommandPayloadError(
  action: string,
  payload: RuntimeRecord,
): string | null {
  try {
    switch (action) {
      case "setExpression":
        parseRuntimeExpressionConfig(payload);
        break;
      case "clearExpressionLayer":
        parseRuntimeExpressionLayerConfig(payload);
        break;
      case "setCustomBlendShape":
        parseRuntimeCustomBlendShapeConfig(payload);
        break;
      case "setLookAtTarget":
        parseRuntimeLookAtTarget(payload);
        break;
      case "setLookAtConfig":
        parseRuntimeLookAtConfig(payload);
        break;
      case "setPhysics":
        parseRuntimePhysicsConfig(payload);
        break;
      case "setWind":
        parseRuntimeWindConfig(payload);
        break;
      case "setBackground":
        parseRuntimeBackgroundConfig(payload);
        break;
      case "setEnvironmentColor":
        parseRuntimeEnvironmentColorConfig(payload);
        break;
    }
    return null;
  } catch (error) {
    return `Command payload ${action} is invalid: ${readErrorMessage(error)}`;
  }
}

export function parseRuntimeExpressionConfig(
  value: unknown,
): RuntimeExpressionConfig {
  const config = requireRecord(value, "Expression config");
  const expression = requireString(config.expression, "expression");
  if (!expressionNameSet.has(expression)) {
    throw new TypeError("expression must be a supported VRM expression.");
  }
  const layer = parseExpressionLayer(config.layer);
  const speechRevision = parseOptionalRevision(config.speechRevision);
  if (layer === "mouth" && speechRevision === undefined) {
    throw new TypeError("speechRevision is required for mouth expressions.");
  }
  return {
    expression: expression as RuntimeExpressionName,
    layer,
    weight: requireUnitInterval(config.weight, "weight"),
    duration: requireNonNegative(config.duration, "duration"),
    disableAutoBlink: requireBoolean(
      config.disableAutoBlink,
      "disableAutoBlink",
    ),
    ...(speechRevision === undefined ? {} : { speechRevision }),
  };
}

export function parseRuntimeExpressionLayerConfig(
  value: unknown,
): RuntimeExpressionLayerConfig {
  const config = requireRecord(value, "Expression layer config");
  const layer = parseExpressionLayer(config.layer);
  const speechRevision = parseOptionalRevision(config.speechRevision);
  if (layer === "mouth" && speechRevision === undefined) {
    throw new TypeError("speechRevision is required for the mouth layer.");
  }
  return {
    layer,
    ...(speechRevision === undefined ? {} : { speechRevision }),
  };
}

export function parseRuntimeCustomBlendShapeConfig(
  value: unknown,
): RuntimeCustomBlendShapeConfig {
  const config = requireRecord(value, "Custom blend shape config");
  return {
    name: requireString(config.name, "name"),
    weight: requireUnitInterval(config.weight, "weight"),
  };
}

export function parseRuntimeLookAtTarget(value: unknown): RuntimeLookAtTarget {
  const target = requireRecord(value, "Look-at target");
  const z = target.z === undefined ? undefined : requireFinite(target.z, "z");
  return {
    x: requireFinite(target.x, "x"),
    y: requireFinite(target.y, "y"),
    ...(z === undefined ? {} : { z }),
  };
}

export function parseRuntimeLookAtConfig(value: unknown): RuntimeLookAtConfig {
  const config = requireRecord(value, "Look-at config");
  if (config.holdDurationSec === undefined) return {};
  return {
    holdDurationSec: requireNonNegative(
      config.holdDurationSec,
      "holdDurationSec",
    ),
  };
}

export function parseRuntimePhysicsConfig(value: unknown): RuntimePhysicsConfig {
  const config = requireRecord(value, "Physics config");
  return {
    stiffness: requireNonNegative(config.stiffness, "stiffness"),
    gravity: requireNonNegative(config.gravity, "gravity"),
    drag: requireNonNegative(config.drag, "drag"),
  };
}

export function parseRuntimeWindConfig(value: unknown): RuntimeWindConfig {
  const config = requireRecord(value, "Wind config");
  const type = requireString(config.type, "type");
  const direction = requireString(config.direction, "direction");
  if (!windTypeSet.has(type)) {
    throw new TypeError('type must be "none", "light", "strong", or "storm".');
  }
  if (!windDirectionSet.has(direction)) {
    throw new TypeError(
      'direction must be "left", "right", "front", or "back".',
    );
  }
  return {
    type: type as RuntimeWindType,
    direction: direction as RuntimeWindDirection,
  };
}

export function parseRuntimeBackgroundConfig(
  value: unknown,
): RuntimeBackgroundConfig {
  const config = requireRecord(value, "Background config");
  const imageUrl = config.imageUrl === undefined || config.imageUrl === null
    ? config.imageUrl
    : requireString(config.imageUrl, "imageUrl");
  const hostedImage = requireBoolean(config.hostedImage, "hostedImage");
  if (hostedImage && imageUrl == null) {
    throw new TypeError("imageUrl is required when hostedImage is true.");
  }
  return {
    color: requireString(config.color, "color"),
    ...(imageUrl === undefined ? {} : { imageUrl }),
    transparent: requireBoolean(config.transparent, "transparent"),
    hostedImage,
  };
}

export function parseRuntimeEnvironmentColorConfig(
  value: unknown,
): RuntimeEnvironmentColorConfig {
  const config = requireRecord(value, "Environment color config");
  return {
    color: requireString(config.color, "color"),
    intensity: requireUnitInterval(config.intensity, "intensity"),
  };
}

function parseExpressionLayer(value: unknown): RuntimeExpressionLayer {
  const layer = requireString(value, "layer");
  if (!expressionLayerSet.has(layer)) {
    throw new TypeError('layer must be "eyes", "mouth", or "brows".');
  }
  return layer as RuntimeExpressionLayer;
}

function parseOptionalRevision(value: unknown): number | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw new TypeError("speechRevision must be a non-negative safe integer.");
  }
  return value;
}

function requireRecord(value: unknown, name: string): RuntimeRecord {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TypeError(`${name} must be an object.`);
  }
  return value as RuntimeRecord;
}

function requireString(value: unknown, name: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`${name} must be a non-empty string.`);
  }
  return value;
}

function requireBoolean(value: unknown, name: string): boolean {
  if (typeof value !== "boolean") {
    throw new TypeError(`${name} must be a boolean.`);
  }
  return value;
}

function requireFinite(value: unknown, name: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new TypeError(`${name} must be a finite number.`);
  }
  return value;
}

function requireNonNegative(value: unknown, name: string): number {
  const number = requireFinite(value, name);
  if (number < 0) {
    throw new TypeError(`${name} must be a non-negative finite number.`);
  }
  return number;
}

function requireUnitInterval(value: unknown, name: string): number {
  const number = requireFinite(value, name);
  if (number < 0 || number > 1) {
    throw new TypeError(`${name} must be between 0 and 1.`);
  }
  return number;
}

function readErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
