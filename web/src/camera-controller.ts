import type { VRM, VRMHumanBoneName } from "@pixiv/three-vrm";
import {
  MathUtils,
  Quaternion,
  Vector2,
  Vector3,
  type PerspectiveCamera,
} from "three";

export type RuntimeCameraMode = "constrained" | "free";

export interface RuntimeCameraTransform {
  readonly x: number;
  readonly y: number;
  readonly zoom: number;
}

export function parseRuntimeCameraTransform(
  value: unknown,
): RuntimeCameraTransform {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TypeError("Camera transform must be an object.");
  }
  const transform = value as Record<string, unknown>;
  const { x, y, zoom } = transform;
  if (
    typeof x !== "number" ||
    typeof y !== "number" ||
    typeof zoom !== "number" ||
    ![x, y, zoom].every(Number.isFinite)
  ) {
    throw new TypeError("Camera transform components must be finite numbers.");
  }
  if (zoom <= 0) {
    throw new TypeError("Camera transform zoom must be positive.");
  }
  return { x, y, zoom };
}

export interface RuntimeCameraControls {
  readonly target: Vector3;
  enabled: boolean;
  enablePan: boolean;
  enableRotate: boolean;
  enableZoom: boolean;
  minPolarAngle: number;
  maxPolarAngle: number;
  minAzimuthAngle: number;
  maxAzimuthAngle: number;
  minDistance: number;
  maxDistance: number;
  enableDamping: boolean;
  dampingFactor: number;
  screenSpacePanning: boolean;
  getDistance(): number;
  update(): void;
}

export interface ConstrainedPanInput {
  readonly deltaX: number;
  readonly deltaY: number;
  readonly viewportWidth: number;
  readonly viewportHeight: number;
  readonly startPan: Vector2;
  readonly modelHeight: number;
}

const EPSILON_SQUARED = 1e-12;
const MIN_CAMERA_DISTANCE = 0.5;
const MAX_CAMERA_DISTANCE = 6.6;
const MIN_CONSTRAINED_FOCUS_CLEARANCE = 0.4;

/**
 * Owns the avatar camera rig.
 *
 * Pan always translates the complete camera rig instead of shifting its
 * projection matrix. This preserves perspective at close zoom, while free mode
 * additionally lets OrbitControls rotate the translated rig.
 */
export class RuntimeCameraController {
  private controls: RuntimeCameraControls;
  private readonly orbitPivot = new Vector3();
  private readonly focusAnchor = new Vector3();
  private readonly displayedFocusAnchor = new Vector3();
  private readonly startFocusAnchor = new Vector3();
  private readonly targetPosition = new Vector3();
  private readonly startPosition = new Vector3();
  private readonly startPivot = new Vector3();
  private readonly nativePanDelta = new Vector3();
  private readonly cameraRight = new Vector3();
  private readonly cameraUp = new Vector3();
  private readonly panTranslation = new Vector3();
  private readonly aimTarget = new Vector3();
  private readonly renderPosition = new Vector3();
  private readonly renderQuaternion = new Quaternion();
  private readonly orbitDirection = new Vector3();
  private readonly preZoomPosition = new Vector3();
  private readonly focusDirection = new Vector3();
  private readonly panOffset = new Vector2();
  private readonly displayedPanOffset = new Vector2();
  private readonly startPanOffset = new Vector2();
  private animationDuration = 0.5;
  private animationStartTime = 0;
  private animating = false;
  private customTransform = false;
  private lastControlsDistance = Number.NaN;
  private renderPresentationApplied = false;

  public constructor(
    private readonly camera: PerspectiveCamera,
    controls: RuntimeCameraControls,
  ) {
    this.controls = controls;
    this.orbitPivot.copy(controls.target);
    this.focusAnchor.copy(controls.target);
    this.displayedFocusAnchor.copy(controls.target);
    this.startFocusAnchor.copy(controls.target);
    this.targetPosition.copy(camera.position);
    this.applyMode();
  }

