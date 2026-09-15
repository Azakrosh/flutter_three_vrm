import {
  AnimationAction,
  AnimationClip,
  AnimationMixer,
  LoopOnce,
  LoopRepeat,
} from "three";

export type MotionSource = "clip" | "pose";

export interface MotionTransitionOptions {
  readonly source: MotionSource;
  readonly fadeDuration?: number;
  readonly loop?: boolean;
  readonly speed?: number;
}

interface RetiringAction {
  readonly action: AnimationAction;
  remainingSeconds: number;
}

/** Owns every mixer action so clips and static poses share one crossfade path. */
export class MotionTransitionController {
  private readonly retiringActions: RetiringAction[] = [];

  public constructor(private readonly mixer: AnimationMixer) {}

  public currentAction: AnimationAction | null = null;
  public currentSource: MotionSource | null = null;
  public isPaused = false;

  public get isActive(): boolean {
    return this.currentAction !== null || this.retiringActions.length > 0;
  }

  public transitionTo(
    clip: AnimationClip,
    options: MotionTransitionOptions,
  ): AnimationAction {
    const fadeDuration = readFadeDuration(options.fadeDuration);
    const speed = readSpeed(options.speed);
    const previous = this.currentAction;
    const next = this.mixer.clipAction(clip);

    this.mixer.timeScale = 1;
    this.isPaused = false;
    next.reset();
    next.enabled = true;
    next.setEffectiveWeight(1);
    next.setEffectiveTimeScale(speed);
    next.setLoop(options.loop === false ? LoopOnce : LoopRepeat, Infinity);
    next.clampWhenFinished = options.loop === false;
    next.play();

    if (previous !== null) {
      if (fadeDuration === 0) {
        this.disposeAction(previous);
      } else {
        previous.crossFadeTo(next, fadeDuration, false);
        this.retiringActions.push({
          action: previous,
          remainingSeconds: fadeDuration,
        });
      }
    } else if (fadeDuration > 0) {
      next.fadeIn(fadeDuration);
    }

    this.currentAction = next;
    this.currentSource = options.source;
    return next;
  }

  public transitionToRest(fadeDuration = 0.5): void {
    const duration = readFadeDuration(fadeDuration);
    const current = this.currentAction;
    this.mixer.timeScale = 1;
    this.isPaused = false;
    this.currentAction = null;
    this.currentSource = null;

    if (current === null) return;
    if (duration === 0) {
      this.disposeAction(current);
    } else {
      current.fadeOut(duration);
      this.retiringActions.push({
        action: current,
        remainingSeconds: duration,
      });
    }
  }

  public pause(): void {
    this.isPaused = true;
    this.mixer.timeScale = 0;
  }

  public resume(speed = 1): void {
    this.setSpeed(speed);
    this.isPaused = false;
    this.mixer.timeScale = 1;
  }

  public setSpeed(speed: number): void {
    const value = readSpeed(speed);
    this.currentAction?.setEffectiveTimeScale(value);
  }

  public update(deltaSeconds: number): void {
    this.mixer.update(deltaSeconds);
    if (this.mixer.timeScale === 0 || this.retiringActions.length === 0) return;

    const elapsed = deltaSeconds * Math.abs(this.mixer.timeScale);
    for (let index = this.retiringActions.length - 1; index >= 0; index -= 1) {
      const retiring = this.retiringActions[index];
      if (retiring === undefined) continue;
      retiring.remainingSeconds -= elapsed;
      if (retiring.remainingSeconds <= 0) {
        this.retiringActions.splice(index, 1);
        this.disposeAction(retiring.action);
      }
    }
  }

  public dispose(): void {
    const actions = new Set<AnimationAction>([
      ...(this.currentAction === null ? [] : [this.currentAction]),
      ...this.retiringActions.map((entry) => entry.action),
    ]);
    for (const action of actions) this.disposeAction(action);
    this.retiringActions.length = 0;
    this.currentAction = null;
    this.currentSource = null;
    this.isPaused = false;
    this.mixer.timeScale = 1;
  }

  private disposeAction(action: AnimationAction): void {
    const clip = action.getClip();
    action.stop();
    this.mixer.uncacheClip(clip);
  }
}

function readFadeDuration(value = 0.5): number {
  if (!Number.isFinite(value) || value < 0) {
    throw new TypeError("fadeDuration must be a non-negative finite number.");
  }
  return value;
}

function readSpeed(value = 1): number {
  if (!Number.isFinite(value) || value <= 0) {
    throw new TypeError("speed must be a positive finite number.");
  }
  return value;
}
