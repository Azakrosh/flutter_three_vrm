import { describe, expect, it } from "vitest";

import { RuntimeDiagnostics } from "../src/runtime-diagnostics";

describe("runtime diagnostics", () => {
  it("counts context losses for the lifetime of one runtime", () => {
    const diagnostics = new RuntimeDiagnostics();

    diagnostics.recordContextLoss();
    diagnostics.recordContextLoss();

    expect(diagnostics.contextLossCount).toBe(2);
  });

  it("retains the duration of the last successful model load", () => {
    const diagnostics = new RuntimeDiagnostics();

    diagnostics.recordSuccessfulModelLoad(100, 350.5);
    expect(diagnostics.lastModelLoadDurationMs).toBe(250.5);

    diagnostics.recordSuccessfulModelLoad(500, 490);
    expect(diagnostics.lastModelLoadDurationMs).toBe(0);
  });

  it("ignores invalid clock samples", () => {
    const diagnostics = new RuntimeDiagnostics();
    diagnostics.recordSuccessfulModelLoad(10, 20);

    diagnostics.recordSuccessfulModelLoad(Number.NaN, 30);
    diagnostics.recordSuccessfulModelLoad(30, Number.POSITIVE_INFINITY);

    expect(diagnostics.lastModelLoadDurationMs).toBe(10);
  });
});