  public mode: RuntimeCameraMode = "constrained";

  public get hasCustomTransform(): boolean {
    return this.customTransform;
  }

  public getPanOffset(): Vector2 {
    return this.panOffset.clone();
  }

  public replaceControls(controls: RuntimeCameraControls): void {
    this.restoreRenderPresentation();
    this.controls = controls;
    this.controls.target.copy(this.orbitPivot);
    if (this.mode === "constrained") {
      this.controls.target.add(
        this.getConstrainedPanTranslation(this.panTranslation),
      );
    }
    this.applyMode();
  }

  public markCustomTransform(value = true): void {
    this.customTransform = value;
  }

  public captureControlsTransform(): void {
    this.customTransform = true;
    if (this.mode === "constrained") {
      this.stabilizeConstrainedCamera();
    } else {
      this.captureNativePan();
      this.correctZoomTowardFocus();
    }
    this.targetPosition.copy(this.camera.position);
    this.applyPanPresentation();
  }

  public clearCustomTransform(): void {
    this.restoreRenderPresentation();
    this.customTransform = false;
    if (this.mode === "constrained") {
      this.camera.position.sub(
        this.getConstrainedPanTranslation(this.panTranslation),
      );
    }
    this.panOffset.set(0, 0);
    this.displayedPanOffset.set(0, 0);
    this.controls.target.copy(this.orbitPivot);
    if (this.mode === "constrained") {
      this.stabilizeConstrainedCamera();
    } else {
      this.camera.lookAt(this.displayedFocusAnchor);
      this.targetPosition.copy(this.camera.position);
    }
    this.applyPanPresentation();
  }

  public setMode(mode: string): void {
    if (mode !== "constrained" && mode !== "free") {
      throw new TypeError(`Unknown camera mode: ${mode}`);
    }
    this.restoreRenderPresentation();
    if (mode === this.mode) {
      if (mode === "free") this.captureNativePan();
      this.applyMode();
      return;
    }

    if (this.mode === "free") {
      this.captureNativePan();
    } else {
      this.camera.position.sub(
        this.getConstrainedPanTranslation(this.panTranslation),
      );
      this.controls.target.copy(this.orbitPivot);
    }
    this.mode = mode;
    this.targetPosition.copy(this.camera.position);
    this.applyMode();
  }

  public applyMode(): void {
    this.controls.enabled = true;
    this.controls.enableZoom = true;
    // Pointer-controlled camera movement must stop when the gesture ends.
    this.controls.enableDamping = false;
    this.controls.dampingFactor = 0;
    this.controls.screenSpacePanning = true;
    if (this.mode === "constrained") {
      this.controls.enablePan = false;
      this.controls.enableRotate = false;
      this.controls.minDistance = this.getConstrainedMinDistance();
      this.controls.maxDistance = MAX_CAMERA_DISTANCE;
    } else {
      // Native OrbitControls pan physically translates both camera and target.
      this.controls.enablePan = true;
      this.controls.enableRotate = true;
      this.controls.minDistance = MIN_CAMERA_DISTANCE;
      this.controls.maxDistance = MAX_CAMERA_DISTANCE;
      this.controls.minPolarAngle = 0.01;
      this.controls.maxPolarAngle = Math.PI - 0.01;
      this.controls.minAzimuthAngle = -Infinity;
      this.controls.maxAzimuthAngle = Infinity;
    }
    if (this.mode === "constrained") {
      this.stabilizeConstrainedCamera();
    } else {
      this.controls.target.copy(this.orbitPivot);
    }
    this.controls.update();
    this.lastControlsDistance = this.controls.getDistance();
    if (this.mode === "constrained") {
      this.prepareForRender();
    } else {
      this.restoreRenderPresentation();
      this.camera.lookAt(this.displayedFocusAnchor);
      this.applyPanPresentation();
    }
  }

