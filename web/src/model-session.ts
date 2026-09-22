import {
  VRMUtils,
  type VRM,
  type VRMSpringBoneManager,
} from "@pixiv/three-vrm";
import {
  AnimationMixer,
  Vector3,
  type AnimationAction,
  type AnimationMixerEventMap,
  type Object3D,
  type Scene,
} from "three";

import {
  MotionTransitionController,
} from "./motion-transition";
import {
  createRuntimeModelReport,
  type RuntimeModelReport,
} from "./model-report";

export interface ModelAnimationFinished {
  readonly name: string;
  readonly playbackId: string;
}

export interface VrmModelAttachOptions {
  readonly sourceBytes: number;
  readonly lookAtTarget: Object3D;
  readonly physicsEnabled: boolean;
  readonly shadowsEnabled: boolean;
  readonly onAnimationFinished: (event: ModelAnimationFinished) => void;
}

export interface VrmModelSessionDependencies {
  readonly prepareVrm?: (vrm: VRM) => void;
  readonly disposeScene?: (scene: Object3D) => void;
  readonly createMixer?: (root: Object3D) => AnimationMixer;
  readonly createMotionTransitions?: (
    mixer: AnimationMixer,
  ) => MotionTransitionController;
}

type MutableVrm = Omit<VRM, "springBoneManager"> & {
  springBoneManager?: VRMSpringBoneManager | null;
};

type FlutterAnimationAction = AnimationAction & {
  _flutterPlaybackId?: unknown;
  _hasNotifiedFinished?: boolean;
};

export class VrmModelSession {
  private readonly prepareVrm: (vrm: VRM) => void;
  private readonly disposeScene: (scene: Object3D) => void;
  private readonly createMixer: (root: Object3D) => AnimationMixer;
  private readonly createMotionTransitions: (
    mixer: AnimationMixer,
  ) => MotionTransitionController;
  private animationFinishedListener:
    | ((event: AnimationMixerEventMap["finished"]) => void)
    | null = null;
  private cachedSpringBoneManager: VRMSpringBoneManager | null = null;

  public constructor(
    private readonly scene: Scene,
    dependencies: VrmModelSessionDependencies = {},
  ) {
    this.prepareVrm = dependencies.prepareVrm ?? prepareVrmForRuntime;
    this.disposeScene = dependencies.disposeScene ?? VRMUtils.deepDispose;
    this.createMixer = dependencies.createMixer ?? ((root) => new AnimationMixer(root));
    this.createMotionTransitions =
      dependencies.createMotionTransitions ??
      ((mixer) => new MotionTransitionController(mixer));
  }

  public currentVrm: VRM | null = null;
  public mixer: AnimationMixer | null = null;
  public motionTransitions: MotionTransitionController | null = null;
  public modelReport: RuntimeModelReport | null = null;

  public get springBoneManager(): VRMSpringBoneManager | null {
    return this.currentVrm?.springBoneManager ?? this.cachedSpringBoneManager;
  }

  public attach(vrm: VRM, options: VrmModelAttachOptions): RuntimeModelReport {
    if (this.currentVrm !== null) {
      throw new Error("Unload the current VRM model before attaching another one.");
    }

    this.prepareVrm(vrm);
    this.currentVrm = vrm;
    this.scene.add(vrm.scene);

    try {
      if (vrm.lookAt) vrm.lookAt.target = options.lookAtTarget;
      this.setPhysicsEnabled(options.physicsEnabled);
      applyMeshShadows(vrm.scene, options.shadowsEnabled);

      this.mixer = this.createMixer(vrm.scene);
      this.motionTransitions = this.createMotionTransitions(this.mixer);
      const height = measureVrmHeight(vrm);
      this.modelReport = createRuntimeModelReport(
        vrm,
        options.sourceBytes,
        height,
        this.cachedSpringBoneManager?.joints.size ?? 0,
      );
      this.animationFinishedListener = (event) => {
        const action = event.action as FlutterAnimationAction;
        if (
          action !== this.motionTransitions?.currentAction ||
          action._hasNotifiedFinished === true
        ) {
          return;
        }
        const playbackId = action._flutterPlaybackId;
        if (typeof playbackId !== "string" || playbackId.length === 0) return;
        action._hasNotifiedFinished = true;
        options.onAnimationFinished({
          name: action.getClip().name,
          playbackId,
        });
      };
      this.mixer.addEventListener("finished", this.animationFinishedListener);
      return this.modelReport;
    } catch (error) {
      this.detach();
      throw error;
    }
  }

  public setPhysicsEnabled(enabled: boolean): void {
    if (this.currentVrm === null) return;
    const vrm = this.currentVrm as MutableVrm;
    if (!enabled) {
      if (vrm.springBoneManager) {
        vrm.springBoneManager.reset();
        this.cachedSpringBoneManager = vrm.springBoneManager;
        vrm.springBoneManager = null;
      }
      return;
    }
    if (this.cachedSpringBoneManager !== null) {
      vrm.springBoneManager = this.cachedSpringBoneManager;
      vrm.springBoneManager.reset();
      this.cachedSpringBoneManager = null;
    }
  }

  public detach(): boolean {
    const vrm = this.currentVrm;
    if (vrm === null) return false;

    if (this.mixer !== null) {
      if (this.animationFinishedListener !== null) {
        this.mixer.removeEventListener(
          "finished",
          this.animationFinishedListener,
        );
      }
      this.motionTransitions?.dispose();
      this.mixer.uncacheRoot(vrm.scene);
    }
    this.scene.remove(vrm.scene);
    this.disposeScene(vrm.scene);

    this.currentVrm = null;
    this.mixer = null;
    this.motionTransitions = null;
    this.modelReport = null;
    this.cachedSpringBoneManager = null;
    this.animationFinishedListener = null;
    return true;
  }
}

function prepareVrmForRuntime(vrm: VRM): void {
  try {
    VRMUtils.removeUnnecessaryVertices?.(vrm.scene);
    VRMUtils.rotateVRM0?.(vrm);
  } catch (error) {
    console.warn("VRMUtils warning:", error);
  }
}

function applyMeshShadows(root: Object3D, enabled: boolean): void {
  root.traverse((object) => {
    if (!("isMesh" in object) || object.isMesh !== true) return;
    object.castShadow = enabled;
    object.receiveShadow = enabled;
  });
}

function measureVrmHeight(vrm: VRM): number {
  try {
    vrm.scene.updateMatrixWorld(true);
    const headBone = vrm.humanoid.getNormalizedBoneNode("head");
    if (headBone !== null) {
      const headPosition = new Vector3();
      headBone.getWorldPosition(headPosition);
      return headPosition.y + 0.15;
    }
  } catch (error) {
    console.warn(
      "Could not calculate exact VRM height from bones, using default 1.6m",
      error,
    );
  }
  return 1.6;
}
