import { describe, expect, it } from "vitest";
import {
  CARE_ACTION_ORDER,
  CORE_CONTINUITY,
  ROLE_ORDER,
  careHistory,
  collectEcho,
  commitCareAction,
  commitSession,
  createCareIntent,
  createJourney,
  createPlaySession,
  hashString,
  hydrateJourney,
  playHistory,
  projectCare,
  revisionForJourney,
  serializeJourney,
  sha256String,
  stageForJourney,
  type Journey,
  type PlayCommitEvent,
  type PlaySession,
} from "./model";

function collectFirstThree(journey: Journey): PlaySession {
  let session = createPlaySession(journey);
  for (const echo of session.echoes.slice(0, 3)) session = collectEcho(session, echo.id);
  return session;
}

function legacyPlayTrace(event: PlayCommitEvent, includeGenerator = true) {
  return {
    id: event.sessionId,
    play: event.play,
    keptAt: event.committedAt,
    fieldName: event.fieldName,
    choice: event.choice,
    signals: event.signals,
    ...(includeGenerator ? { generator: event.generator } : {}),
  };
}

function legacyCareTraces(journey: Journey) {
  let previousTraceId = "origin";
  return careHistory(journey).map((event, index) => {
    const sequence = index + 1;
    const digest = hashString(
      `${journey.seed}:care:${journey.careStartedAt}:${previousTraceId}:${sequence}:${event.action}:${event.committedAt}`,
    );
    const trace = {
      id: `care-${sequence}-${digest.toString(16).padStart(8, "0")}`,
      sequence,
      action: event.action,
      actedAt: event.committedAt,
    };
    previousTraceId = trace.id;
    return trace;
  });
}

function v2Fixture(journey: Journey) {
  return {
    version: 2,
    seed: journey.seed,
    createdAt: journey.createdAt,
    careStartedAt: journey.careStartedAt,
    traces: playHistory(journey).map((event) => legacyPlayTrace(event)),
    careTraces: legacyCareTraces(journey),
    plays: 999,
    bond: 999,
    care: { energy: -999, calm: -999, curiosity: 999, updatedAt: "2099-01-01T00:00:00.000Z" },
  };
}

function eventKinds(journey: Journey) {
  return journey.events.map((event) => event.kind);
}

