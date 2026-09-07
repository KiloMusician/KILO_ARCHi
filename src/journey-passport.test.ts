import { describe, expect, it } from "vitest";
import {
  CORE_CONTINUITY,
  advanceRelayAttempt,
  collectEcho,
  commitCareAction,
  commitRelayCompletion,
  commitSession,
  createCareIntent,
  createJourney,
  createPlaySession,
  createRelayAttempt,
  deriveJourneyPassport,
  hashString,
  journeyOriginSha256,
  revisionForJourney,
  serializeJourney,
  type Journey,
  type JourneyPassport,
  type RelayAction,
} from "./model";
import { inspectJourneyArchive, serializeJourneyArchive } from "./journey-portability";

const createdAt = "2026-09-06T00:00:00.000Z";
const exportedAt = "2026-09-06T00:10:00.000Z";

function progressHistory(): Journey[] {
  const first = createJourney("passport-progress", createdAt);
  const cared = commitCareAction(first, createCareIntent(first, "greet"), "2026-09-06T00:01:00.000Z");
  let field = createPlaySession(cared);
  for (const echo of field.echoes.slice(0, 3)) field = collectEcho(field, echo.id);
  const played = commitSession(cared, field, field.proposals[0], "2026-09-06T00:02:00.000Z");
  const actions: RelayAction[] = [
    { type: "START" }, { type: "REDIRECT", node: 2 }, { type: "REDIRECT", node: 1 }, { type: "REDIRECT", node: 3 },
    { type: "INSPECT", id: "C" }, { type: "INSPECT", id: "A" }, { type: "INSPECT", id: "B" }, { type: "RESOLVE", id: "B" },
  ];
  const attempt = actions.reduce(advanceRelayAttempt, createRelayAttempt(played, "passport-relay-session"));
  const completed = commitRelayCompletion(played, attempt, attempt.sessionId, "2026-09-06T00:03:00.000Z");
  return [first, cared, played, completed];
}

