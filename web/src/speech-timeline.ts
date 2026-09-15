export type SpeechTimelineMode = "viseme" | "amplitude";

export interface SpeechTimelineBeginOptions {
  readonly sessionId: string;
  readonly mode: SpeechTimelineMode;
  readonly timelineOriginEpochMs: number;
  readonly nowMs: number;
  readonly wallNowEpochMs: number;
}

export interface SpeechVisemeFrame {
  readonly viseme: string;
  readonly weight?: number;
  readonly timestampMs: number;
  readonly durationMs: number;
}

export interface SpeechAmplitudeFrame {
  readonly amplitude: number;
  readonly timestampMs: number;
  readonly durationMs: number;
}

export interface SpeechVisemeUpdate {
  readonly viseme: string;
  readonly weight: number;
  readonly durationMs: number;
}

export interface SpeechTimelineUpdate {
  readonly viseme?: SpeechVisemeUpdate | null;
  readonly amplitude?: number;
  readonly finishedSessionId?: string;
}

interface QueuedVisemeFrame extends SpeechVisemeUpdate {
  readonly kind: "viseme";
  readonly targetTimeMs: number;
  readonly sequence: number;
}

interface QueuedAmplitudeFrame {
  readonly kind: "amplitude";
  readonly amplitude: number;
  readonly durationMs: number;
  readonly targetTimeMs: number;
  readonly sequence: number;
}

type QueuedSpeechFrame = QueuedVisemeFrame | QueuedAmplitudeFrame;

const visemeNames = new Set(["aa", "ih", "ou", "ee", "oh", "sil"]);

/**
 * Schedules speech data against a monotonic clock.
 *
 * The origin is transferred as wall-clock time so WebView transport latency is
 * removed once, then all playback uses performance.now() and cannot jump when
 * the system clock changes.
 */
export class SpeechTimeline {
  private queue: QueuedSpeechFrame[] = [];
  private epochMs = 0;
  private finishAtMs: number | null = null;
  private visemeExpiresAtMs: number | null = null;
  private amplitudeExpiresAtMs: number | null = null;
  private sequence = 0;
  private latestInputRevision = 0;

  public sessionId: string | null = null;
  public mode: SpeechTimelineMode | null = null;

  public get isActive(): boolean {
    return this.sessionId !== null;
  }

  /** Rejects commands that arrived after a newer Flutter speech input. */
  public acceptInputRevision(value: number): boolean {
    if (!Number.isSafeInteger(value) || value < 0) {
      throw new TypeError("speechRevision must be a non-negative safe integer.");
    }
    if (value < this.latestInputRevision) return false;
    this.latestInputRevision = value;
    return true;
  }

  public begin(options: SpeechTimelineBeginOptions): void {
    if (typeof options.sessionId !== "string" || options.sessionId.length === 0) {
      throw new TypeError("sessionId must be a non-empty string.");
    }
    if (options.mode !== "viseme" && options.mode !== "amplitude") {
      throw new TypeError("Speech mode must be viseme or amplitude.");
    }
    for (const [name, value] of Object.entries({
      timelineOriginEpochMs: options.timelineOriginEpochMs,
      nowMs: options.nowMs,
      wallNowEpochMs: options.wallNowEpochMs,
    })) {
      if (!Number.isFinite(value)) {
        throw new TypeError(`${name} must be finite.`);
      }
    }

    this.reset();
    this.sessionId = options.sessionId;
    this.mode = options.mode;
    this.epochMs =
      options.nowMs + options.timelineOriginEpochMs - options.wallNowEpochMs;
  }

  public appendVisemes(
    sessionId: string,
    frames: readonly SpeechVisemeFrame[],
  ): boolean {
    if (!this.accepts(sessionId)) return false;
    if (this.mode !== "viseme") {
      throw new Error("Cannot append visemes to an amplitude speech timeline.");
    }
    this.assertAppendable();
    for (const frame of frames) {
      const timestampMs = readNonNegative(frame.timestampMs, "timestampMs");
      const durationMs = readNonNegative(frame.durationMs, "durationMs");
      const weight = readUnitValue(frame.weight ?? 1, "weight");
      if (!visemeNames.has(frame.viseme)) {
        throw new TypeError(`Unknown speech viseme: ${String(frame.viseme)}.`);
      }
      this.queue.push({
        kind: "viseme",
        viseme: frame.viseme,
        weight,
        durationMs,
        targetTimeMs: this.epochMs + timestampMs,
        sequence: this.sequence++,
      });
    }
    this.sortQueue();
    return true;
  }

