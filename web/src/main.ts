import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import {
  VRMLoaderPlugin,
  VRMUtils,
  type VRM,
} from "@pixiv/three-vrm";
import {
  VRMAnimationLoaderPlugin,
  VRMLookAtQuaternionProxy,
  createVRMAnimationClip,
  type VRMAnimation,
} from "@pixiv/three-vrm-animation";

export {
  event,
  failure,
  parseCommand,
  protocolVersion,
  success,
  type CommandEnvelope,
  type EventEnvelope,
  type ResponseEnvelope,
} from "./protocol";

export {
  findRuntimeCommandPayloadError,
  findRuntimeEventPayloadError,
  isRuntimeCommandName,
  isRuntimeEventName,
  runtimeCommandNames,
  runtimeEventNames,
  type RuntimeCommandName,
  type RuntimeCommandPayload,
  type RuntimeCommandPayloadMap,
  type RuntimeCommandRequest,
  type RuntimeEventName,
  type RuntimeEventPayload,
  type RuntimeRecord,
  type RuntimeTypedQueryName,
  type RuntimeTypedQueryResult,
  type RuntimeTypedQueryResultMap,
} from "./protocol-contract";

export {
  createNormalizedPoseClip,
  getNormalizedPose,
  parseNormalizedPose,
  resetNormalizedPose,
  setNormalizedPose,
  type RuntimePose,
} from "./pose";

export {
  createHumanoidAnimationClip,
  type HumanoidAnimationOptions,
} from "./humanoid-animation";

export { RuntimeGazeController } from "./gaze-controller";

export { RuntimeWindPhysicsController } from "./wind-physics-controller";

export { RuntimePointerController } from "./pointer-controller";

export { RuntimeFrameScheduler } from "./frame-scheduler";

export { RuntimePageLifecycle } from "./page-lifecycle";

export {
  AdaptiveQualityController,
  parseAdaptiveQualityConfig,
  type AdaptiveQualityConfig,
  type QualityAdjustment,
} from "./performance";

export {
  MotionTransitionController,
  type MotionSource,
  type MotionTransitionOptions,
} from "./motion-transition";

export {
  RuntimeMotionController,
  type RuntimeMotionDependencies,
  type RuntimeMotionEvent,
} from "./motion-controller";

export {
  SpeechTimeline,
  isSpeechVisemeName,
  type SpeechTimelineMode,
  type SpeechAmplitudeFrame,
  type SpeechTimelineBeginOptions,
  type SpeechTimelineUpdate,
  type SpeechVisemeFrame,
  type SpeechVisemeName,
  type SpeechVisemeUpdate,
} from "./speech-timeline";

export { findSpeechCommandPayloadError } from "./speech-protocol-codec";
export {
  findPoseCameraGraphicsPayloadError,
} from "./pose-camera-graphics-codec";

export {
  RuntimeSpeechController,
  type RuntimeSpeechAmplitudeBatch,
  type RuntimeSpeechBegin,
  type RuntimeSpeechPresentation,
  type RuntimeSpeechVisemeBatch,
} from "./speech-controller";

export {
  RuntimeFaceController,
  type RuntimeFaceDependencies,
} from "./face-controller";

export {
  createRuntimeCommandResponse,
  installRuntimeBridge,
  postRuntimeEvent,
  type RuntimeBridgeOptions,
  type RuntimeCommandExecutor,
} from "./runtime-bridge";

export {
  createRuntimeCommandDispatcher,
  type RuntimeCommandDispatcher,
  type RuntimeCommandHost,
} from "./command-dispatcher";

export {
  createRuntimeCanceledError,
  fetchRuntimeResource,
  isRuntimeCanceledError,
  type RuntimeCanceledError,
  type RuntimeResource,
  type RuntimeResourceProgress,
} from "./resource-loader";

export {
  VrmModelLoader,
  type LoadedVrmDocument,
  type VrmModelLoaderDependencies,
  type VrmModelLoadProgress,
} from "./model-loader";

export {
  VrmAnimationLoader,
  type VrmAnimationLoaderDependencies,
} from "./animation-loader";

export {
  createRuntimeModelReport,
  type RuntimeModelReport,
} from "./model-report";

export {
  VrmModelSession,
  type ModelAnimationFinished,
  type VrmModelAttachOptions,
  type VrmModelSessionDependencies,
} from "./model-session";

export {
  RuntimeCameraController,
  parseRuntimeCameraTransform,
  type ConstrainedPanInput,
  type RuntimeCameraControls,
  type RuntimeCameraMode,
  type RuntimeCameraTransform,
} from "./camera-controller";

export {
  RuntimeSceneController,
  type RuntimeLightingConfig,
  type RuntimeSceneControllerOptions,
  type RuntimeViewport,
} from "./scene-controller";

export {
  RuntimeBackgroundController,
  type RuntimeBackgroundDependencies,
  type RuntimeBackgroundStyle,
} from "./background-controller";

export {
  RuntimeGraphicsController,
  parseRuntimeGraphicsSettings,
  type RuntimeGraphicsPreset,
  type RuntimeGraphicsDependencies,
  type RuntimeGraphicsSettings,
  type RuntimePerformanceSnapshot,
} from "./graphics-controller";

export {
  GLTFLoader,
  OrbitControls,
  THREE,
  VRMAnimationLoaderPlugin,
  VRMLoaderPlugin,
  VRMLookAtQuaternionProxy,
  VRMUtils,
  createVRMAnimationClip,
};
declare const __RUNTIME_VERSION__: string;
declare const __THREE_VRM_VERSION__: string;

export interface RuntimeInfo {
  readonly runtimeVersion: string;
  readonly threeRevision: string;
  readonly threeVrmVersion: string;
  readonly protocolVersion: number;
}

export function getRuntimeInfo(): RuntimeInfo {
  return {
    runtimeVersion: __RUNTIME_VERSION__,
    threeRevision: THREE.REVISION,
    threeVrmVersion: __THREE_VRM_VERSION__,
    protocolVersion: 3,
  };
}

export function createVrmLoader(
  manager: THREE.LoadingManager = THREE.DefaultLoadingManager,
): GLTFLoader {
  const loader = new GLTFLoader(manager);
  loader.register((parser) => new VRMLoaderPlugin(parser));
  return loader;
}

export function createVrmAnimationLoader(
  manager: THREE.LoadingManager = THREE.DefaultLoadingManager,
): GLTFLoader {
  const loader = new GLTFLoader(manager);
  loader.register((parser) => new VRMAnimationLoaderPlugin(parser));
  return loader;
}

// These assignments intentionally prove the public v3 types during typecheck.
export type LoadedVrm = VRM;
export type LoadedVrmAnimation = VRMAnimation;