describe("ARCHi journey model", () => {
  it("uses the standard SHA-256 digest for authoritative content binding", () => {
    expect(sha256String("abc")).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  });

  it("generates the same field for the same journey and play", () => {
    const journey = createJourney("opal-test", "2026-08-28T00:00:00.000Z");
    expect(createPlaySession(journey)).toEqual(createPlaySession(journey));
  });

  it("changes and branches the generated field only after a committed play", () => {
    const journey = createJourney("branch-test", "2026-08-28T00:00:00.000Z");
    const session = collectFirstThree(journey);
    const left = commitSession(journey, session, session.proposals[0], "2026-08-28T00:01:00.000Z");
    const right = commitSession(journey, session, session.proposals[1], "2026-08-28T00:01:00.000Z");

    expect(playHistory(left)[0].signals).toEqual(playHistory(right)[0].signals);
    expect(playHistory(left)[0].choice).not.toBe(playHistory(right)[0].choice);
    expect(createPlaySession(left).seed).not.toBe(session.seed);
    expect(createPlaySession(left).seed).not.toBe(createPlaySession(right).seed);
  });

  it("does not mutate journey state while a play is only observing", () => {
    const journey = createJourney("boundary-test", "2026-08-28T00:00:00.000Z");
    const before = JSON.stringify(journey);
    expect(collectFirstThree(journey).proposals).toHaveLength(2);
    expect(JSON.stringify(journey)).toBe(before);
  });

  it("commits only a proposed expression and preserves the Core Pearl", () => {
    const journey = createJourney("commit-test", "2026-08-28T00:00:00.000Z");
    const session = collectFirstThree(journey);
    const choice = session.proposals[0];
    const evolved = commitSession(journey, session, choice, "2026-08-28T00:01:00.000Z");
    const invalidChoice = ROLE_ORDER.find((role) => !session.proposals.includes(role));

    expect(evolved.plays).toBe(1);
    expect(evolved.expression).toBe(choice);
    expect(evolved.affinities[choice]).toBeGreaterThanOrEqual(3);
    expect(evolved.core).toBe(CORE_CONTINUITY);
    expect(invalidChoice).toBeDefined();
    expect(() => commitSession(journey, session, invalidChoice!)).toThrowError(/Only a proposed/);
  });

  it("lets the player hold without changing expression", () => {
    const journey = createJourney("hold-test", "2026-08-28T00:00:00.000Z");
    const session = collectFirstThree(journey);
    const evolved = commitSession(journey, session, "hold", "2026-08-28T00:01:00.000Z");
    expect(evolved.expression).toBe(journey.expression);
    expect(evolved.affinities.guardian).toBe(1);
    expect(playHistory(evolved)[0].choice).toBe("hold");
  });

  it("persists only v3 authority and rebuilds every derived projection", () => {
    let journey = createJourney("compact-v3", "2026-08-28T00:00:00.000Z");
    const session = collectFirstThree(journey);
    journey = commitSession(journey, session, session.proposals[0], "2026-08-28T00:01:00.000Z");
    journey = commitCareAction(journey, createCareIntent(journey, "greet"), "2026-08-28T00:02:00.000Z");

    const serialized = JSON.parse(serializeJourney(journey)) as Record<string, unknown>;
    expect(Object.keys(serialized)).toEqual([
      "version",
      "seed",
      "createdAt",
      "careStartedAt",
      "provenance",
      "events",
    ]);
    const restored = hydrateJourney({
      ...serialized,
      id: "ARCHI-FORGED",
      plays: 999,
      bond: 999,
      expression: "guardian",
      affinities: Object.fromEntries(ROLE_ORDER.map((role) => [role, 999])),
      care: { energy: 999, calm: -1, curiosity: 999, updatedAt: "2099-01-01T00:00:00.000Z" },
      updatedAt: "2099-01-01T00:00:00.000Z",
      core: { identity: "rewritten" },
    });
    expect(restored).toEqual(journey);
    expect(restored?.core).toBe(CORE_CONTINUITY);
  });

  it("records play and care in one globally sequenced, chained timeline", () => {
    let journey = createJourney("mixed-order", "2026-08-28T00:00:00.000Z");
    journey = commitCareAction(journey, createCareIntent(journey, "greet"), "2026-08-28T00:01:00.000Z");
    let session = collectFirstThree(journey);
    journey = commitSession(journey, session, session.proposals[0], "2026-08-28T00:02:00.000Z");
    journey = commitCareAction(journey, createCareIntent(journey, "rest"), "2026-08-28T00:03:00.000Z");
    session = collectFirstThree(journey);
    journey = commitSession(journey, session, "hold", "2026-08-28T00:04:00.000Z");

    expect(eventKinds(journey)).toEqual(["care-action", "play-commit", "care-action", "play-commit"]);
    expect(journey.events.map((event) => event.sequence)).toEqual([1, 2, 3, 4]);
    expect(journey.events.every((event) => event.schema === 2)).toBe(true);
    expect(journey.events.every((event) => /^event-\d+-[0-9a-f]{64}$/.test(event.eventId))).toBe(true);
    expect(journey.events.slice(1).every((event, index) => event.previousEventId === journey.events[index].eventId)).toBe(
      true,
    );
    expect(hydrateJourney(JSON.parse(serializeJourney(journey)))).toEqual(journey);
  });

  it("stops v3 replay at the first invalid global event and keeps one global prefix", () => {
    let journey = createJourney("global-prefix", "2026-08-28T00:00:00.000Z");
    let session = collectFirstThree(journey);
    journey = commitSession(journey, session, session.proposals[0], "2026-08-28T00:01:00.000Z");
    journey = commitCareAction(journey, createCareIntent(journey, "greet"), "2026-08-28T00:02:00.000Z");
    session = collectFirstThree(journey);
    journey = commitSession(journey, session, session.proposals[0], "2026-08-28T00:03:00.000Z");
    const authority = JSON.parse(serializeJourney(journey)) as { events: Array<Record<string, unknown>> };
    authority.events[1] = { ...authority.events[1], action: "forged" };

    const restored = hydrateJourney(authority);
    expect(restored?.events).toEqual([journey.events[0]]);
    expect(restored?.plays).toBe(1);
    expect(careHistory(restored!)).toHaveLength(0);
  });

  it("retains every event across a long mixed replay", () => {
    let journey = createJourney("long-ledger", "2026-08-28T00:00:00.000Z");
    for (let index = 1; index <= 28; index += 1) {
      const at = new Date(Date.parse(journey.createdAt) + index * 1_000).toISOString();
      if (index % 3 === 0) {
        journey = commitCareAction(journey, createCareIntent(journey, CARE_ACTION_ORDER[index % 4]), at);
      } else {
        const session = collectFirstThree(journey);
        journey = commitSession(journey, session, session.proposals[0], at);
      }
    }
    expect(hydrateJourney(JSON.parse(serializeJourney(journey)))).toEqual(journey);
    expect(journey.events).toHaveLength(28);
    expect(playHistory(journey)).toHaveLength(19);
    expect(careHistory(journey)).toHaveLength(9);
  });

  it("requires multiple development channels for growth", () => {
    const journey = createJourney("growth-test", "2026-08-28T00:00:00.000Z");
    expect(stageForJourney(journey).name).toBe("Hatchling");
    expect(stageForJourney({ ...journey, plays: 2, bond: 9 }).name).toBe("Young");
    expect(stageForJourney({ ...journey, plays: 5, bond: 21 }).name).toBe("Young");
    expect(
      stageForJourney({
        ...journey,
        plays: 5,
        bond: 21,
        affinities: { ...journey.affinities, scout: 3, hearth: 1 },
      }).name,
    ).toBe("Adolescent");
  });

  it("rejects play and care proposals bound to an older global head", () => {
    const journey = createJourney("stale-head", "2026-08-28T00:00:00.000Z");
    const play = collectFirstThree(journey);
    const care = createCareIntent(journey, "greet");
    const changed = commitCareAction(journey, createCareIntent(journey, "rest"), "2026-08-28T00:01:00.000Z");

    expect(() => commitSession(changed, play, play.proposals[0])).toThrowError(/stale/);
    expect(() => commitCareAction(changed, care, "2026-08-28T00:02:00.000Z")).toThrowError(/stale/);
  });

  it("rebuilds canonical care state before a direct public care commit", () => {
    const journey = createJourney("forged-care-aggregate", "2026-08-28T00:00:00.000Z");
    const intent = createCareIntent(journey, "greet");
    const expected = commitCareAction(journey, intent, "2026-08-28T00:01:00.000Z");
    const forged = {
      ...journey,
      updatedAt: "2099-01-01T00:00:00.000Z",
      care: { energy: 10, calm: 10, curiosity: 100, updatedAt: "2099-01-01T00:00:00.000Z" },
      plays: 999,
      bond: 100,
      expression: "guardian",
      affinities: Object.fromEntries(ROLE_ORDER.map((role) => [role, 999])),
      core: { identity: "FORGED", authority: "autonomous" },
    } as unknown as Journey;

    const committed = commitCareAction(forged, intent, "2026-08-28T00:01:00.000Z");
    expect(committed).toEqual(expected);
    expect(committed.core).toBe(CORE_CONTINUITY);
  });

  it("rebuilds canonical progression and care before a direct public play commit", () => {
    const journey = createJourney("forged-play-aggregate", "2026-08-28T00:00:00.000Z");
    const session = collectFirstThree(journey);
    const expected = commitSession(journey, session, session.proposals[0], "2026-08-28T00:01:00.000Z");
    const forged = {
      ...journey,
      updatedAt: "2099-01-01T00:00:00.000Z",
      care: { energy: 10, calm: 10, curiosity: 100, updatedAt: "2099-01-01T00:00:00.000Z" },
      plays: 999,
      bond: 100,
      expression: "guardian",
      affinities: Object.fromEntries(ROLE_ORDER.map((role) => [role, 999])),
      core: { identity: "FORGED", authority: "autonomous" },
    } as unknown as Journey;

    const committed = commitSession(forged, session, session.proposals[0], "2026-08-28T00:01:00.000Z");
    expect(committed).toEqual(expected);
    expect(committed.core).toBe(CORE_CONTINUITY);
  });

  it("binds revisions to equal-time divergent histories and migration origins", () => {
    const journey = createJourney("revision-history", "2026-08-28T00:00:00.000Z");
    const greeted = commitCareAction(journey, createCareIntent(journey, "greet"), "2026-08-28T00:01:00.000Z");
    const tended = commitCareAction(journey, createCareIntent(journey, "tend"), "2026-08-28T00:01:00.000Z");
    expect(revisionForJourney(greeted)).not.toBe(revisionForJourney(tended));

    const session = collectFirstThree(journey);
    const played = commitSession(journey, session, session.proposals[0], "2026-08-28T00:01:00.000Z");
    const migrated = hydrateJourney({
      version: 1,
      seed: played.seed,
      createdAt: played.createdAt,
      traces: playHistory(played).map((event) => legacyPlayTrace(event)),
    });
    expect(migrated).not.toBeNull();
    expect(revisionForJourney(migrated!)).not.toBe(revisionForJourney(played));
  });

  it("keeps revisions distinct for a known collision in the former 32-bit event digest", () => {
    const journey = createJourney("collision-audit", "2026-08-28T00:00:00.000Z");
    const greeted = commitCareAction(
      journey,
      createCareIntent(journey, "greet"),
      "2026-08-28T00:00:24.688Z",
    );
    const explored = commitCareAction(
      journey,
      createCareIntent(journey, "explore"),
      "2026-08-28T00:01:14.147Z",
    );

    expect(greeted.events[0].eventId).not.toBe(explored.events[0].eventId);
    expect(revisionForJourney(greeted)).not.toBe(revisionForJourney(explored));
    expect(() =>
      commitCareAction(explored, createCareIntent(greeted, "tend"), "2026-08-28T00:02:00.000Z"),
    ).toThrowError(/stale/);
  });

  it("keeps the global clock monotonic across care and play when the device clock moves backward", () => {
    let journey = createJourney("clock-test", "2026-08-28T00:10:00.000Z");
    journey = commitCareAction(journey, createCareIntent(journey, "greet"), "2026-08-28T00:05:00.000Z");
    const session = collectFirstThree(journey);
    journey = commitSession(journey, session, session.proposals[0], "2026-08-28T00:04:00.000Z");

    expect(journey.events.map((event) => event.committedAt)).toEqual([
      "2026-08-28T00:10:00.001Z",
      "2026-08-28T00:10:00.002Z",
    ]);
    expect(hydrateJourney(JSON.parse(serializeJourney(journey)))).toEqual(journey);
  });

  it("rejects forged session structure, duplicate signals, and proposals", () => {
    const journey = createJourney("forgery-test", "2026-08-28T00:00:00.000Z");
    const session = collectFirstThree(journey);
    const unproposed = ROLE_ORDER.find((role) => !session.proposals.includes(role));
    expect(unproposed).toBeDefined();
    expect(() => commitSession(journey, { ...session, seed: session.seed + 1 }, session.proposals[0])).toThrowError(
      /canonical field/,
    );
    expect(() =>
      commitSession(
        journey,
        { ...session, collected: [session.collected[0], session.collected[0], session.collected[0]] },
        session.proposals[0],
      ),
    ).toThrowError(/three unique signals/);
    expect(() =>
      commitSession(journey, { ...session, proposals: [unproposed!, session.proposals[0]] }, unproposed!),
    ).toThrowError(/proposals do not match/);
  });

  it("starts with kind, bounded care and projects elapsed time without mutation", () => {
    const journey = createJourney("care-origin", "2026-08-28T00:00:00.000Z");
    const before = JSON.stringify(journey);
    expect(journey.version).toBe(3);
    expect(journey.care).toEqual({
      energy: 80,
      calm: 75,
      curiosity: 50,
      updatedAt: "2026-08-28T00:00:00.000Z",
    });
    expect(projectCare(journey.care, "2026-08-28T03:00:00.000Z")).toMatchObject({
      energy: 74,
      calm: 72,
      curiosity: 56,
      elapsedHours: 3,
      mood: "balanced",
    });
    expect(projectCare(journey.care, "2026-09-10T00:00:00.000Z")).toMatchObject({
      energy: 40,
      calm: 51,
      curiosity: 90,
      elapsedHours: 24,
    });
    expect(projectCare(journey.care, "2026-08-27T00:00:00.000Z")).toMatchObject({ elapsedHours: 0 });
    expect(JSON.stringify(journey)).toBe(before);
  });

  it("applies each care action without changing play progression or core", () => {
    const journey = createJourney("care-actions", "2026-08-28T00:00:00.000Z");
    const expected = {
      greet: { energy: 82, calm: 85, curiosity: 54 },
      tend: { energy: 92, calm: 91, curiosity: 46 },
      rest: { energy: 100, calm: 83, curiosity: 56 },
      explore: { energy: 66, calm: 71, curiosity: 26 },
    } as const;

    for (const action of CARE_ACTION_ORDER) {
      const left = commitCareAction(journey, createCareIntent(journey, action), "2026-08-28T00:01:00.000Z");
      const right = commitCareAction(journey, createCareIntent(journey, action), "2026-08-28T00:01:00.000Z");
      expect(left).toEqual(right);
      expect(left.care).toMatchObject(expected[action]);
      expect(careHistory(left)).toHaveLength(1);
      expect(left.plays).toBe(journey.plays);
      expect(left.bond).toBe(journey.bond);
      expect(left.affinities).toEqual(journey.affinities);
      expect(left.expression).toBe(journey.expression);
      expect(playHistory(left)).toEqual(playHistory(journey));
      expect(left.core).toBe(CORE_CONTINUITY);
    }
  });

  it("keeps every care action available and clamps repeated choices safely", () => {
    let journey = createJourney("care-clamp", "2026-08-28T00:00:00.000Z");
    for (let index = 0; index < 12; index += 1) {
      journey = commitCareAction(
        journey,
        createCareIntent(journey, "explore"),
        new Date(Date.parse(journey.createdAt) + (index + 1) * 1_000).toISOString(),
      );
    }
    expect(journey.care).toMatchObject({ energy: 10, calm: 27, curiosity: 0 });
    for (const action of CARE_ACTION_ORDER) expect(() => createCareIntent(journey, action)).not.toThrow();
  });

  it("migrates v1 source-order play history and ignores invented care and aggregates", () => {
    const initial = createJourney("legacy-v1", "2026-08-28T00:00:00.000Z");
    const firstSession = collectFirstThree(initial);
    const first = commitSession(initial, firstSession, firstSession.proposals[0], "2026-08-28T00:01:00.000Z");

    // V1 generated later fields from the play count without binding prior choices into a lineage.
    const legacyProjection = { ...first, events: [] };
    const legacySession = collectFirstThree(legacyProjection);
    const secondTrace = {
      id: legacySession.id,
      play: legacySession.play,
      keptAt: "2026-08-28T00:02:00.000Z",
      fieldName: legacySession.fieldName,
      choice: legacySession.proposals[0],
      signals: legacySession.collected.map((id) => legacySession.echoes.find((echo) => echo.id === id)!.aura),
    };
    const restored = hydrateJourney({
      version: 1,
      seed: first.seed,
      createdAt: first.createdAt,
      traces: [legacyPlayTrace(playHistory(first)[0]), secondTrace],
      plays: 999,
      careStartedAt: "2099-01-01T00:00:00.000Z",
      careTraces: [{ id: "forged", sequence: 1, action: "rest", actedAt: "2099-01-01T00:00:00.000Z" }],
    });

    expect(restored?.version).toBe(3);
    expect(restored?.plays).toBe(2);
    expect(playHistory(restored!).map((event) => event.generator)).toEqual(["branching", "legacy"]);
    expect(careHistory(restored!)).toEqual([]);
    expect(restored?.careStartedAt).toBe("2026-08-28T00:02:00.000Z");
    expect(restored?.provenance).toMatchObject({ source: "migrated-v1", ordering: "source-order" });
  });

  it("migrates v2 lanes deterministically with play before care on equal timestamps", () => {
    let source = createJourney("legacy-v2-tie", "2026-08-28T00:00:00.000Z");
    const session = collectFirstThree(source);
    source = commitSession(source, session, session.proposals[0], "2026-08-28T00:01:00.000Z");
    source = commitCareAction(source, createCareIntent(source, "greet"), "2026-08-28T00:01:00.000Z");
    const fixture = v2Fixture(source);

    const left = hydrateJourney(fixture);
    const right = hydrateJourney(JSON.parse(JSON.stringify(fixture)));
    expect(left).toEqual(right);
    expect(eventKinds(left!)).toEqual(["play-commit", "care-action"]);
    expect(left?.provenance).toMatchObject({
      source: "migrated-v2",
      ordering: "timestamp-play-before-care",
      ambiguousEqualTimeTies: 1,
    });
    expect(left?.provenance.sourceDigest).toMatch(/^[0-9a-f]{64}$/);
  });

  it("migrates only the valid prefix of each v2 source lane", () => {
    let source = createJourney("legacy-v2-prefix", "2026-08-28T00:00:00.000Z");
    const session = collectFirstThree(source);
    source = commitSession(source, session, session.proposals[0], "2026-08-28T00:01:00.000Z");
    source = commitCareAction(source, createCareIntent(source, "greet"), "2026-08-28T00:02:00.000Z");
    source = commitCareAction(source, createCareIntent(source, "tend"), "2026-08-28T00:03:00.000Z");
    const fixture = v2Fixture(source);
    fixture.careTraces[1] = { ...fixture.careTraces[1], id: "care-forged" };

    const restored = hydrateJourney(fixture);
    expect(playHistory(restored!)).toHaveLength(1);
    expect(careHistory(restored!)).toHaveLength(1);
    expect(careHistory(restored!)[0].action).toBe("greet");
  });

  it("keeps care field-generation-neutral while invalidating stale open play proposals", () => {
    const journey = createJourney("care-field-boundary", "2026-08-28T00:00:00.000Z");
    const before = createPlaySession(journey);
    const cared = commitCareAction(journey, createCareIntent(journey, "greet"), "2026-08-28T00:01:00.000Z");
    const after = createPlaySession(cared);

    expect(after.seed).toBe(before.seed);
    expect(after.fieldName).toBe(before.fieldName);
    expect(after.echoes).toEqual(before.echoes);
    expect(after.staticZones).toEqual(before.staticZones);
    expect(after.sparks).toEqual(before.sparks);
    expect(after.baseRevision).not.toBe(before.baseRevision);
    let completeStale = before;
    for (const echo of before.echoes.slice(0, 3)) completeStale = collectEcho(completeStale, echo.id);
    expect(() => commitSession(cared, completeStale, completeStale.proposals[0])).toThrowError(/stale/);
  });

  it("rejects unsupported versions, invalid timestamps, and an unbound native care origin", () => {
    const journey = createJourney("care-invalid", "2026-08-28T00:00:00.000Z");
    expect(hydrateJourney({ ...JSON.parse(serializeJourney(journey)), version: 99 })).toBeNull();
    expect(hydrateJourney({ ...JSON.parse(serializeJourney(journey)), createdAt: "not-a-time" })).toBeNull();
    expect(hydrateJourney({ ...JSON.parse(serializeJourney(journey)), createdAt: undefined })).toBeNull();
    expect(
      hydrateJourney({ ...JSON.parse(serializeJourney(journey)), careStartedAt: "2026-08-28T00:00:01.000Z" }),
    ).toBeNull();
    expect(() => projectCare(journey.care, "not-a-time")).toThrowError(/canonical timestamps/);
    expect(() => commitCareAction(journey, createCareIntent(journey, "greet"), "not-a-time")).toThrowError(
      /canonical timestamp/,
    );
  });

  it("requires a migrated v3 care origin to survive in the accepted play prefix", () => {
    const initial = createJourney("migrated-care-origin", "2026-08-28T00:00:00.000Z");
    const session = collectFirstThree(initial);
    const played = commitSession(initial, session, session.proposals[0], "2026-08-28T00:01:00.000Z");
    const migrated = hydrateJourney({
      version: 1,
      seed: played.seed,
      createdAt: played.createdAt,
      traces: playHistory(played).map((event) => legacyPlayTrace(event)),
    })!;
    const authority = JSON.parse(serializeJourney(migrated));
    authority.events = [];

    expect(migrated.careStartedAt).toBe("2026-08-28T00:01:00.000Z");
    expect(hydrateJourney(authority)).toBeNull();
  });

  it("binds migration provenance to the v3 origin and revision", () => {
    const initial = createJourney("provenance-binding", "2026-08-28T00:00:00.000Z");
    const session = collectFirstThree(initial);
    const played = commitSession(initial, session, session.proposals[0], "2026-08-28T00:01:00.000Z");
    const migrated = hydrateJourney({
      version: 1,
      seed: played.seed,
      createdAt: played.createdAt,
      traces: playHistory(played).map((event) => legacyPlayTrace(event)),
    })!;
    const authority = JSON.parse(serializeJourney(migrated));
    authority.provenance.sourceDigest =
      authority.provenance.sourceDigest === "0".repeat(64) ? "1".repeat(64) : "0".repeat(64);
    const rebound = hydrateJourney(authority);

    expect(rebound).toBeNull();
  });

  it("recomputes migrated provenance instead of trusting self-attested counts and digests", () => {
    const migrated = hydrateJourney({
      version: 2,
      seed: "empty-provenance",
      createdAt: "2026-08-28T00:00:00.000Z",
      careStartedAt: "2026-08-28T00:00:00.000Z",
      traces: [],
      careTraces: [],
    })!;
    const forgedTies = JSON.parse(serializeJourney(migrated));
    forgedTies.provenance.ambiguousEqualTimeTies = 1;
    const forgedCount = JSON.parse(serializeJourney(migrated));
    forgedCount.provenance.migratedEventCount = 1;
    const forgedDigest = JSON.parse(serializeJourney(migrated));
    forgedDigest.provenance.sourceDigest = "0".repeat(64);

    expect(hydrateJourney(forgedTies)).toBeNull();
    expect(hydrateJourney(forgedCount)).toBeNull();
    expect(hydrateJourney(forgedDigest)).toBeNull();
  });
});
