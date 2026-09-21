import type { VRM } from "@pixiv/three-vrm";
import {
  VRMLookAtQuaternionProxy,
  createVRMAnimationClip,
  type VRMAnimation,
} from "@pixiv/three-vrm-animation";
import {
  AnimationClip,
  type AnimationAction,
} from "three";
import type { GLTF } from "three/addons/loaders/GLTFLoader.js";

import { createHumanoidAnimationClip } from "./humanoid-animation";
import type { MotionTransitionController } from "./motion-transition";
import { createNormalizedPoseClip, getNormalizedPose } from "./pose";
import type { RuntimeRecord } from "./protocol-contract";

export interface RuntimeMotionEvent {
  readonly name: string;
  readonly playbackId: string;
}

export interface RuntimeMotionDependencies {
  readonly getVrm: () => VRM | null;
  readonly getTransitions: () => MotionTransitionController | null;
  readonly resetProceduralMotion: () => void;
  readonly finalizeRestPose: () => void;
  readonly onStarted: (event: RuntimeMotionEvent) => void;
  readonly onFinished: (event: RuntimeMotionEvent) => void;
}

type PlaybackAction = AnimationAction & {
  _flutterPlaybackId?: string;
  _hasNotifiedFinished?: boolean;
};

type RuntimeLookAt = NonNullable<VRM["lookAt"]> & {
  quaternionProxy?: VRMLookAtQuaternionProxy;
};

/** Coordinates VRMA, glTF, Pose and rest transitions over one model-owned mixer. */
export class RuntimeMotionController {
  private poseSequence = 0;
  private pendingRestPoseReset = false;
  private paused = false;

  public constructor(private readonly dependencies: RuntimeMotionDependencies) {}

  public get isActive(): boolean {
    return Boolean(this.dependencies.getTransitions()?.isActive);
  }

  public get isPaused(): boolean {
    return this.paused;
  }

  public resetModelState(): void {
    this.pendingRestPoseReset = false;
  }

  public playLoadedAnimation(gltf: GLTF, options: RuntimeRecord): void {
    const playbackId = options.playbackId;
    if (typeof playbackId !== "string" || playbackId.length === 0) {
      throw new TypeError("playbackId must be a non-empty string.");
    }
    const vrm = this.dependencies.getVrm();
    const transitions = this.dependencies.getTransitions();
    if (!vrm || !transitions) {
      throw new Error("Animation mixer is not initialized.");
    }
    const clipName = options.clipName;
    if (clipName != null && typeof clipName !== "string") {
      throw new TypeError("clipName must be a string.");
    }
    const rootMotion = options.rootMotion ?? "inPlace";
    if (rootMotion !== "inPlace" && rootMotion !== "full") {
      throw new TypeError("rootMotion must be inPlace or full.");
    }
    const loop = options.loop ?? true;
    if (typeof loop !== "boolean") {
      throw new TypeError("loop must be a boolean.");
    }
    const speed = options.speed || 1;
    if (typeof speed !== "number") {
      throw new TypeError("speed must be a positive finite number.");
    }
    const fadeDuration = options.fadeDuration ?? 0.5;
    if (typeof fadeDuration !== "number") {
      throw new TypeError("fadeDuration must be a non-negative finite number.");
    }

    let clip: AnimationClip | null = null;
    const vrmAnimations = gltf.userData.vrmAnimations as VRMAnimation[] | undefined;
    if (vrmAnimations && vrmAnimations.length > 0) {
      try {
        const lookAt = vrm.lookAt as RuntimeLookAt | null;
        if (lookAt && !lookAt.quaternionProxy) {
          lookAt.quaternionProxy = new VRMLookAtQuaternionProxy(lookAt);
          lookAt.quaternionProxy.name = "lookAtQuaternionProxy";
          vrm.scene.add(lookAt.quaternionProxy);
        }
        clip = createVRMAnimationClip(vrmAnimations[0]!, vrm);
      } catch (error) {
        console.warn("createVRMAnimationClip error:", error);
      }
    }

    if (!clip && gltf.animations?.length > 0) {
      const sourceClip = typeof clipName === "string" && clipName.length > 0
        ? AnimationClip.findByName(gltf.animations, clipName)
        : gltf.animations[0];
      if (!sourceClip) {
        throw new Error(`Animation clip was not found: ${clipName}`);
      }
      clip = createHumanoidAnimationClip(gltf.scene, sourceClip, vrm, {
        rootMotion,
      });
    }
    if (!clip) throw new Error("No VRMA or glTF animation clip was found.");

    const action = transitions.transitionTo(clip, {
      source: "clip",
      fadeDuration,
      loop,
      speed,
    }) as PlaybackAction;
    action._flutterPlaybackId = playbackId;
    action._hasNotifiedFinished = false;
    this.pendingRestPoseReset = false;
    this.paused = false;
    this.dependencies.resetProceduralMotion();
    transitions.update(0);
    this.dependencies.onStarted({ name: clip.name, playbackId });
  }

