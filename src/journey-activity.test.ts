import { describe, expect, it, vi } from "vitest";
import {
  MAX_RELAY_RECEIPT_ACTIONS,
  advanceRelayAttempt,
  careHistory,
  collectEcho,
  commitCareAction,
  commitRelayCompletion,
  commitSession,
  createCareIntent,
  createJourney,
  createPlaySession,
  createRelayAttempt,
  deriveActivityMilestones,
  hydrateJourney,
  journeyOriginSha256,
  playHistory,
  revisionForJourney,
  serializeJourney,
  sha256String,
  stageForJourney,
  type ActivityCompleteEvent,
  type Journey,
  type RelayAction,
  type RelayAttempt,
} from "./model";
import { createBrokenRelayState, transitionBrokenRelay } from "./companion-activities/broken-relay";

const originTime = "2026-09-06T00:00:00.000Z";
const completionTime = "2026-09-06T00:03:00.000Z";
const solution: readonly RelayAction[] = [
  { type: "START" }, { type: "REDIRECT", node: 2 }, { type: "REDIRECT", node: 1 }, { type: "REDIRECT", node: 3 },
  { type: "INSPECT", id: "A" }, { type: "INSPECT", id: "B" }, { type: "INSPECT", id: "C" }, { type: "RESOLVE", id: "B" },
];

function solve(journey: Journey, sessionId = "relay-session-1"): RelayAttempt {
  return solution.reduce(advanceRelayAttempt, createRelayAttempt(journey, sessionId));
}

function withCare(journey: Journey, at = "2026-09-06T00:01:00.000Z"): Journey {
  return commitCareAction(journey, createCareIntent(journey, "greet"), at);
}

function withPlay(journey: Journey, at = "2026-09-06T00:02:00.000Z"): Journey {
  let session = createPlaySession(journey);
  for (const echo of session.echoes.slice(0, 3)) session = collectEcho(session, echo.id);
  return commitSession(journey, session, "hold", at);
}

function completed(): Journey {
  const journey = withPlay(withCare(createJourney("relay-journey", originTime)));
  const attempt = solve(journey);
  return commitRelayCompletion(journey, attempt, attempt.sessionId, completionTime);
}

function authority(journey = completed()): Record<string, any> {
  return JSON.parse(serializeJourney(journey)) as Record<string, any>;
}

function rehashActivity(event: Record<string, any>): void {
  const steps = event.actions.map((action: Record<string, unknown>) => action.type === "START"
    ? [action.type] : [action.type, action.type === "REDIRECT" ? action.node : action.id]);
  event.eventId = `event-${event.sequence}-${sha256String(JSON.stringify([
    "journey-event-v3", event.previousEventId, event.sequence, event.committedAt,
    event.kind, event.activityId, event.rulesVersion, event.sessionId, steps,
  ]))}`;
}