describe("read-only Journey passport", () => {
  it("projects the existing full origin, display ID, creation time and revision with a fixed local core profile", () => {
    const journey = createJourney("m2-disposable-migration-opal", createdAt);
    const passport = deriveJourneyPassport(journey);
    expect(passport).toEqual({
      schema: "archi-journey-passport/v1",
      instanceID: "origin-c82faa6cb0b9e1dc0ef3a2b3827f4ae90925eb701737668f05864adc2ca3ead0",
      displayJourneyID: "ARCHI-A8BFA94B",
      createdAt,
      status: "local-only",
      coreProfile: { id: "archi-core-continuity", version: 1 },
      journeyRevision: revisionForJourney(journey),
    });
    expect(passport.instanceID).toBe(`origin-${journeyOriginSha256(journey)}`);
    expect(passport.instanceID).toMatch(/^origin-[0-9a-f]{64}$/);
    expect(passport).not.toHaveProperty("seed");
    expect(passport).not.toHaveProperty("events");
    expect(passport).not.toHaveProperty("bond");
    expect(passport).not.toHaveProperty("appearance");
    expect(passport).not.toHaveProperty("permissions");
  });

  it("keeps one origin through care, changed expression, Relay and v3/v4 archive round trips", () => {
    const history = progressHistory();
    const firstPassport = deriveJourneyPassport(history[0]);
    expect(history.map((journey) => journey.version)).toEqual([3, 3, 3, 4]);
    expect(history[2].expression).not.toBe(history[1].expression);
    for (const journey of history) {
      const before = serializeJourney(journey);
      const beforeArchive = serializeJourneyArchive(journey, exportedAt);
      const eventIDs = journey.events.map((event) => event.eventId);
      const passport = deriveJourneyPassport(journey);
      expect(passport).toEqual({ ...firstPassport, journeyRevision: revisionForJourney(journey) });
      expect(serializeJourney(journey)).toBe(before);
      expect(journey.events.map((event) => event.eventId)).toEqual(eventIDs);
      expect(serializeJourneyArchive(journey, exportedAt)).toBe(beforeArchive);
      const imported = inspectJourneyArchive(beforeArchive);
      expect(imported.status).toBe("valid");
      if (imported.status !== "valid") throw new Error("Expected valid archive fixture");
      expect(deriveJourneyPassport(imported.preview.journey)).toEqual(passport);
      expect(serializeJourney(imported.preview.journey)).toBe(before);
    }
    expect(new Set(history.map((journey) => deriveJourneyPassport(journey).journeyRevision)).size).toBe(history.length);
  });

  it("does not mint another individual for copied same-origin archives or an earlier saved revision", () => {
    const history = progressHistory();
    const latest = deriveJourneyPassport(history.at(-1)!);
    for (const journey of [history[0], history.at(-1)!]) {
      const archive = serializeJourneyArchive(journey, exportedAt);
      const left = inspectJourneyArchive(archive);
      const right = inspectJourneyArchive(archive);
      if (left.status !== "valid" || right.status !== "valid") throw new Error("Expected valid archive fixtures");
      expect(deriveJourneyPassport(left.preview.journey)).toEqual(deriveJourneyPassport(right.preview.journey));
      expect(deriveJourneyPassport(left.preview.journey).instanceID).toBe(latest.instanceID);
    }
    expect(deriveJourneyPassport(history[0]).journeyRevision).not.toBe(latest.journeyRevision);
  });

  it("keeps distinct full origins for a real collision in the familiar 32-bit display ID", () => {
    // Deterministic FNV-1a collision fixtures, not mocked IDs or generated individuals.
    const seedOne = "passport-collision-84199";
    const seedTwo = "passport-collision-102026";
    expect(hashString(seedOne)).toBe(hashString(seedTwo));
    const one = deriveJourneyPassport(createJourney(seedOne, createdAt));
    const two = deriveJourneyPassport(createJourney(seedTwo, createdAt));
    expect(one.displayJourneyID).toBe("ARCHI-5ECEB4DE");
    expect(two.displayJourneyID).toBe(one.displayJourneyID);
    expect(one.instanceID).not.toBe(two.instanceID);
    expect(one.journeyRevision).not.toBe(two.journeyRevision);
  });

  it("distinguishes different creation origins even when their seed and display ID match", () => {
    const first = deriveJourneyPassport(createJourney("same-seed", createdAt));
    const later = deriveJourneyPassport(createJourney("same-seed", "2026-09-06T00:00:01.000Z"));
    expect(first.displayJourneyID).toBe(later.displayJourneyID);
    expect(first.instanceID).not.toBe(later.instanceID);
    expect(first.createdAt).not.toBe(later.createdAt);
  });

  it("ignores forged derived display/core fields and derives from admitted event authority", () => {
    const journey = progressHistory().at(-1)!;
    const forged = {
      ...journey,
      id: "ARCHI-FORGED",
      core: { ...CORE_CONTINUITY, identity: "FORGED" },
      plays: 999,
      bond: 999,
    } as unknown as Journey;
    expect(deriveJourneyPassport(forged)).toEqual(deriveJourneyPassport(journey));
    expect(forged.id).toBe("ARCHI-FORGED");
    expect(forged.plays).toBe(999);
  });

  it.each([1, 3])("rejects incomplete authority at history index %s rather than issuing a prefix passport", (index) => {
    const journey = progressHistory()[index];
    const damaged = {
      ...journey,
      events: [...journey.events, { ...journey.events[0], eventId: "damaged" }],
    };
    const before = serializeJourney(damaged);
    expect(() => deriveJourneyPassport(damaged)).toThrow(/complete valid event chain/i);
    expect(serializeJourney(damaged)).toBe(before);
  });

  it("rejects unsupported authority and never promotes a mere v4 label to an identity projection", () => {
    const journey = createJourney("unsupported-passport", createdAt);
    expect(() => deriveJourneyPassport({ ...journey, version: 99 } as unknown as Journey)).toThrow(/supported event authority/i);
    expect(() => deriveJourneyPassport({ ...journey, version: 4 })).toThrow(/complete valid event chain/i);
  });

  it("freezes both projection levels and keeps an earlier readback unchanged when progress advances", () => {
    const [journey, later] = progressHistory();
    const before = serializeJourney(journey);
    const passport = deriveJourneyPassport(journey);
    const original = JSON.stringify(passport);
    expect(Object.isFrozen(passport)).toBe(true);
    expect(Object.isFrozen(passport.coreProfile)).toBe(true);
    expect(() => { (passport as { displayJourneyID: string }).displayJourneyID = "changed"; }).toThrow();
    expect(() => { (passport.coreProfile as { version: number }).version = 2; }).toThrow();
    const laterPassport: JourneyPassport = deriveJourneyPassport(later);
    expect(laterPassport.instanceID).toBe(passport.instanceID);
    expect(laterPassport.journeyRevision).not.toBe(passport.journeyRevision);
    expect(JSON.stringify(passport)).toBe(original);
    expect(serializeJourney(journey)).toBe(before);
  });
});
