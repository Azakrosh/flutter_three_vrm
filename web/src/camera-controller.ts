import type { VRM } from "@pixiv/three-vrm";
import {
  MathUtils,
  Vector3,
  type PerspectiveCamera,
} from "three";

export type RuntimeCameraMode = "constrained" | "free";

export interface RuntimeCameraTransform {
  readonly x: number;
  readonly y: number;
  readonly zoom: number;
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
  getDistance(): number;
  update(): void;
}

export interface ConstrainedPanInput {
  readonly deltaX: number;
  readonly deltaY: number;
  readonly viewportWidth: number;
  readonly viewportHeight: number;
  readonly startTarget: Vector3;
  readonly modelHeight: number;
}

export class RuntimeCameraController {
  private controls: RuntimeCameraControls;
  private readonly targetPosition = new Vector3();
  private readonly target = new Vector3();
  private readonly startPosition = new Vector3();
  private readonly startTarget = new Vector3();
  private readonly panDelta = new Vector3();
  private animationDuration = 0.5;
  private animationStartTime = 0;
  private animating = false;
  private customTransform = false;

  public constructor(
    private readonly camera: PerspectiveCamera,
    controls: RuntimeCameraControls,
  ) {
    this.controls = controls;
    this.targetPosition.copy(camera.position);
    this.target.copy(controls.target);
    this.applyMode();
  }

  public mode: RuntimeCameraMode = "constrained";

  public get hasCustomTransform(): boolean {
    return this.customTransform;
  }

  public replaceControls(controls: RuntimeCameraControls): void {
    this.controls = controls;
    this.applyMode();
  }

  public markCustomTransform(value = true): void {
    this.customTransform = value;
  }

  public captureControlsTransform(): void {
    this.customTransform = true;
    this.target.copy(this.controls.target);
    this.targetPosition.copy(this.camera.position);
  }

  public clearCustomTransform(): void {
    this.customTransform = false;
  }

  public setMode(mode: string): void {
    if (mode !== "constrained" && mode !== "free") {
      throw new TypeError(`Unknown camera mode: ${mode}`);
    }
    this.mode = mode;
    this.applyMode();
  }

  public applyMode(): void {
    this.controls.enabled = true;
    this.controls.enableZoom = true;
    this.controls.enableDamping = true;
    this.controls.dampingFactor = 0.08;
    if (this.mode === "constrained") {
      this.controls.enablePan = false;
      this.controls.enableRotate = false;
      this.controls.minPolarAngle = Math.PI / 2;
      this.controls.maxPolarAngle = Math.PI / 2;
      this.controls.minAzimuthAngle = 0;
      this.controls.maxAzimuthAngle = 0;
      this.controls.minDistance = 0.5;
      this.controls.maxDistance = 6.6;
    } else {
      this.controls.enablePan = true;
      this.controls.enableRotate = true;
      this.controls.minPolarAngle = 0.01;
      this.controls.maxPolarAngle = Math.PI - 0.01;
      this.controls.minAzimuthAngle = -Infinity;
      this.controls.maxAzimuthAngle = Infinity;
    }
    this.controls.update();
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

    const headNode =
      vrm.humanoid.getNormalizedBoneNode("head") ??
      vrm.humanoid.getRawBoneNode("head");
    let modelHeight = 1.45;
    if (headNode !== null) {
      const headPosition = new Vector3();
      headNode.getWorldPosition(headPosition);
      modelHeight = headPosition.y - vrm.scene.position.y + 0.15;
    }

    const centerY = modelHeight / 2;
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
    this.startTarget.copy(this.controls.target);
    if (!this.customTransform) {
      this.target.set(0, centerY, 0);
      this.targetPosition.set(0, centerY, distance);
    }

    if (durationMs <= 0) {
      this.animating = false;
      this.camera.position.copy(this.targetPosition);
      this.controls.target.copy(this.target);
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
    const distance = this.controls.getDistance();
    const verticalFov = MathUtils.degToRad(this.camera.fov);
    const heightAtDepth = 2 * Math.tan(verticalFov / 2) * distance;
    const widthAtDepth = heightAtDepth * this.camera.aspect;
    const worldDeltaX = input.deltaX / input.viewportWidth * widthAtDepth;
    const worldDeltaY = -input.deltaY / input.viewportHeight * heightAtDepth;
    const clampX = widthAtDepth / 2 + 0.2;
    const minimumY = -0.7 - heightAtDepth / 2;
    const maximumY = input.modelHeight + 0.2 + heightAtDepth / 2;
    this.target.set(
      MathUtils.clamp(input.startTarget.x - worldDeltaX, -clampX, clampX),
      MathUtils.clamp(input.startTarget.y - worldDeltaY, minimumY, maximumY),
      input.startTarget.z,
    );
  }

  public updatePanFollowing(deltaSeconds: number): void {
    if (this.animating) return;
    this.panDelta.copy(this.target).sub(this.controls.target);
    if (this.panDelta.lengthSq() <= 0.000001) return;
    this.panDelta.multiplyScalar(1 - Math.exp(-25 * deltaSeconds));
    this.camera.position.add(this.panDelta);
    this.controls.target.add(this.panDelta);
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
    this.controls.target.lerpVectors(this.startTarget, this.target, eased);
    this.camera.lookAt(this.controls.target);
    if (progress >= 1) {
      this.animating = false;
      this.camera.position.copy(this.targetPosition);
      this.controls.target.copy(this.target);
      this.applyMode();
    }
  }

  public getTransform(): RuntimeCameraTransform {
    return {
      x: -this.target.x,
      y: 0.95 - this.target.y,
      zoom: this.controls.getDistance(),
    };
  }

  public setTransform(value: unknown): void {
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      throw new TypeError("Camera transform must be an object.");
    }
    const transform = value as Record<string, unknown>;
    const x = Number(transform.x);
    const y = Number(transform.y);
    const zoom = Number(transform.zoom);
    if (![x, y, zoom].every(Number.isFinite)) {
      throw new TypeError("Camera transform components must be finite numbers.");
    }
    if (zoom <= 0) {
      throw new TypeError("Camera transform zoom must be positive.");
    }

    this.animating = false;
    this.customTransform = true;
    const targetX = -x;
    const targetY = 0.95 - y;
    this.target.set(targetX, targetY, 0);
    this.controls.target.copy(this.target);
    const distance = MathUtils.clamp(
      zoom,
      this.controls.minDistance,
      this.controls.maxDistance,
    );
    this.camera.position.set(targetX, targetY, distance);
    this.targetPosition.copy(this.camera.position);
    this.controls.update();
  }
}
