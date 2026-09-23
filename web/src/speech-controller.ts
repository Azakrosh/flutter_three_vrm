import { MathUtils } from "three";
import type { RuntimeExpressionName } from "./interaction-protocol-codec";

import {
  SpeechTimeline,
  type SpeechAmplitudeFrame,
  type SpeechTimelineMode,
  type SpeechVisemeFrame,
} from "./speech-timeline";

export interface RuntimeSpeechBegin {
  readonly speechRevision: number;
  readonly sessionId: string;
  readonly mode: SpeechTimelineMode;
  readonly timelineOriginEpochMs: number;
}

export interface RuntimeSpeechVisemeBatch extends RuntimeSpeechBegin {
  readonly frames: readonly SpeechVisemeFrame[];
}

export interface RuntimeSpeechAmplitudeBatch extends RuntimeSpeechBegin {
  readonly frames: readonly SpeechAmplitudeFrame[];
}

export interface RuntimeSpeechPresentation {
  readonly clearMouth: () => void;
  readonly setMouthExpression: (
    name: RuntimeExpressionName,
    weight: number,
    durationSeconds: number,
  ) => void;
  readonly onFinished: (sessionId: string) => void;
  readonly nowMs?: () => number;
  readonly wallNowEpochMs?: () => number;
}

const visemeMap: Readonly<Record<string, RuntimeExpressionName>> = {
  aa: "aa", ih: "ih", ou: "ou", ee: "ee", oh: "oh",
  AA: "aa", IH: "ih", OU: "ou", EE: "ee", OH: "oh",
};

export class RuntimeSpeechController {
  public readonly timeline = new SpeechTimeline();
  private amplitudeValue = 0;
  private smoothAmplitudeValue = 0;

  public constructor(private readonly presentation: RuntimeSpeechPresentation) {}

  public get amplitude(): number {
    return this.amplitudeValue;
  }

  public setAmplitude(amplitude: number): void {
    this.amplitudeValue = amplitude;
  }

  public resetAmplitude(): void {
    this.amplitudeValue = 0;
    this.smoothAmplitudeValue = 0;
  }

  public begin(payload: RuntimeSpeechBegin): boolean {
    if (!this.timeline.acceptInputRevision(payload.speechRevision)) return false;
    this.timeline.begin({
      sessionId: payload.sessionId,
      mode: payload.mode,
      timelineOriginEpochMs: payload.timelineOriginEpochMs,
      nowMs: this.now(),
      wallNowEpochMs: this.presentation.wallNowEpochMs?.() ?? Date.now(),
    });
    this.resetPresentation();
    return true;
  }

  public appendVisemes(
    sessionId: string,
    frames: readonly SpeechVisemeFrame[],
  ): boolean {
    return this.timeline.appendVisemes(sessionId, frames);
  }

  public appendAmplitudes(
    sessionId: string,
    frames: readonly SpeechAmplitudeFrame[],
  ): boolean {
    return this.timeline.appendAmplitudes(sessionId, frames);
  }

  public finish(sessionId: string, audioDurationMs: number): boolean {
    return this.timeline.finish(sessionId, audioDurationMs);
  }

  public cancel(sessionId?: string): boolean {
    const canceled = this.timeline.cancel(sessionId);
    if (sessionId !== undefined && !canceled) return false;
    this.resetPresentation();
    return canceled;
  }

  public enqueueVisemes(payload: RuntimeSpeechVisemeBatch): void {
    if (payload.frames.length === 0 || !this.begin(payload)) return;
    this.appendVisemes(payload.sessionId, payload.frames);
    this.finish(payload.sessionId, batchDuration(payload.frames));
  }

  public enqueueAmplitudes(payload: RuntimeSpeechAmplitudeBatch): void {
    if (payload.frames.length === 0 || !this.begin(payload)) return;
    this.appendAmplitudes(payload.sessionId, payload.frames);
    this.finish(payload.sessionId, batchDuration(payload.frames));
  }

  public update(nowMs = this.now()): void {
    const update = this.timeline.advance(nowMs);
    if (Object.prototype.hasOwnProperty.call(update, "viseme")) {
      if (update.viseme === null) {
        this.presentation.clearMouth();
      } else if (update.viseme !== undefined) {
        if (update.viseme.viseme === "sil") {
          this.presentation.clearMouth();
        } else {
          const durationSeconds = Math.min(
            0.08,
            Math.max(0.02, update.viseme.durationMs / 4000),
          );
          this.presentation.setMouthExpression(
            visemeMap[update.viseme.viseme] ?? "aa",
            update.viseme.weight,
            durationSeconds,
          );
        }
      }
    }
    if (update.amplitude !== undefined) {
      this.amplitudeValue = update.amplitude;
    }
    if (update.finishedSessionId !== undefined) {
      this.presentation.onFinished(update.finishedSessionId);
    }
  }

  public applyAmplitude(
    expressionManager: Pick<
      NonNullable<import("@pixiv/three-vrm").VRM["expressionManager"]>,
      "setValue"
    >,
  ): void {
    this.smoothAmplitudeValue = MathUtils.lerp(
      this.smoothAmplitudeValue,
      this.amplitudeValue,
      0.25,
    );
    if (this.amplitudeValue > 0.001 || this.smoothAmplitudeValue > 0.001) {
      expressionManager.setValue("aa", this.smoothAmplitudeValue);
    }
  }

  public resetPresentation(): void {
    this.resetAmplitude();
    this.presentation.clearMouth();
  }

  private now(): number {
    return this.presentation.nowMs?.() ?? performance.now();
  }
}

function batchDuration(
  frames: readonly (SpeechVisemeFrame | SpeechAmplitudeFrame)[],
): number {
  return frames.reduce(
    (end, frame) =>
      Math.max(end, Number(frame.timestampMs || 0) + Number(frame.durationMs || 0)),
    0,
  );
}