describe("Journey-owned Relay activity", () => {
  it("preserves the pre-activity v3 golden authority bytes, origin and schema-2 hashes", () => {
    const journey = withPlay(withCare(createJourney("m2-disposable-migration-opal", originTime)));
    expect(journey.version).toBe(3);
    expect(journeyOriginSha256(journey)).toBe("c82faa6cb0b9e1dc0ef3a2b3827f4ae90925eb701737668f05864adc2ca3ead0");
    expect(sha256String(serializeJourney(journey))).toBe("521911cc030370d8b963f4149d203fda5b6ab1e2e3782f4d521595fedbaa9067");
    expect(journey.events.map((event) => event.eventId)).toEqual([
      "event-1-2cb888fc58fbc1b9c56be5b4c0a287b624c5b538043a349cfbcec3b20ee19220",
      "event-2-414bdd1a9d396e642f193c700e6cf83c87f93cdeec52479edc56265ced5df770",
    ]);
    expect(serializeJourney(hydrateJourney(authority(journey))!)).toBe(serializeJourney(journey));
  });

  it("creates a detached frozen attempt without changing Journey or reading Date.now", () => {
    const journey = createJourney("attempt-only", originTime);
    const before = serializeJourney(journey);
    const clock = vi.spyOn(Date, "now").mockImplementation(() => { throw new Error("No ambient clock"); });
    try {
      const attempt = createRelayAttempt(journey, "session-1");
      expect(attempt.baseRevision).toBe(revisionForJourney(journey));
      expect(attempt.state).toEqual(createBrokenRelayState());
      expect(Object.isFrozen(attempt)).toBe(true);
      expect(Object.isFrozen(attempt.actions)).toBe(true);
      expect(Object.isFrozen(attempt.state)).toBe(true);
      expect(Object.isFrozen(attempt.state.readTransmissionIds)).toBe(true);
      expect(() => (attempt.actions as RelayAction[]).push({ type: "START" })).toThrow();
      expect(serializeJourney(journey)).toBe(before);
    } finally { clock.mockRestore(); }
  });

  it("preserves source feedback and selection across wrong, repeated and out-of-order inputs", () => {
    const journey = createJourney("source-semantics", originTime);
    let attempt = createRelayAttempt(journey, "session-1");
    let source = createBrokenRelayState();
    const inputs: RelayAction[] = [
      { type: "INSPECT", id: "B" }, { type: "RESOLVE", id: "B" }, { type: "START" }, { type: "START" },
      { type: "REDIRECT", node: 1 }, { type: "REDIRECT", node: 2 }, { type: "REDIRECT", node: 2 },
      { type: "REDIRECT", node: 1 }, { type: "REDIRECT", node: 3 }, { type: "RESOLVE", id: "B" },
      { type: "INSPECT", id: "C" }, { type: "INSPECT", id: "A" }, { type: "INSPECT", id: "C" },
      { type: "RESOLVE", id: "A" }, { type: "START" }, { type: "INSPECT", id: "B" },
      { type: "RESOLVE", id: "C" }, { type: "RESOLVE", id: "B" }, { type: "INSPECT", id: "A" },
    ];
    for (const input of inputs) {
      source = transitionBrokenRelay(source, input);
      attempt = advanceRelayAttempt(attempt, input);
      expect(attempt.state).toEqual(source);
    }
    expect(attempt.actions).toHaveLength(8);
    expect(attempt.actions.slice(4, 7)).toEqual([
      { type: "INSPECT", id: "C" }, { type: "INSPECT", id: "A" }, { type: "INSPECT", id: "B" },
    ]);
    expect(attempt.state.phase).toBe("RESTORED");
    expect(deriveActivityMilestones(journey)).toEqual([]);
  });

  it("allows unlimited retryable mistakes while bounding accepted receipt steps to eight", () => {
    let attempt = advanceRelayAttempt(createRelayAttempt(createJourney("retries", originTime), "session-1"), { type: "START" });
    for (let index = 0; index < 300; index += 1) attempt = advanceRelayAttempt(attempt, { type: "REDIRECT", node: 1 });
    expect(attempt.actions).toEqual([{ type: "START" }]);
    for (const step of solution.slice(1)) attempt = advanceRelayAttempt(attempt, step);
    expect(attempt.state.phase).toBe("RESTORED");
    expect(attempt.actions).toHaveLength(MAX_RELAY_RECEIPT_ACTIONS);
    expect(attempt.actions.every(Object.isFrozen)).toBe(true);
  });

  it("upgrades on explicit completion only, preserving origin/history and granting no field rewards", () => {
    const journey = withPlay(withCare(createJourney("no-field-reward", originTime)));
    const before = serializeJourney(journey);
    const field = createPlaySession(journey);
    const attempt = solve(journey);
    expect(serializeJourney(journey)).toBe(before);
    const kept = commitRelayCompletion(journey, attempt, attempt.sessionId, completionTime);
    expect(kept.version).toBe(4);
    expect(kept.events.slice(0, -1)).toEqual(journey.events);
    expect(journeyOriginSha256(kept)).toBe(journeyOriginSha256(journey));
    expect(kept.id).toBe(journey.id);
    expect(kept.seed).toBe(journey.seed);
    expect(kept.provenance).toEqual(journey.provenance);
    expect(kept.core).toBe(journey.core);
    expect([kept.plays, kept.bond, kept.expression, kept.affinities, kept.care]).toEqual(
      [journey.plays, journey.bond, journey.expression, journey.affinities, journey.care]);
    expect(stageForJourney(kept)).toEqual(stageForJourney(journey));
    expect(createPlaySession(kept)).toEqual({ ...field, baseRevision: revisionForJourney(kept) });
    const event = kept.events.at(-1)!;
    expect(event).toMatchObject({ schema: 3, kind: "activity-complete", activityId: "broken-relay", rulesVersion: 1, actions: solution });
    expect(Object.isFrozen(event)).toBe(true);
    expect(Object.isFrozen((event as ActivityCompleteEvent).actions)).toBe(true);
    expect(deriveActivityMilestones(kept)).toEqual([{
      id: "game:broken-relay:restored", activityId: "broken-relay", rulesVersion: 1,
      title: "Broken Relay restored",
      text: "Protected the relay through nodes 2 → 1 → 3, inspected all three transmissions, and identified B as contradicting the field log.",
      eventId: event.eventId, committedAt: completionTime,
    }]);
    expect(Object.isFrozen(deriveActivityMilestones(kept)[0])).toBe(true);
  });

  it("keeps a duplicate completion idempotent without reusing it as a new achievement", () => {
    const journey = createJourney("idempotent", originTime);
    const attempt = solve(journey);
    const kept = commitRelayCompletion(journey, attempt, attempt.sessionId, completionTime);
    expect(commitRelayCompletion(kept, attempt, attempt.sessionId, completionTime)).toBe(kept);
    const later = withCare(kept, "2026-09-06T00:04:00.000Z");
    expect(commitRelayCompletion(later, attempt, attempt.sessionId, completionTime)).toBe(later);
    const replay = solve(later, "session-2");
    expect(commitRelayCompletion(later, replay, replay.sessionId, completionTime)).toBe(later);
    expect(deriveActivityMilestones(later)).toHaveLength(1);
  });

  it("rejects an ended session, stale Journey, different origin and an unrelated stale attempt", () => {
    const journey = createJourney("stale", originTime);
    const attempt = solve(journey);
    expect(() => commitRelayCompletion(journey, attempt, "session-2", completionTime)).toThrow(/session/i);
    expect(() => commitRelayCompletion(withCare(journey), attempt, attempt.sessionId, completionTime)).toThrow(/stale/i);
    expect(() => commitRelayCompletion(createJourney("other", originTime), attempt, attempt.sessionId, completionTime)).toThrow(/stale/i);
    const kept = commitRelayCompletion(journey, attempt, attempt.sessionId, completionTime);
    const otherAttempt = solve(journey, "other-attempt");
    expect(() => commitRelayCompletion(kept, otherAttempt, otherAttempt.sessionId, completionTime)).toThrow(/stale/i);
    expect(() => commitRelayCompletion(kept, attempt, "ended", completionTime)).toThrow(/session/i);
  });

  it("never admits a forged terminal projection, incomplete steps or appearance/reset actions", () => {
    const journey = createJourney("incomplete", originTime);
    const attempt = createRelayAttempt(journey, "session-1");
    expect(() => commitRelayCompletion(journey, attempt, attempt.sessionId, completionTime)).toThrow(/Complete/i);
    expect(() => commitRelayCompletion(journey, { ...attempt, state: solve(journey).state }, attempt.sessionId, completionTime)).toThrow(/projection/i);
    for (const type of ["TRY_FOCUS", "RESTORE_PROTO", "RESET"]) {
      expect(() => advanceRelayAttempt(attempt, { type } as RelayAction)).toThrow(/Unknown/i);
    }
    expect(() => advanceRelayAttempt(attempt, { type: "START", extra: true } as RelayAction)).toThrow();
    expect(() => createRelayAttempt(journey, "")).toThrow(/session/i);
    expect(() => createRelayAttempt(journey, "s".repeat(129))).toThrow(/session/i);
  });

  it("rejects malformed/accessor attempts and actions without executing their getters", () => {
    const journey = createJourney("plain-data", originTime);
    const attempt = createRelayAttempt(journey, "session-1");
    const getter = vi.fn(() => "START");
    const action = Object.defineProperty({}, "type", { get: getter, enumerable: true });
    expect(() => advanceRelayAttempt(attempt, action as RelayAction)).toThrow();
    const badAttempt = Object.defineProperty({ ...attempt }, "actions", { get: getter, enumerable: true });
    expect(() => commitRelayCompletion(journey, badAttempt, attempt.sessionId, completionTime)).toThrow();
    expect(getter).not.toHaveBeenCalled();
  });

  it("detaches accepted actions and rejects accessor provenance before replay", () => {
    const journey = createJourney("detached-input", originTime);
    const action: { type: "START" | "RESET" } = { type: "START" };
    const attempt = advanceRelayAttempt(createRelayAttempt(journey, "session-1"), action as RelayAction);
    action.type = "RESET";
    expect(attempt.actions).toEqual([{ type: "START" }]);
    const saved = authority();
    const getter = vi.fn(() => "native-v3");
    saved.provenance = Object.defineProperty({ ...saved.provenance }, "source", { get: getter, enumerable: true });
    expect(hydrateJourney(saved)).toBeNull();
    expect(getter).not.toHaveBeenCalled();
  });

  it("retains schema-2 care and field events after upgrade and fully replays mixed v4 history", () => {
    let journey = completed();
    journey = withCare(journey, "2026-09-06T00:04:00.000Z");
    journey = withPlay(journey, "2026-09-06T00:05:00.000Z");
    expect(journey.version).toBe(4);
    expect(journey.events.map((event) => event.schema)).toEqual([2, 2, 3, 2, 2]);
    expect(playHistory(journey)).toHaveLength(2);
    expect(careHistory(journey)).toHaveLength(2);
    const restored = hydrateJourney(authority(journey));
    expect(restored).toEqual(journey);
    expect(serializeJourney(restored!)).toBe(serializeJourney(journey));
    expect(deriveActivityMilestones(restored!)).toEqual(deriveActivityMilestones(journey));
  });

  it("preserves migrated legacy provenance when an existing Journey later completes Relay", () => {
    const legacy = hydrateJourney({ version: 1, seed: "legacy-relay", createdAt: originTime, traces: [] })!;
    expect(legacy.version).toBe(3);
    const attempt = solve(legacy);
    const kept = commitRelayCompletion(legacy, attempt, attempt.sessionId, completionTime);
    expect(kept.provenance).toEqual(legacy.provenance);
    expect(journeyOriginSha256(kept)).toBe(journeyOriginSha256(legacy));
    expect(hydrateJourney(authority(kept))).toEqual(kept);
  });

  it("requires a real activity for v4 and preserves v3 prefix compatibility", () => {
    const old = withCare(createJourney("version-guard", originTime));
    expect(hydrateJourney({ ...authority(old), version: 4 })).toBeNull();
    const badTail = { schema: 99, kind: "unknown" };
    expect(hydrateJourney({ ...authority(old), events: [...old.events, badTail] })?.events).toEqual(old.events);
    expect(hydrateJourney({ ...authority(), events: [...completed().events, badTail] })).toBeNull();
    expect(hydrateJourney({ ...authority(), version: 99 })).toBeNull();
  });

  it.each([0, 1, 2])("rejects the entire v4 authority for an invalid event at index %s", (index) => {
    const saved = authority();
    saved.events[index].eventId = "damaged";
    expect(hydrateJourney(saved)).toBeNull();
  });

  it.each([
    ["short receipt", (event: Record<string, any>) => { event.actions.pop(); }],
    ["wrong redirect", (event: Record<string, any>) => { event.actions[1].node = 1; }],
    ["wrong answer", (event: Record<string, any>) => { event.actions[7].id = "A"; }],
    ["duplicate clue", (event: Record<string, any>) => { event.actions[6].id = "A"; }],
    ["future rules", (event: Record<string, any>) => { event.rulesVersion = 2; }],
    ["unknown activity", (event: Record<string, any>) => { event.activityId = "other"; }],
    ["non-progress step", (event: Record<string, any>) => { event.actions.push({ type: "START" }); }],
    ["extra field", (event: Record<string, any>) => { event.reward = 99; }],
  ] as const)("rejects %s even with a recomputed event checksum", (_name, damage) => {
    const saved = authority();
    damage(saved.events[2]);
    rehashActivity(saved.events[2]);
    expect(hydrateJourney(saved)).toBeNull();
  });

  it("rejects a second validly hashed completion event and malformed v4 containers", () => {
    const saved = authority();
    const second = { ...saved.events[2], sequence: 4, previousEventId: saved.events[2].eventId, sessionId: "session-2" };
    rehashActivity(second);
    expect(hydrateJourney({ ...saved, events: [...saved.events, second] })).toBeNull();
    expect(hydrateJourney({ ...saved, unexpected: true })).toBeNull();
    const sparse = authority();
    delete sparse.events[1];
    expect(hydrateJourney(sparse)).toBeNull();
    const extra = authority();
    extra.events[0].extra = true;
    expect(hydrateJourney(extra)).toBeNull();
  });
});