  /** Applies render-only framing after OrbitControls updates its base rig. */
  public prepareForRender(): void {
    this.restoreRenderPresentation();
    if (this.mode === "constrained") {
      if (!this.animating) this.stabilizeConstrainedCamera();
      this.camera.lookAt(this.getDisplayedAimTarget(this.aimTarget));
    } else {
      this.renderPosition.copy(this.camera.position);
      this.renderQuaternion.copy(this.camera.quaternion);
      this.camera.lookAt(this.displayedFocusAnchor);
      this.getFreePanTranslation(this.panTranslation);
      this.camera.position.add(this.panTranslation);
      this.camera.lookAt(
        this.aimTarget
          .copy(this.displayedFocusAnchor)
          .add(this.panTranslation),
      );
      this.camera.updateMatrixWorld(true);
      this.renderPresentationApplied = true;
    }
    this.applyPanPresentation();
  }

  /** Restores the control camera immediately after the renderer consumed it. */
  public finishRender(): void {
    this.restoreRenderPresentation();
  }

  public frameAvatar(
    vrm: VRM | null,
    elapsedTime: number,
    durationMs = 500,
    resetPosition = true,
  ): boolean {
    if (!vrm?.humanoid) return false;
    if (resetPosition) {
      vrm.scene.position.set(0, 0, 0);
      vrm.springBoneManager?.reset();
    }
    vrm.scene.updateMatrixWorld(true);
    this.controls.enabled = false;

    const headPosition = readBoneWorldPosition(vrm, ["head"]);
    let modelHeight = 1.45;
    if (headPosition !== null) {
      modelHeight = headPosition.y - vrm.scene.position.y + 0.15;
    }
    const nextPivot = calculateAvatarOrbitPivot(vrm, modelHeight);
    const nextFocusAnchor = calculateAvatarFocusAnchor(vrm, modelHeight);

    const verticalFov = MathUtils.degToRad(this.camera.fov);
    const targetFrustumHeight = modelHeight / 0.8;
    let distance = targetFrustumHeight / 2 / Math.tan(verticalFov / 2);
    if (this.camera.aspect < 1) {
      const targetFrustumWidth = modelHeight * 0.5;
      const distanceForWidth =
        targetFrustumWidth /
        2 /
        (Math.tan(verticalFov / 2) * this.camera.aspect);
      distance = Math.max(distance, distanceForWidth);
    }

    this.startPosition.copy(this.camera.position);
    this.startPivot.copy(this.controls.target);
    this.startFocusAnchor.copy(this.displayedFocusAnchor);
    this.startPanOffset.copy(this.displayedPanOffset);
    const pivotDelta = nextPivot.clone().sub(this.orbitPivot);
    this.orbitPivot.copy(nextPivot);
    this.focusAnchor.copy(nextFocusAnchor);
    if (!this.customTransform) {
      this.panOffset.set(0, 0);
      this.targetPosition.set(
        this.focusAnchor.x,
        this.focusAnchor.y,
        this.focusAnchor.z + 1,
      );
      positionAtOrbitDistance(
        this.targetPosition,
        this.focusAnchor,
        this.orbitPivot,
        distance,
      );
    } else {
      // A transform may be restored before the replacement model is framed.
      // Move the camera with the new humanoid pivot to preserve its angle and
      // distance instead of orbiting the new avatar around the old model.
      this.panTranslation.set(0, 0, 0);
      if (this.mode === "constrained") {
        this.getConstrainedPanTranslation(this.panTranslation);
      }
      this.targetPosition
        .copy(this.camera.position)
        .sub(this.panTranslation)
        .add(pivotDelta);
      positionAtOrbitDistance(
        this.targetPosition,
        this.focusAnchor,
        this.orbitPivot,
        this.controls.getDistance(),
      );
      if (this.mode === "constrained") {
        this.targetPosition.add(this.panTranslation);
      }
    }

    if (durationMs <= 0) {
      this.animating = false;
      this.camera.position.copy(this.targetPosition);
      this.displayedFocusAnchor.copy(this.focusAnchor);
      this.displayedPanOffset.copy(this.panOffset);
      this.controls.target.copy(this.orbitPivot);
      if (this.mode === "constrained") {
        this.controls.target.add(
          this.getConstrainedPanTranslation(this.panTranslation),
        );
      }
      this.applyMode();
    } else {
      this.animating = true;
      this.animationDuration = durationMs / 1000;
      this.animationStartTime = elapsedTime;
    }
    return true;
  }

