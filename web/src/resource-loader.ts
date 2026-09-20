export interface RuntimeResource {
  readonly data: ArrayBuffer;
  readonly byteLength: number;
  readonly contentType: string;
}

export type RuntimeResourceProgress = (
  loadedBytes: number,
  totalBytes: number,
) => void;

export interface RuntimeCanceledError extends Error {
  readonly code: "canceled";
}

export function createRuntimeCanceledError(
  message: string,
): RuntimeCanceledError {
  return Object.assign(new Error(message), { code: "canceled" as const });
}

export async function fetchRuntimeResource(
  url: string,
  signal: AbortSignal,
  onProgress?: RuntimeResourceProgress,
  fetcher: typeof fetch = fetch,
): Promise<RuntimeResource> {
  const response = await fetcher(url, {
    signal,
    credentials: "omit",
  });
  if (!response.ok) {
    throw new Error(`Resource request failed with HTTP ${response.status}.`);
  }

  const contentType = response.headers.get("content-type") ?? "";
  const declaredLength = readContentLength(response.headers);
  if (response.body === null) {
    const data = await response.arrayBuffer();
    onProgress?.(data.byteLength, data.byteLength);
    return { data, byteLength: data.byteLength, contentType };
  }

  const reader = response.body.getReader();
  let capacity = declaredLength > 0 ? declaredLength : 1024 * 1024;
  let bytes = new Uint8Array(capacity);
  let loaded = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    if (loaded + value.length > capacity) {
      capacity = Math.max(capacity * 2, loaded + value.length);
      const expanded = new Uint8Array(capacity);
      expanded.set(bytes.subarray(0, loaded));
      bytes = expanded;
    }
    bytes.set(value, loaded);
    loaded += value.length;
    onProgress?.(loaded, declaredLength);
  }

  const data = new Uint8Array(loaded);
  data.set(bytes.subarray(0, loaded));
  return { data: data.buffer, byteLength: loaded, contentType };
}

function readContentLength(headers: Headers): number {
  const value = Number(headers.get("content-length") ?? 0);
  return Number.isSafeInteger(value) && value > 0 ? value : 0;
}
