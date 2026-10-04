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
    expect(camera.position.x).toBeCloseTo(0);
    expect(camera.position.y).toBeCloseTo(1.58);
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
    expect(camera.position.y).toBeGreaterThan(1.2);
    expect(camera.position.y).toBeLessThan(1.35);
    const halfwayPosition = camera.position.clone();
    controller.prepareForRender();
    expect(camera.position.toArray()).toEqual(halfwayPosition.toArray());
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

  it("smoothly resets a physically panned free camera", () => {
    const camera = createCamera();
    const controls = createControls(camera);
    const controller = new RuntimeCameraController(camera, controls);
    const { vrm } = createVrm();

    controller.frameAvatar(vrm, 0, 0, true);
    controller.setMode("free");
    controller.setTransform({ x: 0, y: 0.5, zoom: 1.2 });
    controller.prepareForRender();
    const startCameraY = camera.position.y;
    controller.finishRender();

    controller.reset(vrm, 1000, 0);
    controller.updateAnimation(0.5);
    controller.prepareForRender();

    expect(camera.position.y).toBeGreaterThan(startCameraY);
    expect(camera.position.y).toBeLessThan(1.58);
    expect(controls.target.y).toBeCloseTo(1.05);
    controller.finishRender();

    controller.updateAnimation(1);
    expect(camera.position.y).toBeCloseTo(1.58);
    expect(controls.target.y).toBeCloseTo(1.05);
    expect(controller.getTransform()).toMatchObject({ x: 0, y: 0 });
  });

  it("smoothly translates the complete constrained camera rig", () => {
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
    const initialRigOffset = camera.position.clone().sub(controls.target);
    controller.updatePanFollowing(1 / 60);
    controller.prepareForRender();

    expect(controls.target.equals(initialTarget)).toBe(false);
    expect(camera.position.equals(initialPosition)).toBe(false);
    expect(camera.position.clone().sub(controls.target).toArray()).toEqual(
      initialRigOffset.toArray(),
    );
    expect(camera.view?.enabled ?? false).toBe(false);
    expect(controller.getTransform().x).toBeGreaterThan(0);
    expect(controller.getTransform().y).toBeGreaterThan(0);
    expectProjectedAtCenter(camera, controls.target);
  });

  it("keeps a level optical axis when lower-body framing is zoomed close", () => {
    const camera = createCamera();
    const controls = createControls(camera);
    const controller = new RuntimeCameraController(camera, controls);
    const { vrm } = createVrm();
    const eyeAnchor = new Vector3(0, 1.58, 0.02);

    controller.frameAvatar(vrm, 0, 0, true);
    controller.setTransform({ x: 0.15, y: 0.8, zoom: 0.75 });
    controller.prepareForRender();

    const translatedAim = eyeAnchor.clone().add(new Vector3(-0.15, -0.8, 0));
    const viewDirection = new Vector3();
    camera.getWorldDirection(viewDirection);

    expect(camera.position.y).toBeCloseTo(translatedAim.y);
    expect(viewDirection.x).toBeCloseTo(0, 8);
    expect(viewDirection.y).toBeCloseTo(0, 8);
    expect(viewDirection.z).toBeCloseTo(-1, 8);
    expect(camera.position.distanceTo(controls.target)).toBeCloseTo(0.75);
    expect(camera.view?.enabled ?? false).toBe(false);
    expectProjectedAtCenter(camera, translatedAim);
  });

  it("keeps a level optical axis for close lower-body zoom in free mode", () => {
    const camera = createCamera();
    const controls = createControls(camera);
    const controller = new RuntimeCameraController(camera, controls);
    const { vrm } = createVrm();
    const eyeAnchor = new Vector3(0, 1.58, 0.02);

    controller.frameAvatar(vrm, 0, 0, true);
    controller.setMode("free");
    controller.setTransform({ x: 0.15, y: 0.8, zoom: 0.75 });

    simulateOrbitControlsZoom(camera, controls.target, 0.55);
    controller.updatePanFollowing(1 / 60);
    controller.prepareForRender();

    const translatedAim = eyeAnchor.clone().add(new Vector3(-0.15, -0.8, 0));
    const viewDirection = new Vector3();
    camera.getWorldDirection(viewDirection);

    expect(camera.position.y).toBeCloseTo(translatedAim.y);
    expect(viewDirection.x).toBeCloseTo(0, 8);
    expect(viewDirection.y).toBeCloseTo(0, 8);
    expect(viewDirection.z).toBeCloseTo(-1, 8);
    expect(camera.view?.enabled ?? false).toBe(false);
    expectProjectedAtCenter(camera, translatedAim);
    controller.finishRender();
    expect(camera.position.distanceTo(controls.target)).toBeCloseTo(0.55);
  });

  it("preserves panned framing across camera modes and controls replacement", () => {
    const camera = createCamera();
    const controls = createControls(camera);
    const controller = new RuntimeCameraController(camera, controls);
    const { vrm } = createVrm();
    const eyeAnchor = new Vector3(0, 1.58, 0.02);

    controller.frameAvatar(vrm, 0, 0, true);
    controller.setTransform({ x: 0.2, y: 0.5, zoom: 1.2 });
    controller.prepareForRender();
    camera.updateMatrixWorld(true);
    const constrainedProjection = eyeAnchor.clone().project(camera);

    controller.setMode("free");
    controller.prepareForRender();
    camera.updateMatrixWorld(true);
    const freeProjection = eyeAnchor.clone().project(camera);

    expect(camera.view?.enabled ?? false).toBe(false);
    expect(camera.position.x).toBeCloseTo(eyeAnchor.x - 0.2);
    expect(camera.position.y).toBeCloseTo(eyeAnchor.y - 0.5);
    expect(freeProjection.x).toBeCloseTo(constrainedProjection.x, 8);
    expect(freeProjection.y).toBeCloseTo(constrainedProjection.y, 8);
    controller.finishRender();

    controller.setMode("constrained");
    expect(camera.view?.enabled ?? false).toBe(false);
    expect(camera.position.distanceTo(controls.target)).toBeCloseTo(1.2);

    const replacement = createControls(camera);
    controller.replaceControls(replacement);
    expect(camera.position.distanceTo(replacement.target)).toBeCloseTo(1.2);
    expect(replacement.target.x).toBeCloseTo(0.03 - 0.2);
    expect(replacement.target.y).toBeCloseTo(1.05 - 0.5);
  });

  it("keeps the torso pivot fixed after free pan and later rotation", () => {
    const camera = createCamera();
    const controls = createControls(camera);
    const controller = new RuntimeCameraController(camera, controls);
    const { vrm } = createVrm();

    controller.frameAvatar(vrm, 0, 0, true);
    controller.setMode("free");
    const pivot = controls.target.clone();
    const basePosition = camera.position.clone();

    // OrbitControls emits start/end for a right-button click even without a
    // move. Capturing that gesture must be a strict no-op.
    controller.captureControlsTransform();
    expect(controls.target.toArray()).toEqual(pivot.toArray());
    expect(controller.getTransform()).toMatchObject({ x: 0, y: 0 });

    const nativePan = new Vector3(0.3, 0.25, 0);
    controls.target.add(nativePan);
    camera.position.add(nativePan);

    controller.updatePanFollowing(1 / 60);

    expect(controls.target.toArray()).toEqual(pivot.toArray());
    expect(camera.position.x).toBeCloseTo(basePosition.x);
    expect(camera.position.y).toBeCloseTo(basePosition.y);
    expect(camera.position.z).toBeCloseTo(basePosition.z);
    expect(controller.getTransform().x).toBeCloseTo(-0.3);
    expect(controller.getTransform().y).toBeCloseTo(-0.25);

    controller.prepareForRender();
    expect(camera.position.x).toBeCloseTo(basePosition.x + nativePan.x);
    expect(camera.position.y).toBeCloseTo(basePosition.y + nativePan.y);
    controller.finishRender();

    // Rotation continues around the humanoid torso, never around the point
    // where the preceding right-button pan gesture occurred.
    camera.position.set(pivot.x + 1.4, pivot.y + 0.2, pivot.z);
    controller.updatePanFollowing(1 / 60);

    expect(controls.target.toArray()).toEqual(pivot.toArray());
    expect(controller.getTransform().x).toBeCloseTo(-0.3);
    expect(controller.getTransform().y).toBeCloseTo(-0.25);
  });

  it("keeps the eye line stable while zooming around the torso pivot", () => {
    const camera = createCamera();
    const controls = createControls(camera);
    const controller = new RuntimeCameraController(camera, controls);
    const { vrm } = createVrm();
    const eyeAnchor = new Vector3(0, 1.58, 0.02);

    controller.frameAvatar(vrm, 0, 0, true);
    const torsoPivot = controls.target.clone();
    expect(camera.position.y).toBeCloseTo(eyeAnchor.y);

    simulateOrbitControlsZoom(camera, torsoPivot, 1.1);
    controller.updatePanFollowing(1 / 60);
    controller.prepareForRender();

    expect(controls.target.toArray()).toEqual(torsoPivot.toArray());
    expect(camera.position.distanceTo(torsoPivot)).toBeCloseTo(1.1);
    expect(camera.position.y).toBeCloseTo(eyeAnchor.y);
    expectProjectedAtCenter(camera, eyeAnchor);

    simulateOrbitControlsZoom(camera, torsoPivot, 0.5);
    controller.updatePanFollowing(1 / 60);
    controller.prepareForRender();

    expect(controls.minDistance).toBeGreaterThan(0.5);
    expect(camera.position.distanceTo(torsoPivot)).toBeCloseTo(
      controls.minDistance,
    );
    expect(camera.position.distanceTo(eyeAnchor)).toBeGreaterThanOrEqual(0.4);
    expectProjectedAtCenter(camera, eyeAnchor);

    controller.setMode("free");
    expect(controls.minDistance).toBeCloseTo(0.5);
    simulateOrbitControlsZoom(camera, torsoPivot, 2.2);
    controller.updatePanFollowing(1 / 60);
    controller.prepareForRender();

    expect(controls.target.toArray()).toEqual(torsoPivot.toArray());
    expect(camera.position.distanceTo(torsoPivot)).toBeCloseTo(2.2);
    expect(camera.position.y).toBeCloseTo(eyeAnchor.y);
    expectProjectedAtCenter(camera, eyeAnchor);
  });

  it("recovers constrained framing after OrbitControls applies its angle limits", () => {
    const camera = createCamera();
    const controls = createControls(camera);
    const controller = new RuntimeCameraController(camera, controls);
    const { vrm } = createVrm();
    const eyeAnchor = new Vector3(0, 1.58, 0.02);

    controller.frameAvatar(vrm, 0, 0, true);
    const torsoPivot = controls.target.clone();
    const zoomDistance = 1.1;

    // Reproduce the old implementation: fixed PI / 2 and zero azimuth make
    // OrbitControls put the camera at torso height before every render.
    camera.position.set(
      torsoPivot.x,
      torsoPivot.y,
      torsoPivot.z + zoomDistance,
    );
    camera.lookAt(torsoPivot);
    controller.prepareForRender();

    expect(camera.position.distanceTo(torsoPivot)).toBeCloseTo(zoomDistance);
    expect(camera.position.x).toBeCloseTo(eyeAnchor.x);
    expect(camera.position.y).toBeCloseTo(eyeAnchor.y);
    expectProjectedAtCenter(camera, eyeAnchor);
    expect(controls.minPolarAngle).toBeCloseTo(controls.maxPolarAngle);
    expect(controls.minPolarAngle).not.toBeCloseTo(Math.PI / 2);
    expect(controls.minAzimuthAngle).toBeCloseTo(controls.maxAzimuthAngle);
  });

  it("returns from free mode to an upright constrained eye-level view", () => {
    const camera = createCamera();
    const controls = createControls(camera);
    const controller = new RuntimeCameraController(camera, controls);
    const { vrm } = createVrm();
    const eyeAnchor = new Vector3(0, 1.58, 0.02);

    controller.frameAvatar(vrm, 0, 0, true);
    controller.setMode("free");
    const torsoPivot = controls.target.clone();
    camera.position.set(
      torsoPivot.x + 0.6,
      torsoPivot.y - 0.25,
      torsoPivot.z + 1.4,
    );
    controller.prepareForRender();
    const freeDistance = camera.position.distanceTo(torsoPivot);

    controller.setMode("constrained");

    expect(camera.position.distanceTo(torsoPivot)).toBeCloseTo(freeDistance);
    expect(camera.position.x).toBeCloseTo(eyeAnchor.x);
    expect(camera.position.y).toBeCloseTo(eyeAnchor.y);
    expectProjectedAtCenter(camera, eyeAnchor);
  });

  it("reanchors a transform restored before model framing", () => {
    const camera = createCamera();
    const controls = createControls(camera);
    const controller = new RuntimeCameraController(camera, controls);
    const { vrm } = createVrm();

    controller.setTransform({ x: 0.2, y: -0.1, zoom: 1.4 });
    controller.frameAvatar(vrm, 0, 0, true);

    // In constrained mode the serialized pan translates both camera and
    // OrbitControls target. Their relative distance remains the saved zoom.
    expect(controls.target.x).toBeCloseTo(0.03 - 0.2);
    expect(controls.target.y).toBeCloseTo(1.05 + 0.1);
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
    screenSpacePanning: true,
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
  const leftEye = new Object3D();
  leftEye.position.set(-0.03, 1.58, 0.02);
  scene.add(leftEye);
  const rightEye = new Object3D();
  rightEye.position.set(0.03, 1.58, 0.02);
  scene.add(rightEye);
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
        leftEye,
        rightEye,
        leftHand,
      })[name] ?? null,
      getRawBoneNode: () => null,
    },
    springBoneManager,
  } as unknown as VRM;
  return { vrm, resetSpringBones };
}

function simulateOrbitControlsZoom(
  camera: PerspectiveCamera,
  target: Vector3,
  distance: number,
): void {
  camera.position.sub(target).normalize().multiplyScalar(distance).add(target);
  camera.lookAt(target);
}

function expectProjectedAtCenter(
  camera: PerspectiveCamera,
  worldPosition: Vector3,
): void {
  camera.updateMatrixWorld(true);
  const projected = worldPosition.clone().project(camera);
  expect(projected.x).toBeCloseTo(0, 8);
  expect(projected.y).toBeCloseTo(0, 8);
}