  public reset(vrm: VRM | null, durationMs: number, elapsedTime: number): boolean {
    const duration = Number(durationMs);
    if (!Number.isFinite(duration) || duration < 0) {
      throw new TypeError("Camera reset duration must be a non-negative number.");
    }
    this.customTransform = false;
    return this.frameAvatar(vrm, elapsedTime, duration, false);
  }

  public setConstrainedPanTarget(input: ConstrainedPanInput): void {
    if (this.mode !== "constrained") return;
    this.customTransform = true;
    const distance = this.camera.position.distanceTo(
      this.getDisplayedAimTarget(this.aimTarget),
    );
    const verticalFov = MathUtils.degToRad(this.camera.fov);
    const heightAtDepth = 2 * Math.tan(verticalFov / 2) * distance;
    const widthAtDepth = heightAtDepth * this.camera.aspect;
    const worldDeltaX = input.deltaX / input.viewportWidth * widthAtDepth;
    const worldDeltaY = -input.deltaY / input.viewportHeight * heightAtDepth;
    const clampX = widthAtDepth / 2 + 0.2;
    const clampY = input.modelHeight / 2 + heightAtDepth / 2 + 0.2;
    this.panOffset.set(
      MathUtils.clamp(input.startPan.x + worldDeltaX, -clampX, clampX),
      MathUtils.clamp(input.startPan.y + worldDeltaY, -clampY, clampY),
    );
  }

  public updatePanFollowing(deltaSeconds: number): void {
    if (this.animating) return;
    if (this.mode === "free") {
      this.captureNativePan();
      this.displayedPanOffset.copy(this.panOffset);
    } else {
      const factor = 1 - Math.exp(-25 * deltaSeconds);
      this.displayedPanOffset.lerp(this.panOffset, factor);
    }
    if (this.mode === "constrained") {
      this.stabilizeConstrainedCamera();
    } else {
      this.correctZoomTowardFocus();
    }
    this.applyPanPresentation();
  }

  public updateAnimation(elapsedTime: number): void {
    if (!this.animating) return;
    const progress = Math.min(
      (elapsedTime - this.animationStartTime) / this.animationDuration,
      1,
    );
    const eased = 0.5 - Math.cos(progress * Math.PI) / 2;
    this.camera.position.lerpVectors(
      this.startPosition,
      this.targetPosition,
      eased,
    );
    this.displayedFocusAnchor.lerpVectors(
      this.startFocusAnchor,
      this.focusAnchor,
      eased,
    );
    this.displayedPanOffset.lerpVectors(
      this.startPanOffset,
      this.panOffset,
      eased,
    );
    this.aimTarget.copy(this.orbitPivot);
    if (this.mode === "constrained") {
      this.aimTarget.add(
        this.getConstrainedPanTranslation(this.panTranslation),
      );
    }
    this.controls.target.lerpVectors(this.startPivot, this.aimTarget, eased);
    if (this.mode === "constrained") {
      this.camera.lookAt(this.getDisplayedAimTarget(this.aimTarget));
      this.lockConstrainedOrbitAngles();
    } else {
      this.camera.lookAt(this.displayedFocusAnchor);
    }
    this.applyPanPresentation();
    if (progress >= 1) {
      this.animating = false;
      this.camera.position.copy(this.targetPosition);
      this.displayedFocusAnchor.copy(this.focusAnchor);
      this.displayedPanOffset.copy(this.panOffset);
      this.controls.target.copy(this.orbitPivot);
      if (this.mode === "constrained") {
        this.controls.target.add(
          this.getConstrainedPanTranslation(this.panTranslation),
        );
      }
      this.applyMode();
    }
  }

