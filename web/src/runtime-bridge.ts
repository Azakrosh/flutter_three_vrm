import {
  event,
  failure,
  parseCommand,
  success,
  type ResponseEnvelope,
} from "./protocol";
import type {
  RuntimeCommandName,
  RuntimeCommandPayload,
  RuntimeEventName,
} from "./protocol-contract";

export type RuntimeCommandExecutor = (
  action: RuntimeCommandName,
  payload: RuntimeCommandPayload,
) => unknown | Promise<unknown>;

export interface RuntimeBridgeOptions {
  readonly executeCommand: RuntimeCommandExecutor;
  readonly dispose: () => void;
  readonly isDisposed: () => boolean;
}

declare global {
  interface Window {
    FlutterBridge?: {
      postMessage(message: string): void;
    };
    chrome?: {
      webview?: {
        postMessage(message: string): void;
      };
    };
    flutterVrmDispatch?: (commandJson: string) => Promise<void>;
    flutterVrmDispose?: () => void;
  }
}

export async function createRuntimeCommandResponse(
  commandJson: string,
  executeCommand: RuntimeCommandExecutor,
): Promise<ResponseEnvelope> {
  let id = "invalid-command";
  try {
    const command = parseCommand(commandJson);
    id = command.id;
    const result = await executeCommand(command.action, command.payload);
    return success(id, result ?? null);
  } catch (error) {
    return failure(id, readErrorCode(error), readErrorMessage(error));
  }
}

export function installRuntimeBridge(options: RuntimeBridgeOptions): () => void {
  const dispatch = async (commandJson: string): Promise<void> => {
    const response = await createRuntimeCommandResponse(
      commandJson,
      options.executeCommand,
    );
    if (!options.isDisposed()) postFlutterMessage(response);
  };
  const dispose = (): void => options.dispose();

  window.flutterVrmDispatch = dispatch;
  window.flutterVrmDispose = dispose;

  return () => {
    if (window.flutterVrmDispatch === dispatch) {
      delete window.flutterVrmDispatch;
    }
    if (window.flutterVrmDispose === dispose) {
      delete window.flutterVrmDispose;
    }
  };
}

export function postRuntimeEvent(
  eventName: RuntimeEventName,
  payload: Readonly<Record<string, unknown>>,
): void {
  postFlutterMessage(event(eventName, payload));
}

function postFlutterMessage(value: unknown): void {
  const message = typeof value === "string" ? value : JSON.stringify(value);
  if (window.FlutterBridge !== undefined) {
    window.FlutterBridge.postMessage(message);
  } else if (window.chrome?.webview !== undefined) {
    window.chrome.webview.postMessage(message);
  } else {
    window.parent.postMessage(message, "*");
  }
}

function readErrorCode(error: unknown): string {
  if (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    typeof error.code === "string"
  ) {
    return error.code;
  }
  return "runtimeError";
}

function readErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
