import { describe, expect, it } from "vitest";

import { SpeechTimeline } from "../src/speech-timeline";

describe("SpeechTimeline", () => {
  it("removes bridge latency and expires a viseme on the monotonic clock", () => {
    const timeline = new SpeechTimeline();
    timeline.begin({
      sessionId: "speech-1",
      mode: "viseme",
      timelineOriginEpochMs: 1_000,
      nowMs: 250,
      wallNowEpochMs: 1_120,
    });
    timeline.appendVisemes("speech-1", [
      { viseme: "aa", weight: 0.8, timestampMs: 100, durationMs: 100 },
    ]);

    expect(timeline.advance(250).viseme).toEqual({
      viseme: "aa",
      weight: 0.8,
      durationMs: 100,
    });
    expect(timeline.advance(331).viseme).toBeNull();
  });

  it("skips an already expired late frame instead of flashing stale speech", () => {
    const timeline = new SpeechTimeline();
    timeline.begin({
      sessionId: "speech-1",
      mode: "viseme",
      timelineOriginEpochMs: 1_000,
      nowMs: 100,
      wallNowEpochMs: 1_100,
    });
    timeline.appendVisemes("speech-1", [
      { viseme: "oh", timestampMs: 0, durationMs: 20 },
    ]);

    expect(timeline.advance(100).viseme).toBeNull();
  });

  it("plays amplitude samples, closes the mouth, and finishes exactly once", () => {
    const timeline = new SpeechTimeline();
    timeline.begin({
      sessionId: "speech-2",
      mode: "amplitude",
      timelineOriginEpochMs: 2_000,
      nowMs: 0,
      wallNowEpochMs: 2_000,
    });
    timeline.appendAmplitudes("speech-2", [
      { amplitude: 1, timestampMs: 0, durationMs: 60 },
      { amplitude: 0.5, timestampMs: 40, durationMs: 60 },
    ]);
    timeline.finish("speech-2", 120);

    expect(timeline.advance(0).amplitude).toBe(1);
    expect(timeline.advance(40).amplitude).toBe(0.5);
    expect(timeline.advance(101).amplitude).toBe(0);
    expect(timeline.advance(119).finishedSessionId).toBeUndefined();
    expect(timeline.advance(120)).toEqual({
      viseme: null,
      amplitude: 0,
      finishedSessionId: "speech-2",
    });
    expect(timeline.advance(121)).toEqual({});
  });

  it("ignores stale session packets without affecting the current session", () => {
    const timeline = new SpeechTimeline();
    timeline.begin({
      sessionId: "old",
      mode: "viseme",
      timelineOriginEpochMs: 0,
      nowMs: 0,
      wallNowEpochMs: 0,
    });
    timeline.begin({
      sessionId: "current",
      mode: "viseme",
      timelineOriginEpochMs: 0,
      nowMs: 0,
      wallNowEpochMs: 0,
    });

    expect(timeline.appendVisemes("old", [])).toBe(false);
    expect(timeline.finish("old", 10)).toBe(false);
    expect(timeline.cancel("old")).toBe(false);
    expect(timeline.sessionId).toBe("current");
  });

  it("rejects out-of-order direct input after a newer timeline command", () => {
    const timeline = new SpeechTimeline();

    expect(timeline.acceptInputRevision(4)).toBe(true);
    expect(timeline.acceptInputRevision(3)).toBe(false);
    expect(timeline.acceptInputRevision(5)).toBe(true);
    expect(() => timeline.acceptInputRevision(Number.NaN)).toThrow(
      "speechRevision",
    );
  });

  it("rejects mixed modes and invalid samples", () => {
    const timeline = new SpeechTimeline();
    timeline.begin({
      sessionId: "speech-3",
      mode: "amplitude",
      timelineOriginEpochMs: 0,
      nowMs: 0,
      wallNowEpochMs: 0,
    });

    expect(() => timeline.appendVisemes("speech-3", [])).toThrow("amplitude");
    expect(() =>
      timeline.appendAmplitudes("speech-3", [
        { amplitude: Number.NaN, timestampMs: 0, durationMs: 20 },
      ]),
    ).toThrow("amplitude");
  });
});
