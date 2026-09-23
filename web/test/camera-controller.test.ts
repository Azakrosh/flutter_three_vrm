import type { VRM, VRMSpringBoneManager } from "@pixiv/three-vrm";
import { Group, Object3D, PerspectiveCamera, Vector3 } from "three";
import { describe, expect, it, vi } from "vitest";

import {
  RuntimeCameraController,
  type RuntimeCameraControls,
} from "../src/camera-controller";

describe("runtime camera controller", () => {
  it("configures constrained and free modes and restores them on new controls", () => {
    const camera = createCamera();
    const controls = createControls(camera);
    const controller = new RuntimeCameraController(camera, controls);

    expect(controls).toMatchObject({
      enabled: true,
      enablePan: false,
      enableRotate: false,
      enableZoom: true,
      minDistance: 0.5,
      maxDistance: 6.6,
    });

    controller.setMode("free");
    expect(controls.enablePan).toBe(true);
    expect(controls.enableRotate).toBe(true);

    const replacement = createControls(camera);
    controller.replaceControls(replacement);
    expect(replacement.enablePan).toBe(true);
    expect(replacement.enableRotate).toBe(true);
    expect(replacement.update).toHaveBeenCalledOnce();
    expect(() => controller.setMode("orbit")).toThrow("Unknown camera mode");
  });

  it("frames a VRM immediately and resets its model and spring bones", () => {
    const camera = createCamera();
    const controls = createControls(camera);
    const controller = new RuntimeCameraController(camera, controls);
    const { vrm, resetSpringBones } = createVrm();
    vrm.scene.position.set(2, 3, 4);

    expect(controller.frameAvatar(vrm, 0, 0, true)).toBe(true);

    expect(vrm.scene.position.toArray()).toEqual([0, 0, 0]);
    expect(resetSpringBones).toHaveBeenCalledOnce();
    expect(controls.target.x).toBeCloseTo(0);
    expect(controls.target.y).toBeCloseTo(0.825);
    expect(camera.position.x).toBeCloseTo(0);
    expect(camera.position.y).toBeCloseTo(0.825);
    expect(controller.getTransform()).toMatchObject({
      x: -0,
      y: expect.closeTo(0.125),
    });
    expect(controller.getTransform().zoom).toBeGreaterThan(1);
    expect(controls.enabled).toBe(true);
  });

  it("animates a reset and preserves validated camera transforms", () => {
    const camera = createCamera();
    const controls = createControls(camera);
    const controller = new RuntimeCameraController(camera, controls);
    const { vrm } = createVrm();

    controller.setTransform({ x: 0.2, y: -0.1, zoom: 1.4 });
    expect(controller.hasCustomTransform).toBe(true);
    const transform = controller.getTransform();
    expect(transform.x).toBeCloseTo(0.2);
    expect(transform.y).toBeCloseTo(-0.1);
    expect(transform.zoom).toBeCloseTo(1.4);

    expect(controller.reset(vrm, 1000, 5)).toBe(true);
    expect(controller.hasCustomTransform).toBe(false);
    expect(controls.enabled).toBe(false);
    controller.updateAnimation(5.5);
    expect(camera.position.y).toBeGreaterThan(0.85);
    expect(camera.position.y).toBeLessThan(0.95);
    controller.updateAnimation(6);
    expect(controls.enabled).toBe(true);
    expect(controls.target.y).toBeCloseTo(0.825);

    expect(() => controller.setTransform({ x: 0, y: 0, zoom: 0 })).toThrow(
      "must be positive",
    );
    expect(() => controller.setTransform({ x: 0, y: Number.NaN, zoom: 1 })).toThrow(
      "finite numbers",
    );
    expect(() =>
      controller.setTransform({ x: "0", y: 0, zoom: 1 })
    ).toThrow("finite numbers");
  });

  it("smoothly follows constrained pan and captures free control changes", () => {
    const camera = createCamera();
    const controls = createControls(camera);
    const controller = new RuntimeCameraController(camera, controls);

    controller.setConstrainedPanTarget({
      deltaX: 100,
      deltaY: -50,
      viewportWidth: 1000,
      viewportHeight: 500,
      startTarget: controls.target.clone(),
      modelHeight: 1.6,
    });
    expect(controller.hasCustomTransform).toBe(true);
    const initialTarget = controls.target.clone();
    controller.updatePanFollowing(1 / 60);
    expect(controls.target.equals(initialTarget)).toBe(false);
    expect(camera.position.x).toBeCloseTo(controls.target.x);

    controller.setMode("free");
    controls.target.set(0.3, 1.2, -0.1);
    camera.position.set(0.3, 1.2, 2);
    controller.captureControlsTransform();
    expect(controller.getTransform()).toMatchObject({
      x: -0.3,
      y: -0.25,
    });
  });
});

function createCamera(): PerspectiveCamera {
  const camera = new PerspectiveCamera(36, 16 / 9, 0.1, 20);
  camera.position.set(0, 0.95, 1.9);
  return camera;
}

function createControls(camera: PerspectiveCamera): RuntimeCameraControls {
  const target = new Vector3(0, 0.95, 0);
  return {
    target,
    enabled: true,
    enablePan: true,
    enableRotate: true,
    enableZoom: true,
    minPolarAngle: 0,
    maxPolarAngle: Math.PI,
    minAzimuthAngle: -Infinity,
    maxAzimuthAngle: Infinity,
    minDistance: 0,
    maxDistance: Infinity,
    enableDamping: false,
    dampingFactor: 0,
    getDistance: () => camera.position.distanceTo(target),
    update: vi.fn(),
  };
}

function createVrm(): {
  vrm: VRM;
  resetSpringBones: ReturnType<typeof vi.fn>;
} {
  const scene = new Group();
  const head = new Object3D();
  head.position.y = 1.5;
  scene.add(head);
  const resetSpringBones = vi.fn();
  const springBoneManager = {
    reset: resetSpringBones,
  } as unknown as VRMSpringBoneManager;
  const vrm = {
    scene,
    humanoid: {
      getNormalizedBoneNode: (name: string) => name === "head" ? head : null,
      getRawBoneNode: () => null,
    },
    springBoneManager,
  } as unknown as VRM;
  return { vrm, resetSpringBones };
}