  public getTransform(): RuntimeCameraTransform {
    return {
      x: this.panOffset.x,
      y: this.panOffset.y,
      zoom: this.controls.getDistance(),
    };
  }

  public setTransform(value: unknown): void {
    const { x, y, zoom } = parseRuntimeCameraTransform(value);

    this.restoreRenderPresentation();
    this.animating = false;
    this.customTransform = true;
    if (this.mode === "free") {
      this.captureNativePan();
    } else {
      this.camera.position.sub(
        this.getConstrainedPanTranslation(this.panTranslation),
      );
    }

    this.panOffset.set(x, y);
    this.displayedPanOffset.copy(this.panOffset);
    this.controls.target.copy(this.orbitPivot);

    const distance = MathUtils.clamp(
      zoom,
      this.controls.minDistance,
      this.controls.maxDistance,
    );
    this.targetPosition.copy(this.camera.position);
    positionAtOrbitDistance(
      this.targetPosition,
      this.displayedFocusAnchor,
      this.orbitPivot,
      distance,
    );
    if (this.mode === "constrained") {
      this.getConstrainedPanTranslation(this.panTranslation);
      this.targetPosition.add(this.panTranslation);
      this.controls.target.add(this.panTranslation);
    }
    this.camera.position.copy(this.targetPosition);
    this.controls.update();
    this.lastControlsDistance = this.controls.getDistance();
    if (this.mode === "constrained") {
      this.prepareForRender();
    } else {
      this.camera.lookAt(this.displayedFocusAnchor);
      this.applyPanPresentation();
    }
  }

  /** Captures native pan as framing while keeping the torso orbit pivot fixed. */
  private captureNativePan(): void {
    if (this.mode !== "free") return;
    this.nativePanDelta.copy(this.controls.target).sub(this.orbitPivot);
    if (this.nativePanDelta.lengthSq() <= EPSILON_SQUARED) {
      this.controls.target.copy(this.orbitPivot);
      return;
    }

    this.cameraRight.set(1, 0, 0).applyQuaternion(this.camera.quaternion);
    this.cameraUp.set(0, 1, 0).applyQuaternion(this.camera.quaternion);
    this.panOffset.x -= this.nativePanDelta.dot(this.cameraRight);
    this.panOffset.y -= this.nativePanDelta.dot(this.cameraUp);
    this.displayedPanOffset.copy(this.panOffset);

    // OrbitControls physically pans camera and target. Move both back to their
    // base rig; the same displacement is applied only during rendering.
    this.camera.position.sub(this.nativePanDelta);
    this.controls.target.copy(this.orbitPivot);
    this.targetPosition.copy(this.camera.position);
  }

  /** Keeps constrained zoom front-facing while its orbit pivot stays at torso. */
  private stabilizeConstrainedCamera(): void {
    this.controls.minDistance = this.getConstrainedMinDistance();
    const requestedDistance = MathUtils.clamp(
      this.controls.getDistance(),
      this.controls.minDistance,
      this.controls.maxDistance,
    );
    const offsetX = this.displayedFocusAnchor.x - this.orbitPivot.x;
    const offsetY = this.displayedFocusAnchor.y - this.orbitPivot.y;
    const perpendicularSquared = offsetX * offsetX + offsetY * offsetY;
    const forwardDistance = Math.max(
      1e-6,
      this.orbitPivot.z - this.displayedFocusAnchor.z +
        Math.sqrt(
          Math.max(
            0,
            requestedDistance * requestedDistance - perpendicularSquared,
          ),
        ),
    );
    this.camera.position.set(
      this.displayedFocusAnchor.x,
      this.displayedFocusAnchor.y,
      this.displayedFocusAnchor.z + forwardDistance,
    );
    this.getConstrainedPanTranslation(this.panTranslation);
    this.camera.position.add(this.panTranslation);
    this.controls.target.copy(this.orbitPivot).add(this.panTranslation);
    this.targetPosition.copy(this.camera.position);

    this.lockConstrainedOrbitAngles();
    this.lastControlsDistance = this.controls.getDistance();
  }

