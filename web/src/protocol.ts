import {
  findRuntimeEventPayloadError,
  findRuntimeCommandPayloadError,
  isRuntimeCommandName,
  type RuntimeCommandName,
  type RuntimeCommandRequest,
  type RuntimeCommandResult,
  type RuntimeEventName,
  type RuntimeEventPayload,
} from "./protocol-contract";

export const protocolVersion = 3 as const;

interface CommandEnvelopeBase {
  readonly version: typeof protocolVersion;
  readonly id: string;
  readonly type: "command";
}

export type CommandEnvelope<
  Name extends RuntimeCommandName = RuntimeCommandName,
> = CommandEnvelopeBase & RuntimeCommandRequest<Name>;

export interface SuccessEnvelope<Result = RuntimeCommandResult> {
  readonly version: typeof protocolVersion;
  readonly id: string;
  readonly type: "response";
  readonly ok: true;
  readonly result: Result;
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

export interface EventEnvelope<
  Name extends RuntimeEventName = RuntimeEventName,
> {
  readonly version: typeof protocolVersion;
  readonly type: "event";
  readonly event: Name;
  readonly payload: RuntimeEventPayload<Name>;
}

export type ResponseEnvelope<Result = RuntimeCommandResult> =
  SuccessEnvelope<Result> | FailureEnvelope;
export type OutgoingEnvelope = ResponseEnvelope | EventEnvelope;

export type RuntimeCommandResponse<Name extends RuntimeCommandName> =
  ResponseEnvelope<RuntimeCommandResult<Name>>;

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
  if (!isRuntimeCommandName(decoded.action)) {
    throw new ProtocolError(
      "unknownAction",
      `Unknown VRM command: ${decoded.action}.`,
    );
  }
  if (!isRecord(decoded.payload)) {
    throw new ProtocolError(
      "invalidPayload",
      "Command payload must be an object.",
    );
  }
  const payloadError = findRuntimeCommandPayloadError(
    decoded.action,
    decoded.payload,
  );
  if (payloadError !== null) {
    throw new ProtocolError("invalidPayload", payloadError);
  }

  return {
    version: protocolVersion,
    id: decoded.id,
    type: "command",
    action: decoded.action,
    payload: decoded.payload,
  } as CommandEnvelope;
}

export function success<Result>(
  id: string,
  result: Result,
): SuccessEnvelope<Result> {
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

export function event<Name extends RuntimeEventName>(
  eventName: Name,
  payload: RuntimeEventPayload<Name>,
): EventEnvelope<Name> {
  if (!isRecord(payload)) {
    throw new ProtocolError(
      "invalidEventPayload",
      "Event payload must be an object.",
    );
  }
  const payloadError = findRuntimeEventPayloadError(eventName, payload);
  if (payloadError !== null) {
    throw new ProtocolError("invalidEventPayload", payloadError);
  }
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