  public appendAmplitudes(
    sessionId: string,
    frames: readonly SpeechAmplitudeFrame[],
  ): boolean {
    if (!this.accepts(sessionId)) return false;
    if (this.mode !== "amplitude") {
      throw new Error("Cannot append amplitudes to a viseme speech timeline.");
    }
    this.assertAppendable();
    for (const frame of frames) {
      const timestampMs = readNonNegative(frame.timestampMs, "timestampMs");
      const durationMs = readNonNegative(frame.durationMs, "durationMs");
      this.queue.push({
        kind: "amplitude",
        amplitude: readUnitValue(frame.amplitude, "amplitude"),
        durationMs,
        targetTimeMs: this.epochMs + timestampMs,
        sequence: this.sequence++,
      });
    }
    this.sortQueue();
    return true;
  }

  public finish(sessionId: string, audioDurationMs: number): boolean {
    if (!this.accepts(sessionId)) return false;
    if (this.finishAtMs !== null) {
      throw new StateError("The speech timeline is already finishing.");
    }
    this.finishAtMs =
      this.epochMs + readNonNegative(audioDurationMs, "audioDurationMs");
    return true;
  }

  public cancel(sessionId?: string): boolean {
    if (!this.isActive || (sessionId !== undefined && !this.accepts(sessionId))) {
      return false;
    }
    this.reset();
    return true;
  }

  public advance(nowMs: number): SpeechTimelineUpdate {
    if (!Number.isFinite(nowMs)) {
      throw new TypeError("nowMs must be finite.");
    }
    if (!this.isActive) return {};

    const update: {
      viseme?: SpeechVisemeUpdate | null;
      amplitude?: number;
      finishedSessionId?: string;
    } = {};

    while (this.queue.length > 0 && this.queue[0]!.targetTimeMs <= nowMs) {
      const frame = this.queue.shift()!;
      if (frame.kind === "viseme") {
        if (frame.viseme === "sil" || frame.weight <= 0.001) {
          update.viseme = null;
          this.visemeExpiresAtMs = null;
        } else {
          update.viseme = {
            viseme: frame.viseme,
            weight: frame.weight,
            durationMs: frame.durationMs,
          };
          this.visemeExpiresAtMs = frame.targetTimeMs + frame.durationMs;
        }
      } else {
        update.amplitude = frame.amplitude;
        this.amplitudeExpiresAtMs =
          frame.amplitude <= 0.001
            ? null
            : frame.targetTimeMs + frame.durationMs;
      }
    }

    if (
      this.visemeExpiresAtMs !== null &&
      nowMs >= this.visemeExpiresAtMs
    ) {
      update.viseme = null;
      this.visemeExpiresAtMs = null;
    }
    if (
      this.amplitudeExpiresAtMs !== null &&
      nowMs >= this.amplitudeExpiresAtMs
    ) {
      update.amplitude = 0;
      this.amplitudeExpiresAtMs = null;
    }

    if (this.finishAtMs !== null && nowMs >= this.finishAtMs) {
      const finishedSessionId = this.sessionId!;
      update.viseme = null;
      update.amplitude = 0;
      update.finishedSessionId = finishedSessionId;
      this.reset();
    }
    return update;
  }

  private accepts(sessionId: string): boolean {
    return this.sessionId === sessionId;
  }

  private assertAppendable(): void {
    if (this.finishAtMs !== null) {
      throw new StateError("Cannot append to a finishing speech timeline.");
    }
  }

  private sortQueue(): void {
    this.queue.sort(
      (first, second) =>
        first.targetTimeMs - second.targetTimeMs ||
        first.sequence - second.sequence,
    );
  }

  private reset(): void {
    this.queue = [];
    this.epochMs = 0;
    this.finishAtMs = null;
    this.visemeExpiresAtMs = null;
    this.amplitudeExpiresAtMs = null;
    this.sequence = 0;
    this.sessionId = null;
    this.mode = null;
  }
}

class StateError extends Error {
  public constructor(message: string) {
    super(message);
    this.name = "StateError";
  }
}

function readNonNegative(value: number, field: string): number {
  if (!Number.isFinite(value) || value < 0) {
    throw new TypeError(`${field} must be a non-negative finite number.`);
  }
  return value;
}

function readUnitValue(value: number, field: string): number {
  if (!Number.isFinite(value) || value < 0 || value > 1) {
    throw new TypeError(`${field} must be a finite number from 0 to 1.`);
  }
  return value;
}