  /** Keeps the camera safely in front of the focus at maximum zoom. */
  private getConstrainedMinDistance(): number {
    const offsetX = this.displayedFocusAnchor.x - this.orbitPivot.x;
    const offsetY = this.displayedFocusAnchor.y - this.orbitPivot.y;
    const cameraOffsetZ =
      this.displayedFocusAnchor.z +
      MIN_CONSTRAINED_FOCUS_CLEARANCE -
      this.orbitPivot.z;
    return Math.max(
      MIN_CAMERA_DISTANCE,
      Math.hypot(offsetX, offsetY, cameraOffsetZ),
    );
  }

  /** Locks a non-rotating rig without forcing it onto the torso horizon. */
  private lockConstrainedOrbitAngles(): void {
    this.orbitDirection.copy(this.camera.position).sub(this.controls.target);
    const actualDistance = Math.max(this.orbitDirection.length(), 1e-6);
    const polarAngle = Math.acos(
      MathUtils.clamp(this.orbitDirection.y / actualDistance, -1, 1),
    );
    const azimuthAngle = Math.atan2(
      this.orbitDirection.x,
      this.orbitDirection.z,
    );
    this.controls.minPolarAngle = polarAngle;
    this.controls.maxPolarAngle = polarAngle;
    this.controls.minAzimuthAngle = azimuthAngle;
    this.controls.maxAzimuthAngle = azimuthAngle;
  }

  /** Replaces OrbitControls' torso-directed dolly with a face-directed dolly. */
  private correctZoomTowardFocus(): void {
    const currentDistance = this.controls.getDistance();
    if (!Number.isFinite(this.lastControlsDistance)) {
      this.lastControlsDistance = currentDistance;
      return;
    }
    if (Math.abs(currentDistance - this.lastControlsDistance) <= 1e-9) return;

    this.orbitDirection.copy(this.camera.position).sub(this.orbitPivot);
    if (this.orbitDirection.lengthSq() <= EPSILON_SQUARED) {
      this.orbitDirection.set(0, 0, 1);
    } else {
      this.orbitDirection.normalize();
    }
    this.preZoomPosition
      .copy(this.orbitDirection)
      .multiplyScalar(this.lastControlsDistance)
      .add(this.orbitPivot);
    this.focusDirection
      .copy(this.preZoomPosition)
      .sub(this.displayedFocusAnchor);
    if (this.focusDirection.lengthSq() <= EPSILON_SQUARED) {
      this.focusDirection.set(0, 0, 1);
    }
    this.camera.position
      .copy(this.displayedFocusAnchor)
      .add(this.focusDirection.normalize());
    positionAtOrbitDistance(
      this.camera.position,
      this.displayedFocusAnchor,
      this.orbitPivot,
      currentDistance,
    );
    this.controls.target.copy(this.orbitPivot);
    this.targetPosition.copy(this.camera.position);
    this.lastControlsDistance = this.controls.getDistance();
  }

  private applyPanPresentation(): void {
    if (this.camera.view?.enabled) this.camera.clearViewOffset();
  }

  private getConstrainedPanTranslation(target: Vector3): Vector3 {
    return target.set(
      -this.displayedPanOffset.x,
      -this.displayedPanOffset.y,
      0,
    );
  }

