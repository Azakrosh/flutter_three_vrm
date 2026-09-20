import type { VRM, VRMSpringBoneManager } from "@pixiv/three-vrm";
import {
  AnimationClip,
  BoxGeometry,
  Group,
  Mesh,
  MeshBasicMaterial,
  Object3D,
  Scene,
} from "three";
import { describe, expect, it, vi } from "vitest";

import { VrmModelSession } from "../src/model-session";

describe("VRM model session", () => {
  it("owns scene, motion, physics, events, and deterministic disposal", () => {
    const scene = new Scene();
    const { vrm, springBoneManager, resetSpringBones, mesh } = createVrm();
    const disposeScene = vi.fn();
    const onAnimationFinished = vi.fn();
    const session = new VrmModelSession(scene, {
      prepareVrm: vi.fn(),
      disposeScene,
    });

    const report = session.attach(vrm, {
      sourceBytes: 2048,
      lookAtTarget: new Object3D(),
      physicsEnabled: false,
      shadowsEnabled: true,
      onAnimationFinished,
    });

    expect(scene.children).toContain(vrm.scene);
    expect(session.currentVrm).toBe(vrm);
    expect(session.mixer).not.toBeNull();
    expect(session.motionTransitions).not.toBeNull();
    expect(report).toMatchObject({
      name: "Session Avatar",
      sourceBytes: 2048,
      height: 1.65,
      springBoneJoints: 3,
    });
    expect(mesh.castShadow).toBe(true);
    expect(mesh.receiveShadow).toBe(true);
    expect(vrm.springBoneManager).toBeNull();
    expect(resetSpringBones).toHaveBeenCalledOnce();

    session.setPhysicsEnabled(true);
    expect(vrm.springBoneManager).toBe(springBoneManager);
    expect(resetSpringBones).toHaveBeenCalledTimes(2);

    const mixer = session.mixer!;
    const clip = new AnimationClip("Wave", 1, []);
    const action = mixer.clipAction(clip);
    Object.assign(action, {
      _flutterPlaybackId: "playback-1",
      _hasNotifiedFinished: false,
    });
    session.motionTransitions!.currentAction = action;
    mixer.dispatchEvent({ type: "finished", action, direction: 1 });
    mixer.dispatchEvent({ type: "finished", action, direction: 1 });
    expect(onAnimationFinished).toHaveBeenCalledOnce();
    expect(onAnimationFinished).toHaveBeenCalledWith({
      name: "Wave",
      playbackId: "playback-1",
    });

    expect(session.detach()).toBe(true);
    expect(session.detach()).toBe(false);
    expect(scene.children).not.toContain(vrm.scene);
    expect(disposeScene).toHaveBeenCalledOnce();
    expect(disposeScene).toHaveBeenCalledWith(vrm.scene);
    expect(session.currentVrm).toBeNull();
    expect(session.mixer).toBeNull();
    expect(session.motionTransitions).toBeNull();
    expect(session.modelReport).toBeNull();

    mixer.dispatchEvent({ type: "finished", action, direction: 1 });
    expect(onAnimationFinished).toHaveBeenCalledOnce();
  });

  it("rolls back scene ownership when session initialization fails", () => {
    const scene = new Scene();
    const { vrm } = createVrm();
    const disposeScene = vi.fn();
    const session = new VrmModelSession(scene, {
      prepareVrm: vi.fn(),
      disposeScene,
      createMotionTransitions: () => {
        throw new Error("Motion initialization failed.");
      },
    });

    expect(() =>
      session.attach(vrm, {
        sourceBytes: 1,
        lookAtTarget: new Object3D(),
        physicsEnabled: true,
        shadowsEnabled: false,
        onAnimationFinished: vi.fn(),
      }),
    ).toThrow("Motion initialization failed.");
    expect(scene.children).not.toContain(vrm.scene);
    expect(disposeScene).toHaveBeenCalledWith(vrm.scene);
    expect(session.currentVrm).toBeNull();
  });
});

function createVrm(): {
  vrm: VRM;
  springBoneManager: VRMSpringBoneManager;
  resetSpringBones: ReturnType<typeof vi.fn>;
  mesh: Mesh;
} {
  const root = new Group();
  const head = new Object3D();
  head.position.y = 1.5;
  root.add(head);
  const mesh = new Mesh(new BoxGeometry(), new MeshBasicMaterial());
  root.add(mesh);
  const resetSpringBones = vi.fn();
  const springBoneManager = {
    joints: new Set([{}, {}, {}]),
    reset: resetSpringBones,
  } as unknown as VRMSpringBoneManager;
  const vrm = {
    scene: root,
    meta: { name: "Session Avatar", metaVersion: "1" },
    humanoid: {
      normalizedHumanBones: { head: {} },
      getNormalizedBoneNode: (name: string) => name === "head" ? head : null,
    },
    lookAt: { target: null },
    springBoneManager,
  } as unknown as VRM;
  return { vrm, springBoneManager, resetSpringBones, mesh };
}