  public getPose(): ReturnType<typeof getNormalizedPose> {
    return getNormalizedPose(this.dependencies.getVrm());
  }

  public setPose(pose: unknown, fadeDuration: number): void {
    const vrm = this.dependencies.getVrm();
    const transitions = this.dependencies.getTransitions();
    if (!vrm || !transitions) {
      throw new Error("Load a VRM model before using the Pose API.");
    }
    const clip = createNormalizedPoseClip(
      vrm,
      pose,
      `Pose ${++this.poseSequence}`,
    );
    if (clip.tracks.length === 0) {
      this.transitionToRest(fadeDuration);
    } else {
      transitions.transitionTo(clip, {
        source: "pose",
        fadeDuration,
        loop: true,
        speed: 1,
      });
      this.pendingRestPoseReset = false;
      this.paused = false;
      this.dependencies.resetProceduralMotion();
      transitions.update(0);
    }
    vrm.update(0);
    vrm.scene.updateMatrixWorld(true);
  }

  public transitionToRest(fadeDuration = 0.5): void {
    const vrm = this.dependencies.getVrm();
    const transitions = this.dependencies.getTransitions();
    if (!vrm || !transitions) {
      throw new Error("Load a VRM model before stopping its motion.");
    }
    transitions.transitionToRest(fadeDuration);
    this.pendingRestPoseReset = true;
    this.paused = false;
    this.dependencies.resetProceduralMotion();
    transitions.update(0);
    if (!transitions.isActive) this.finalizeRestPose();
  }

  public pause(): void {
    this.paused = true;
    this.dependencies.getTransitions()?.pause();
  }

  public resume(speed = 1): void {
    this.paused = false;
    this.dependencies.getTransitions()?.resume(speed || 1);
  }

  public setSpeed(speed: number): void {
    this.dependencies.getTransitions()?.setSpeed(speed);
  }

  public update(delta: number): void {
    const transitions = this.dependencies.getTransitions();
    if (!transitions) return;
    transitions.update(delta);
    if (this.pendingRestPoseReset && !transitions.isActive) {
      this.finalizeRestPose();
    }

    // Three.js can occasionally miss the finished event; preserve the
    // playback-scoped fallback used by the runner.
    const action = transitions.currentAction as PlaybackAction | null;
    if (!action || action.isRunning()) return;
    const clip = action.getClip();
    if (!clip || action.time < clip.duration - 0.05) return;
    if (action._hasNotifiedFinished) return;
    const playbackId = action._flutterPlaybackId;
    if (typeof playbackId !== "string" || playbackId.length === 0) return;
    action._hasNotifiedFinished = true;
    this.dependencies.onFinished({ name: clip.name, playbackId });
  }

  private finalizeRestPose(): void {
    this.pendingRestPoseReset = false;
    this.dependencies.finalizeRestPose();
  }
}
