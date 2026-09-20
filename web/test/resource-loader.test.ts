import { describe, expect, it, vi } from "vitest";

import {
  createRuntimeCanceledError,
  fetchRuntimeResource,
  isRuntimeCanceledError,
} from "../src/resource-loader";

describe("runtime resource loader", () => {
  it("streams a resource and reports byte progress", async () => {
    const progress = vi.fn();
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new Uint8Array([1, 2]));
        controller.enqueue(new Uint8Array([3, 4]));
        controller.close();
      },
    });
    const fetcher = vi.fn(async () =>
      new Response(stream, {
        headers: {
          "content-length": "4",
          "content-type": "model/gltf-binary",
        },
      }),
    ) as unknown as typeof fetch;

    const result = await fetchRuntimeResource(
      "https://example.test/avatar.vrm",
      new AbortController().signal,
      progress,
      fetcher,
    );

    expect([...new Uint8Array(result.data)]).toEqual([1, 2, 3, 4]);
    expect(result).toMatchObject({
      byteLength: 4,
      contentType: "model/gltf-binary",
    });
    expect(progress.mock.calls).toEqual([
      [2, 4],
      [4, 4],
    ]);
    expect(fetcher).toHaveBeenCalledWith(
      "https://example.test/avatar.vrm",
      expect.objectContaining({ credentials: "omit" }),
    );
  });

  it("rejects unsuccessful HTTP responses", async () => {
    const fetcher = vi.fn(async () => new Response(null, { status: 503 })) as
      unknown as typeof fetch;

    await expect(
      fetchRuntimeResource(
        "https://example.test/avatar.vrm",
        new AbortController().signal,
        undefined,
        fetcher,
      ),
    ).rejects.toThrow("Resource request failed with HTTP 503.");
  });

  it("creates stable cancellation errors", () => {
    const error = createRuntimeCanceledError("Loading was canceled.");

    expect(error).toMatchObject({
      name: "Error",
      message: "Loading was canceled.",
      code: "canceled",
    });
    expect(isRuntimeCanceledError(error)).toBe(true);
    expect(
      isRuntimeCanceledError(new DOMException("Aborted", "AbortError")),
    ).toBe(true);
    expect(isRuntimeCanceledError(new Error("Network failed"))).toBe(false);
  });
});
