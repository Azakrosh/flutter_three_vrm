import {
  Mesh,
  MeshBasicMaterial,
  Object3D,
  type PerspectiveCamera,
  type WebGLRenderer,
  type WebGLRendererParameters,
} from "three";
import type { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { describe, expect, it, vi } from "vitest";

import { RuntimeSceneController } from "../src/scene-controller";

describe("runtime scene controller", () => {
  it("creates the scene, camera, lights, renderer, and controls", () => {
    const harness = createHarness();
    const onControlsStart = vi.fn();
    const onControlsEnd = vi.fn();
    const lookAtTarget = new Object3D();
    const controller = harness.createController({
      lookAtTarget,
      onControlsStart,
      onControlsEnd,
    });

    expect(controller.scene.children).toContain(lookAtTarget);
    expect(lookAtTarget.position.toArray()).toEqual([0, 1.4, 2.1]);
    expect(controller.camera.aspect).toBeCloseTo(16 / 9);
    expect(controller.camera.position.toArray()).toEqual([0, 1.05, 1.9]);
    expect(controller.ambientLight.intensity).toBe(1.2);
    expect(controller.directionalLight.intensity).toBe(1);
    expect(controller.rimLight.intensity).toBe(0.6);
    expect(harness.rendererParameters[0]).toMatchObject({
      alpha: true,
      antialias: true,
      premultipliedAlpha: false,
      preserveDrawingBuffer: false,
    });
    expect(harness.renderers[0]!.setSize).toHaveBeenCalledWith(1600, 900);
    expect(harness.renderers[0]!.pixelRatio).toBe(1.5);
    expect(harness.containerChildren).toEqual([
      harness.renderers[0]!.canvas,
    ]);

    harness.controls[0]!.dispatch("start");
    harness.controls[0]!.dispatch("end");
    expect(onControlsStart).toHaveBeenCalledOnce();
    expect(onControlsEnd).toHaveBeenCalledOnce();
  });

  it("owns lighting, shadows, canvas background, and resize", () => {
    const harness = createHarness();
    const controller = harness.createController();
    const material = new MeshBasicMaterial();
    const mesh = new Mesh(undefined, material);
    controller.scene.add(mesh);
    const initialMaterialVersion = material.version;

    controller.setLighting({
      ambientIntensity: 0.8,
      ambientColor: "#123456",
      directionalIntensity: 1.7,
      directionalColor: "#fedcba",
    });
    expect(() =>
      controller.setLighting({ ambientIntensity: -1 })
    ).toThrow("ambientIntensity");
    expect(() =>
      controller.setLighting({ directionalColor: "" })
    ).toThrow("directionalColor");
    controller.setEnvironmentColor("#ff0000", 0.5);
    expect(controller.ambientLight.intensity).toBe(0.8);
    expect(controller.directionalLight.intensity).toBe(1.7);
    expect(controller.directionalLight.color.getHexString()).toBe("fedcba");
    expect(controller.rimLight.color.getHexString()).toBe("ff0000");

    expect(controller.setShadows(true)).toBe(true);
    expect(controller.setShadows(true)).toBe(false);
    expect(controller.renderer.shadowMap.enabled).toBe(true);
    expect(controller.directionalLight.castShadow).toBe(true);
    expect(mesh.castShadow).toBe(true);
    expect(mesh.receiveShadow).toBe(true);
    expect(material.version).toBeGreaterThan(initialMaterialVersion);
    expect(harness.renderers[0]!.clear).not.toHaveBeenCalled();

    controller.setCanvasBackground("#224466", false);
    expect(controller.scene.background).not.toBeNull();
    expect(harness.renderers[0]!.setClearColor).toHaveBeenLastCalledWith(
      "#224466",
      1,
    );
    controller.setCanvasBackground(null, true);
    expect(controller.scene.background).toBeNull();
    expect(harness.renderers[0]!.setClearColor).toHaveBeenLastCalledWith(
      0x000000,
      0,
    );

    controller.resize(400, 0);
    expect(controller.camera.aspect).toBe(1);
    expect(harness.renderers[0]!.setSize).toHaveBeenLastCalledWith(400, 0);
  });

  it("tracks WebGL context state and recompiles materials after restore", () => {
    const harness = createHarness();
    const onContextLost = vi.fn();
    const onContextRestored = vi.fn();
    const controller = harness.createController({
      onContextLost,
      onContextRestored,
    });
    const material = new MeshBasicMaterial();
    controller.scene.add(new Mesh(undefined, material));
    const initialMaterialVersion = material.version;

    const lostEvent = new Event("webglcontextlost", { cancelable: true });
    harness.renderers[0]!.canvas.dispatchEvent(lostEvent);
    expect(lostEvent.defaultPrevented).toBe(true);
    expect(controller.contextLost).toBe(true);
    expect(onContextLost).toHaveBeenCalledOnce();

    harness.renderers[0]!.canvas.dispatchEvent(
      new Event("webglcontextrestored"),
    );
    expect(controller.contextLost).toBe(false);
    expect(material.version).toBeGreaterThan(initialMaterialVersion);
    expect(onContextRestored).toHaveBeenCalledOnce();
  });

  it("recreates renderer and controls while preserving applied state", () => {
    const harness = createHarness();
    const controller = harness.createController();
    const firstRenderer = harness.renderers[0]!;
    const firstControls = harness.controls[0]!;
    firstControls.target.set(0.2, 1.1, -0.3);
    controller.setPixelRatio(1.25);
    controller.setShadows(true);

    expect(controller.recreateRenderer(false)).toBe(true);
    const secondRenderer = harness.renderers[1]!;
    const secondControls = harness.controls[1]!;
    expect(controller.antialias).toBe(false);
    expect(controller.renderer).toBe(secondRenderer.renderer);
    expect(controller.controls).toBe(secondControls.controls);
    expect(secondRenderer.pixelRatio).toBe(1.25);
    expect(secondRenderer.renderer.shadowMap.enabled).toBe(true);
    expect(secondControls.target.toArray()).toEqual([0.2, 1.1, -0.3]);
    expect(firstControls.dispose).toHaveBeenCalledOnce();
    expect(firstRenderer.dispose).toHaveBeenCalledOnce();
    expect(firstRenderer.forceContextLoss).toHaveBeenCalledOnce();
    expect(harness.containerChildren).toEqual([secondRenderer.canvas]);
    expect(secondRenderer.render).toHaveBeenCalledOnce();
    expect(secondRenderer.render).toHaveBeenCalledWith(
      controller.scene,
      controller.camera,
    );
    expect(controller.recreateRenderer(false)).toBe(false);

    secondRenderer.render.mockClear();
    const prepareCamera = vi.fn();
    controller.updateAndRender(prepareCamera);
    expect(secondControls.update).toHaveBeenCalledOnce();
    expect(prepareCamera).toHaveBeenCalledOnce();
    expect(secondControls.update.mock.invocationCallOrder[0]).toBeLessThan(
      prepareCamera.mock.invocationCallOrder[0]!,
    );
    expect(prepareCamera.mock.invocationCallOrder[0]).toBeLessThan(
      secondRenderer.render.mock.invocationCallOrder[0]!,
    );
    expect(secondRenderer.render).toHaveBeenCalledWith(
      controller.scene,
      controller.camera,
    );

    controller.dispose();
    controller.dispose();
    expect(secondControls.dispose).toHaveBeenCalledOnce();
    expect(secondRenderer.dispose).toHaveBeenCalledOnce();
    expect(secondRenderer.forceContextLoss).toHaveBeenCalledOnce();
    expect(harness.containerChildren).toEqual([]);
    expect(controller.scene.children).toEqual([]);
  });

  it("keeps the current renderer when replacement controls fail", () => {
    const harness = createHarness({ failControlsAt: 1 });
    const controller = harness.createController();
    const firstRenderer = harness.renderers[0]!;
    const firstControls = harness.controls[0]!;

    expect(() => controller.recreateRenderer(false)).toThrow(
      "Controls creation failed",
    );
    const failedRenderer = harness.renderers[1]!;
    expect(controller.renderer).toBe(firstRenderer.renderer);
    expect(controller.controls).toBe(firstControls.controls);
    expect(firstRenderer.dispose).not.toHaveBeenCalled();
    expect(firstControls.dispose).not.toHaveBeenCalled();
    expect(failedRenderer.dispose).toHaveBeenCalledOnce();
    expect(failedRenderer.forceContextLoss).toHaveBeenCalledOnce();
    expect(harness.containerChildren).toEqual([firstRenderer.canvas]);
  });

  it("cleans up a renderer when initial controls creation fails", () => {
    const harness = createHarness({ failControlsAt: 0 });

    expect(() => harness.createController()).toThrow(
      "Controls creation failed",
    );
    expect(harness.renderers[0]!.dispose).toHaveBeenCalledOnce();
    expect(harness.renderers[0]!.forceContextLoss).toHaveBeenCalledOnce();
    expect(harness.containerChildren).toEqual([]);
  });
});

interface HarnessOptions {
  readonly failControlsAt?: number;
}

interface ControllerOverrides {
  readonly lookAtTarget?: Object3D;
  readonly onControlsStart?: () => void;
  readonly onControlsEnd?: () => void;
  readonly onContextLost?: () => void;
  readonly onContextRestored?: () => void;
}

function createHarness(options: HarnessOptions = {}) {
  const containerChildren: FakeCanvas[] = [];
  const container = {
    appendChild: vi.fn((canvas: FakeCanvas) => {
      canvas.parentNode = container;
      containerChildren.push(canvas);
      return canvas;
    }),
    removeChild: vi.fn((canvas: FakeCanvas) => {
      const index = containerChildren.indexOf(canvas);
      if (index >= 0) containerChildren.splice(index, 1);
      canvas.parentNode = null;
      return canvas;
    }),
  };
  const renderers: FakeRenderer[] = [];
  const controls: FakeControls[] = [];
  const rendererParameters: WebGLRendererParameters[] = [];

  return {
    containerChildren,
    controls,
    rendererParameters,
    renderers,
    createController(overrides: ControllerOverrides = {}) {
      return new RuntimeSceneController({
        container: container as unknown as HTMLElement,
        lookAtTarget: overrides.lookAtTarget ?? new Object3D(),
        getViewport: () => ({
          width: 1600,
          height: 900,
          pixelRatio: 2,
        }),
        createRenderer: (parameters) => {
          rendererParameters.push(parameters);
          const renderer = createFakeRenderer();
          renderers.push(renderer);
          return renderer.renderer;
        },
        createControls: (
          camera: PerspectiveCamera,
          domElement: HTMLElement,
        ) => {
          if (controls.length === options.failControlsAt) {
            throw new Error("Controls creation failed");
          }
          const value = createFakeControls(camera, domElement);
          controls.push(value);
          return value.controls;
        },
        onControlsStart: overrides.onControlsStart,
        onControlsEnd: overrides.onControlsEnd,
        onContextLost: overrides.onContextLost,
        onContextRestored: overrides.onContextRestored,
      });
    },
  };
}

class FakeCanvas extends EventTarget {
  public parentNode: unknown = null;
}

interface FakeRenderer {
  renderer: WebGLRenderer;
  readonly canvas: FakeCanvas;
  readonly setSize: ReturnType<typeof vi.fn>;
  readonly setClearColor: ReturnType<typeof vi.fn>;
  readonly clear: ReturnType<typeof vi.fn>;
  readonly dispose: ReturnType<typeof vi.fn>;
  readonly forceContextLoss: ReturnType<typeof vi.fn>;
  readonly render: ReturnType<typeof vi.fn>;
  pixelRatio: number;
}

function createFakeRenderer(): FakeRenderer {
  const canvas = new FakeCanvas();
  const value: FakeRenderer = {
    renderer: undefined as unknown as WebGLRenderer,
    canvas,
    setSize: vi.fn(),
    setClearColor: vi.fn(),
    clear: vi.fn(),
    dispose: vi.fn(),
    forceContextLoss: vi.fn(),
    render: vi.fn(),
    pixelRatio: 1,
  };
  value.renderer = {
    domElement: canvas,
    shadowMap: { enabled: false, type: 0 },
    outputColorSpace: "",
    setSize: value.setSize,
    setPixelRatio: vi.fn((pixelRatio: number) => {
      value.pixelRatio = pixelRatio;
    }),
    getPixelRatio: () => value.pixelRatio,
    setClearColor: value.setClearColor,
    clear: value.clear,
    dispose: value.dispose,
    forceContextLoss: value.forceContextLoss,
    render: value.render,
  } as unknown as WebGLRenderer;
  return value;
}

interface FakeControls {
  controls: OrbitControls;
  readonly target: Object3D["position"];
  readonly update: ReturnType<typeof vi.fn>;
  readonly dispose: ReturnType<typeof vi.fn>;
  dispatch(type: "start" | "end"): void;
}

function createFakeControls(
  _camera: PerspectiveCamera,
  _domElement: HTMLElement,
): FakeControls {
  const listeners = new Map<string, Set<() => void>>();
  const target = new Object3D().position;
  const update = vi.fn();
  const dispose = vi.fn();
  const value: FakeControls = {
    controls: undefined as unknown as OrbitControls,
    target,
    update,
    dispose,
    dispatch(type) {
      for (const listener of listeners.get(type) ?? []) listener();
    },
  };
  value.controls = {
    target,
    update,
    dispose,
    addEventListener: (type: string, listener: () => void) => {
      const entries = listeners.get(type) ?? new Set<() => void>();
      entries.add(listener);
      listeners.set(type, entries);
    },
    removeEventListener: (type: string, listener: () => void) => {
      listeners.get(type)?.delete(listener);
    },
  } as unknown as OrbitControls;
  return value;
}