  private getFreePanTranslation(target: Vector3): Vector3 {
    this.cameraRight.set(1, 0, 0).applyQuaternion(this.camera.quaternion);
    this.cameraUp.set(0, 1, 0).applyQuaternion(this.camera.quaternion);
    return target
      .copy(this.cameraRight)
      .multiplyScalar(-this.displayedPanOffset.x)
      .addScaledVector(this.cameraUp, -this.displayedPanOffset.y);
  }

  private getDisplayedAimTarget(target: Vector3): Vector3 {
    return target
      .copy(this.displayedFocusAnchor)
      .add(this.getConstrainedPanTranslation(this.panTranslation));
  }

  private restoreRenderPresentation(): void {
    if (!this.renderPresentationApplied) return;
    this.camera.position.copy(this.renderPosition);
    this.camera.quaternion.copy(this.renderQuaternion);
    this.camera.updateMatrixWorld(true);
    this.renderPresentationApplied = false;
  }
}

function calculateAvatarOrbitPivot(vrm: VRM, modelHeight: number): Vector3 {
  const hips = readBoneWorldPosition(vrm, ["hips"]);
  const upperTorso = readBoneWorldPosition(vrm, [
    "upperChest",
    "chest",
    "spine",
  ]);
  if (hips !== null && upperTorso !== null) {
    return new Vector3().lerpVectors(hips, upperTorso, 0.5);
  }
  if (upperTorso !== null) return upperTorso;

  const head = readBoneWorldPosition(vrm, ["head"]);
  if (hips !== null && head !== null) {
    return new Vector3().lerpVectors(hips, head, 0.35);
  }
  if (hips !== null) return hips;
  if (head !== null) {
    head.y -= modelHeight * 0.3;
    return head;
  }

  const fallback = new Vector3();
  vrm.scene.getWorldPosition(fallback);
  fallback.y += modelHeight * 0.55;
  return fallback;
}

function calculateAvatarFocusAnchor(vrm: VRM, modelHeight: number): Vector3 {
  const leftEye = readBoneWorldPosition(vrm, ["leftEye"]);
  const rightEye = readBoneWorldPosition(vrm, ["rightEye"]);
  if (leftEye !== null && rightEye !== null) {
    return new Vector3().addVectors(leftEye, rightEye).multiplyScalar(0.5);
  }
  if (leftEye !== null) return leftEye;
  if (rightEye !== null) return rightEye;
  const head = readBoneWorldPosition(vrm, ["head"]);
  if (head !== null) {
    head.y += modelHeight * 0.05;
    return head;
  }
  return calculateAvatarOrbitPivot(vrm, modelHeight);
}

function positionAtOrbitDistance(
  position: Vector3,
  focusAnchor: Vector3,
  orbitPivot: Vector3,
  distance: number,
): void {
  const direction = position.clone().sub(focusAnchor);
  if (direction.lengthSq() <= EPSILON_SQUARED) direction.set(0, 0, 1);
  direction.normalize();
  const focusOffset = focusAnchor.clone().sub(orbitPivot);
  const alongOffset = focusOffset.dot(direction);
  const discriminant = Math.max(
    0,
    alongOffset * alongOffset + distance * distance - focusOffset.lengthSq(),
  );
  const focusDistance = Math.max(1e-6, -alongOffset + Math.sqrt(discriminant));
  position.copy(focusAnchor).addScaledVector(direction, focusDistance);
}

function readBoneWorldPosition(
  vrm: VRM,
  names: readonly VRMHumanBoneName[],
): Vector3 | null {
  for (const name of names) {
    const node = vrm.humanoid.getNormalizedBoneNode(name) ??
      vrm.humanoid.getRawBoneNode(name);
    if (node === null) continue;
    const position = new Vector3();
    node.getWorldPosition(position);
    if ([position.x, position.y, position.z].every(Number.isFinite)) {
      return position;
    }
  }
  return null;
}
