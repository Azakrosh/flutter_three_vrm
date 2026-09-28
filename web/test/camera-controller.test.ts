import type { VRM, VRMSpringBoneManager } from "@pixiv/three-vrm";
import { Group, Object3D, PerspectiveCamera, Vector2, Vector3 } from "three";
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
      enableDamping: false,
      dampingFactor: 0,
      minDistance: 0.5,
      maxDistance: 6.6,
    });

    controller.setMode("free");
    expect(controls.enablePan).toBe(true);
    expect(controls.enableRotate).toBe(true);
    expect(controls.enableDamping).toBe(false);
    expect(controls.dampingFactor).toBe(0);

    const replacement = createControls(camera);
    controller.replaceControls(replacement);
    expect(replacement.enablePan).toBe(true);
    expect(replacement.enableRotate).toBe(true);
    expect(replacement.enableDamping).toBe(false);
    expect(replacement.dampingFactor).toBe(0);
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
    // The orbit pivot comes from the torso, not from asymmetric extremities.
    expect(controls.target.toArray()).toEqual([
      expect.closeTo(0.03),
      expect.closeTo(1.05),
      expect.closeTo(0.01),
    ]);
    expect(camera.position.x).toBeCloseTo(0.03);
    expect(camera.position.y).toBeCloseTo(1.05);
    expect(controller.getTransform()).toMatchObject({
      x: 0,
      y: 0,
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
    expect(camera.position.y).toBeGreaterThan(0.95);
    expect(camera.position.y).toBeLessThan(1.05);
    controller.updateAnimation(6);
    expect(controls.enabled).toBe(true);
    expect(controls.target.y).toBeCloseTo(1.05);
    expect(controller.getTransform()).toMatchObject({ x: 0, y: 0 });

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

  it("smoothly follows constrained pan", () => {
    const camera = createCamera();
    const controls = createControls(camera);
    const controller = new RuntimeCameraController(camera, controls);

    controller.setConstrainedPanTarget({
      deltaX: 100,
      deltaY: -50,
      viewportWidth: 1000,
      viewportHeight: 500,
      startPan: new Vector2(),
      modelHeight: 1.6,
    });
    expect(controller.hasCustomTransform).toBe(true);
    const initialTarget = controls.target.clone();
    const initialPosition = camera.position.clone();
    controller.updatePanFollowing(1 / 60);
    expect(controls.target.equals(initialTarget)).toBe(true);
    expect(camera.position.equals(initialPosition)).toBe(true);
    expect(camera.view?.enabled).toBe(true);
    expect(controller.getTransform().x).toBeGreaterThan(0);
    expect(controller.getTransform().y).toBeGreaterThan(0);
  });

  it("keeps the torso pivot stable after free pan and rotation", () => {
    const camera = createCamera();
    const controls = createControls(camera);
    const controller = new RuntimeCameraController(camera, controls);
    const { vrm } = createVrm();

    controller.frameAvatar(vrm, 0, 0, true);
    controller.setMode("free");
    const pivot = controls.target.clone();
    const prePanPosition = camera.position.clone();
    const nativePan = new Vector3(0.3, 0.25, 0);
    controls.target.add(nativePan);
    camera.position.add(nativePan);

    controller.updatePanFollowing(1 / 60);

    expect(controls.target.toArray()).toEqual(pivot.toArray());
    expect(camera.position.x).toBeCloseTo(prePanPosition.x);
    expect(camera.position.y).toBeCloseTo(prePanPosition.y);
    expect(camera.position.z).toBeCloseTo(prePanPosition.z);
    expect(controller.getTransform().x).toBeCloseTo(-0.3);
    expect(controller.getTransform().y).toBeCloseTo(-0.25);
    expect(camera.view?.enabled).toBe(true);

    // A later orbit changes only the camera position. The torso remains the
    // target and the independent screen-space pan is retained.
    camera.position.set(pivot.x + 1.4, pivot.y + 0.2, pivot.z);
    controller.updatePanFollowing(1 / 60);

    expect(controls.target.toArray()).toEqual(pivot.toArray());
    expect(controller.getTransform().x).toBeCloseTo(-0.3);
    expect(controller.getTransform().y).toBeCloseTo(-0.25);
  });

  it("reanchors a transform restored before model framing", () => {
    const camera = createCamera();
    const controls = createControls(camera);
    const controller = new RuntimeCameraController(camera, controls);
    const { vrm } = createVrm();

    controller.setTransform({ x: 0.2, y: -0.1, zoom: 1.4 });
    controller.frameAvatar(vrm, 0, 0, true);

    expect(controls.target.x).toBeCloseTo(0.03);
    expect(controls.target.y).toBeCloseTo(1.05);
    expect(controls.target.z).toBeCloseTo(0.01);
    expect(camera.position.distanceTo(controls.target)).toBeCloseTo(1.4);
    expect(controller.getTransform()).toMatchObject({
      x: 0.2,
      y: -0.1,
      zoom: expect.closeTo(1.4),
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
  const hips = new Object3D();
  hips.position.set(0.08, 0.9, 0.03);
  scene.add(hips);
  const upperChest = new Object3D();
  upperChest.position.set(-0.02, 1.2, -0.01);
  scene.add(upperChest);
  const head = new Object3D();
  head.position.y = 1.5;
  scene.add(head);
  const leftHand = new Object3D();
  leftHand.position.set(-1.4, 1.3, 0);
  scene.add(leftHand);
  const resetSpringBones = vi.fn();
  const springBoneManager = {
    reset: resetSpringBones,
  } as unknown as VRMSpringBoneManager;
  const vrm = {
    scene,
    humanoid: {
      getNormalizedBoneNode: (name: string) => ({
        hips,
        upperChest,
        head,
        leftHand,
      })[name] ?? null,
      getRawBoneNode: () => null,
    },
    springBoneManager,
  } as unknown as VRM;
  return { vrm, resetSpringBones };
}
