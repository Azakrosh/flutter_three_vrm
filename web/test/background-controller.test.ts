import { describe, expect, it, vi } from "vitest";

import {
  RuntimeBackgroundController,
  type RuntimeBackgroundStyle,
} from "../src/background-controller";
import type { RuntimeResource } from "../src/resource-loader";

describe("runtime background controller", () => {
  it("preserves direct image, transparent, and solid-color presentation", async () => {
    const harness = createHarness();
    await harness.controller.setBackground(
      "#123456",
      "https://example.test/image(1).png",
      false,
    );
    expect(harness.style.backgroundColor).toBe("#123456");
    expect(harness.style.backgroundImage).toBe(
      'url("https://example.test/image(1).png")',
    );
    expect(harness.style.backgroundSize).toBe("cover");
    expect(harness.style.backgroundPosition).toBe("center");
    expect(harness.setCanvasBackground).toHaveBeenCalledWith(null, true);
    expect(harness.fetchResource).not.toHaveBeenCalled();

    await harness.controller.setBackground("#abcdef", null, true);
    expect(harness.style.backgroundImage).toBe("none");
    expect(harness.style.backgroundColor).toBe("transparent");
    expect(harness.setCanvasBackground).toHaveBeenLastCalledWith(null, true);

    await harness.controller.setBackground("#fedcba", null, false);
    expect(harness.style.backgroundColor).toBe("#fedcba");
    expect(harness.setCanvasBackground).toHaveBeenLastCalledWith(
      "#fedcba",
      false,
    );
  });

  it("copies hosted bytes into a Blob and revokes replaced URLs exactly once", async () => {
    const harness = createHarness();
    harness.createObjectUrl
      .mockReturnValueOnce("blob:first")
      .mockReturnValueOnce("blob:second");

    await harness.controller.setBackground(
      "#111111",
      "http://127.0.0.1/first",
      false,
      true,
    );
    expect(harness.style.backgroundImage).toBe('url("blob:first")');
    expect(harness.fetchResource).toHaveBeenCalledOnce();
    const firstBlob = harness.createObjectUrl.mock.calls[0]?.[0];
    expect(firstBlob).toBeInstanceOf(Blob);
    expect(Array.from(new Uint8Array(await firstBlob!.arrayBuffer()))).toEqual(
      [1, 2, 3],
    );
    expect(firstBlob?.type).toBe("image/png");

    await harness.controller.setBackground(
      "#222222",
      "http://127.0.0.1/second",
      false,
      true,
    );
    expect(harness.revokeObjectUrl).toHaveBeenCalledExactlyOnceWith(
      "blob:first",
    );
    expect(harness.style.backgroundImage).toBe('url("blob:second")');

    await harness.controller.setBackground("#333333", null, false);
    expect(harness.revokeObjectUrl).toHaveBeenCalledWith("blob:second");
    harness.controller.dispose();
    expect(harness.revokeObjectUrl).toHaveBeenCalledTimes(2);
  });

  it("ignores stale fetch completion and keeps the newest hosted background", async () => {
    const first = deferred<RuntimeResource>();
    const harness = createHarness({
      fetchResource: (url) => url.endsWith("/old")
        ? first.promise
        : Promise.resolve(resource()),
    });
    harness.createObjectUrl.mockReturnValue("blob:new");
    const oldRequest = harness.controller.setBackground(
      "#111111",
      "http://127.0.0.1/old",
      false,
      true,
    );
    await harness.controller.setBackground(
      "#222222",
      "http://127.0.0.1/new",
      false,
      true,
    );
    first.resolve(resource());

    await expect(oldRequest).rejects.toMatchObject({ code: "canceled" });
    expect(harness.createObjectUrl).toHaveBeenCalledOnce();
    expect(harness.style.backgroundImage).toBe('url("blob:new")');
    harness.controller.dispose();
    expect(harness.revokeObjectUrl).toHaveBeenCalledExactlyOnceWith(
      "blob:new",
    );
  });

  it("revokes a newly created URL if cancellation wins before presentation", async () => {
    const harness = createHarness();
    harness.createObjectUrl.mockImplementation(() => {
      harness.controller.cancelLoad();
      return "blob:stale";
    });

    await expect(harness.controller.setBackground(
      "#111111",
      "http://127.0.0.1/stale",
      false,
      true,
    )).rejects.toMatchObject({ code: "canceled" });
    expect(harness.revokeObjectUrl).toHaveBeenCalledExactlyOnceWith(
      "blob:stale",
    );
    expect(harness.style.backgroundImage).toBe("none");
  });

  it("keeps the previous image on fetch failure and cleans up on dispose", async () => {
    const harness = createHarness({
      fetchResource: async () => { throw new Error("HTTP 500"); },
    });
    await harness.controller.setBackground(
      "#111111",
      "https://example.test/previous.png",
      false,
    );
    await expect(harness.controller.setBackground(
      "#222222",
      "http://127.0.0.1/failure",
      false,
      true,
    )).rejects.toThrow("HTTP 500");
    expect(harness.style.backgroundImage).toBe(
      'url("https://example.test/previous.png")',
    );
    harness.controller.dispose();
    harness.controller.dispose();
    expect(harness.style.backgroundImage).toBe("none");
    await expect(harness.controller.setBackground(
      "#333333",
      null,
      false,
    )).rejects.toMatchObject({ code: "canceled" });
  });
});

function createHarness(
  overrides: {
    fetchResource?: (
      url: string,
      signal: AbortSignal,
    ) => Promise<RuntimeResource>;
  } = {},
) {
  const style: RuntimeBackgroundStyle = {
    backgroundColor: "",
    backgroundImage: "none",
    backgroundSize: "",
    backgroundPosition: "",
  };
  const setCanvasBackground = vi.fn();
  const fetchResource = vi.fn(overrides.fetchResource ?? (async () => resource()));
  const createObjectUrl = vi.fn((_blob: Blob) => "blob:test");
  const revokeObjectUrl = vi.fn();
  const controller = new RuntimeBackgroundController({
    style,
    setCanvasBackground,
    fetchResource,
    createObjectUrl,
    revokeObjectUrl,
  });
  return {
    controller,
    style,
    setCanvasBackground,
    fetchResource,
    createObjectUrl,
    revokeObjectUrl,
  };
}

function resource(): RuntimeResource {
  const data = new Uint8Array([1, 2, 3]).buffer;
  return { data, byteLength: data.byteLength, contentType: "image/png" };
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((complete) => { resolve = complete; });
  return { promise, resolve };
}
