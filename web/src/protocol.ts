export const protocolVersion = 3 as const;

export interface CommandEnvelope {
  readonly version: typeof protocolVersion;
  readonly id: string;
  readonly type: "command";
  readonly action: string;
  readonly payload: unknown;
}

export interface SuccessEnvelope {
  readonly version: typeof protocolVersion;
  readonly id: string;
  readonly type: "response";
  readonly ok: true;
  readonly result: unknown;
}

export interface FailureEnvelope {
  readonly version: typeof protocolVersion;
  readonly id: string;
  readonly type: "response";
  readonly ok: false;
  readonly error: {
    readonly code: string;
    readonly message: string;
    readonly details?: unknown;
  };
}

export interface EventEnvelope {
  readonly version: typeof protocolVersion;
  readonly type: "event";
  readonly event: string;
  readonly payload: unknown;
}

export type ResponseEnvelope = SuccessEnvelope | FailureEnvelope;
export type OutgoingEnvelope = ResponseEnvelope | EventEnvelope;

export function parseCommand(value: string): CommandEnvelope {
  const decoded: unknown = JSON.parse(value);
  if (!isRecord(decoded)) {
    throw new ProtocolError("invalidEnvelope", "Protocol message must be an object.");
  }
  if (decoded.version !== protocolVersion) {
    throw new ProtocolError(
      "unsupportedVersion",
      `Unsupported protocol version: ${String(decoded.version)}.`,
    );
  }
  if (decoded.type !== "command") {
    throw new ProtocolError("invalidType", "Expected a command envelope.");
  }
  if (typeof decoded.id !== "string" || decoded.id.length === 0) {
    throw new ProtocolError("invalidId", "Command id must be a non-empty string.");
  }
  if (typeof decoded.action !== "string" || decoded.action.length === 0) {
    throw new ProtocolError(
      "invalidAction",
      "Command action must be a non-empty string.",
    );
  }

  return {
    version: protocolVersion,
    id: decoded.id,
    type: "command",
    action: decoded.action,
    payload: decoded.payload,
  };
}

export function success(id: string, result: unknown = null): SuccessEnvelope {
  return { version: protocolVersion, id, type: "response", ok: true, result };
}

export function failure(
  id: string,
  code: string,
  message: string,
  details?: unknown,
): FailureEnvelope {
  return {
    version: protocolVersion,
    id,
    type: "response",
    ok: false,
    error: { code, message, ...(details === undefined ? {} : { details }) },
  };
}

export function event(eventName: string, payload: unknown = null): EventEnvelope {
  return {
    version: protocolVersion,
    type: "event",
    event: eventName,
    payload,
  };
}

export class ProtocolError extends Error {
  public constructor(
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "ProtocolError";
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
