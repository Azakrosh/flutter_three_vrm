import { isSpeechVisemeName } from "./speech-timeline";

type RuntimeRecord = Readonly<Record<string, unknown>>;

/**
 * Validates the nested wire representation of streaming speech commands.
 *
 * Top-level required fields are checked by protocol-contract.ts. This codec
 * owns the mode-specific values, optional fields, and individual frame shape.
 */
export function findSpeechCommandPayloadError(
  action: string,
  payload: RuntimeRecord,
): string | null {
  switch (action) {
    case "enqueueSpeechVisemes": {
      const baseError = findBeginError(action, payload, "viseme");
      if (baseError !== null) return baseError;
      const framesError = findVisemeFramesError(action, payload.frames);
      if (framesError !== null) return framesError;
      return findOptionalNonNegativeNumberError(
        action,
        payload,
        "audioDurationMs",
      );
    }
    case "enqueueSpeechAmplitudes": {
      const baseError = findBeginError(action, payload, "amplitude");
      if (baseError !== null) return baseError;
      const framesError = findAmplitudeFramesError(action, payload.frames);
      if (framesError !== null) return framesError;
      return findOptionalNonNegativeNumberError(
        action,
        payload,
        "audioDurationMs",
      );
    }
    case "beginSpeech":
      return findBeginError(action, payload);
    case "appendSpeechVisemes":
      return findVisemeFramesError(action, payload.frames);
    case "appendSpeechAmplitudes":
      return findAmplitudeFramesError(action, payload.frames);
    case "finishSpeech":
      return findNonNegativeNumberError(
        action,
        "audioDurationMs",
        payload.audioDurationMs,
      );
    case "cancelSpeech":
      return findOptionalNonEmptyStringError(action, payload, "sessionId");
    default:
      return null;
  }
}

function findBeginError(
  action: string,
  payload: RuntimeRecord,
  expectedMode?: "viseme" | "amplitude",
): string | null {
  const mode = payload.mode;
  if (mode !== "viseme" && mode !== "amplitude") {
    return `Command payload ${action}.mode must be "viseme" or "amplitude".`;
  }
  if (expectedMode !== undefined && mode !== expectedMode) {
    return `Command payload ${action}.mode must be "${expectedMode}".`;
  }
  const revisionError = findNonNegativeSafeIntegerError(
    action,
    "speechRevision",
    payload.speechRevision,
  );
  if (revisionError !== null) return revisionError;
  return findFiniteNumberError(
    action,
    "timelineOriginEpochMs",
    payload.timelineOriginEpochMs,
  );
}

function findVisemeFramesError(
  action: string,
  value: unknown,
): string | null {
  if (!Array.isArray(value)) return null;
  for (let index = 0; index < value.length; index += 1) {
    const frame = value[index];
    const prefix = `Command payload ${action}.frames[${index}]`;
    if (!isRecord(frame)) return `${prefix} must be an object.`;
    if (!isSpeechVisemeName(frame.viseme)) {
      return `${prefix}.viseme must be a supported viseme.`;
    }
    const timestampError = findFrameNonNegativeNumberError(
      prefix,
      "timestampMs",
      frame.timestampMs,
    );
    if (timestampError !== null) return timestampError;
    const durationError = findFrameNonNegativeNumberError(
      prefix,
      "durationMs",
      frame.durationMs,
    );
    if (durationError !== null) return durationError;
    if (
      frame.weight !== undefined &&
      (!isFiniteNumber(frame.weight) || frame.weight < 0 || frame.weight > 1)
    ) {
      return `${prefix}.weight must be a finite number from 0 to 1.`;
    }
  }
  return null;
}

function findAmplitudeFramesError(
  action: string,
  value: unknown,
): string | null {
  if (!Array.isArray(value)) return null;
  for (let index = 0; index < value.length; index += 1) {
    const frame = value[index];
    const prefix = `Command payload ${action}.frames[${index}]`;
    if (!isRecord(frame)) return `${prefix} must be an object.`;
    if (
      !isFiniteNumber(frame.amplitude) ||
      frame.amplitude < 0 ||
      frame.amplitude > 1
    ) {
      return `${prefix}.amplitude must be a finite number from 0 to 1.`;
    }
    const timestampError = findFrameNonNegativeNumberError(
      prefix,
      "timestampMs",
      frame.timestampMs,
    );
    if (timestampError !== null) return timestampError;
    const durationError = findFrameNonNegativeNumberError(
      prefix,
      "durationMs",
      frame.durationMs,
    );
    if (durationError !== null) return durationError;
  }
  return null;
}

function findFrameNonNegativeNumberError(
  prefix: string,
  field: string,
  value: unknown,
): string | null {
  if (!isFiniteNumber(value) || value < 0) {
    return `${prefix}.${field} must be a non-negative finite number.`;
  }
  return null;
}

function findFiniteNumberError(
  action: string,
  field: string,
  value: unknown,
): string | null {
  if (!isFiniteNumber(value)) {
    return `Command payload ${action}.${field} must be a finite number.`;
  }
  return null;
}

function findNonNegativeNumberError(
  action: string,
  field: string,
  value: unknown,
): string | null {
  if (!isFiniteNumber(value) || value < 0) {
    return `Command payload ${action}.${field} must be a non-negative finite number.`;
  }
  return null;
}

function findNonNegativeSafeIntegerError(
  action: string,
  field: string,
  value: unknown,
): string | null {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    return `Command payload ${action}.${field} must be a non-negative safe integer.`;
  }
  return null;
}

function findOptionalNonNegativeNumberError(
  action: string,
  payload: RuntimeRecord,
  field: string,
): string | null {
  const value = payload[field];
  return value === undefined
    ? null
    : findNonNegativeNumberError(action, field, value);
}

function findOptionalNonEmptyStringError(
  action: string,
  payload: RuntimeRecord,
  field: string,
): string | null {
  const value = payload[field];
  if (value === undefined) return null;
  if (typeof value !== "string" || value.length === 0) {
    return `Command payload ${action}.${field} must be a non-empty string.`;
  }
  return null;
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function isRecord(value: unknown): value is RuntimeRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
