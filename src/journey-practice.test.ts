import { describe, expect, it } from "vitest";
import {
  BATTLE_LIMITS, choosePracticeCommand, createBattle, createBattleCommand,
  replayCompletedPractice, resolveBattleRound,
  type BattleCommand, type BattleTeamSetup, type PracticeReplay,
} from "./battle-engine";
import {
  MAX_KEPT_PRACTICES, advanceRelayAttempt, commitCareAction, commitPracticeCompletion,
  commitRelayCompletion, createCareIntent, createJourney, createRelayAttempt,
  derivePracticeSummaries, hydrateJourney, journeyOriginSha256, revisionForJourney,
  serializeJourney, sha256String, stageForJourney,
  type Journey, type PracticeAttempt, type RelayAction,
} from "./model";
import { inspectJourneyArchive, serializeJourneyArchive } from "./journey-portability";

const createdAt = "2026-09-06T00:00:00.000Z";
const completedAt = "2026-09-06T00:03:00.000Z";
const exportedAt = "2026-09-06T00:10:00.000Z";
const sessionId = "11111111-1111-4111-8111-111111111111";
const uuid = (index: number) => `00000000-0000-4000-8000-${String(index).padStart(12, "0")}`;
const copy = <T>(value: T): T => JSON.parse(JSON.stringify(value)) as T;

function completeReplay(index = 1): PracticeReplay {
  const teams: [BattleTeamSetup, BattleTeamSetup] = [
    { id: "one", label: "ARCHi", bondRole: "scout", roster: [{ id: "one-scout", name: "Scout", role: "scout" }] },
    { id: "two", label: "Practice partner", bondRole: "guardian", roster: [{ id: "two-guardian", name: "Guardian", role: "guardian" }] },
  ];
  let state = createBattle(uuid(index), ...teams);
  const commands: [BattleCommand, BattleCommand][] = [];
  while (state.status === "active" && commands.length < BATTLE_LIMITS.maximumRounds) {
    const pair: [BattleCommand, BattleCommand] = [choosePracticeCommand(state, "one"), choosePracticeCommand(state, "two")];
    const result = resolveBattleRound(state, ...pair);
    if (!result.accepted) throw new Error(result.reason);
    commands.push(pair); state = result.state;
  }
  if (state.status !== "complete") throw new Error("Fixture did not complete within the production round limit");
  return { rulesVersion: 1, battleId: state.battleId, teams, commands };
}

function attempt(journey: Journey, index = 1): PracticeAttempt {
  return { originDigest: journeyOriginSha256(journey), baseRevision: revisionForJourney(journey),
    sessionId, replay: completeReplay(index) };
}

function keep(journey: Journey, index = 1): Journey {
  return commitPracticeCompletion(journey, attempt(journey, index), sessionId, completedAt);
}

function withRelay(journey: Journey): Journey {
  const actions: RelayAction[] = [
    { type: "START" }, { type: "REDIRECT", node: 2 }, { type: "REDIRECT", node: 1 }, { type: "REDIRECT", node: 3 },
    { type: "INSPECT", id: "A" }, { type: "INSPECT", id: "B" }, { type: "INSPECT", id: "C" }, { type: "RESOLVE", id: "B" },
  ];
  const solved = actions.reduce(advanceRelayAttempt, createRelayAttempt(journey, "practice-relay"));
  return commitRelayCompletion(journey, solved, solved.sessionId, completedAt);
}

function rehashPractice(event: Record<string, any>): void {
  event.eventId = `event-${event.sequence}-${sha256String(JSON.stringify([
    "journey-event-v4", event.previousEventId, event.sequence, event.committedAt,
    event.kind, event.originDigest, event.baseRevision, event.sessionId, event.replay,
  ]))}`;
}

describe("Journey-owned completed practice", () => {
  it("replays the same legal non-surrender rounds and derives a detached immutable outcome", () => {
    const replay = completeReplay();
    const before = JSON.stringify(replay);
    const verified = replayCompletedPractice(replay);
    expect(verified.state.status).toBe("complete");
    expect(verified.state.history.map((round) => round.commands)).toEqual(replay.commands);
    expect(verified.digest).toBe(sha256String(JSON.stringify(verified.replay)));
    expect(verified).toEqual(replayCompletedPractice(copy(replay)));
    expect(JSON.stringify(replay)).toBe(before);
    expect(Object.isFrozen(verified.replay)).toBe(true);
    expect(Object.isFrozen(verified.replay.commands[0])).toBe(true);
    expect(Object.isFrozen(verified.replay.teams[0].roster[0])).toBe(true);
    const mutable = replay as any;
    mutable.commands[0][0] = { ...mutable.commands[0][0], action: "surrender" };
    expect(verified.replay.commands[0][0].action).not.toBe("surrender");
  });

  it.each([
    ["unsupported rules", (value: any) => { value.rulesVersion = 2; }],
    ["foreign result field", (value: any) => { value.winner = "one"; }],
    ["non-UUID battle", (value: any) => { value.battleId = "local-practice-1"; }],
    ["missing round", (value: any) => { value.commands.pop(); }],
    ["extra terminal round", (value: any) => { value.commands.push(value.commands.at(-1)); }],
    ["over-budget replay", (value: any) => { value.commands = Array.from({ length: 21 }, () => value.commands[0]); }],
    ["stale command", (value: any) => { value.commands[0][0].baseRevision = "sha256:wrong"; }],
    ["invented command field", (value: any) => { value.commands[0][0].reward = 500; }],
    ["reordered teams", (value: any) => { value.teams.reverse(); }],
    ["invented member stats", (value: any) => { value.teams[0].roster[0].integrity = 999; }],
    ["sparse rounds", (value: any) => { delete value.commands[0]; }],
  ] as const)("rejects %s without accepting submitted outcome authority", (_name, damage) => {
    const replay = copy(completeReplay()); damage(replay);
    expect(() => replayCompletedPractice(replay)).toThrow();
  });

  it("rejects a legal opponent command that was not chosen by the public-state partner", () => {
    const replay = copy(completeReplay());
    const initial = createBattle(replay.battleId, ...replay.teams);
    const expected = choosePracticeCommand(initial, "two");
    const other = createBattleCommand(initial, "two", expected.action === "guard" ? "pulse" : "guard");
    expect(resolveBattleRound(initial, replay.commands[0][0], other).accepted).toBe(true);
    const commands = replay.commands.map((pair) => [...pair] as [BattleCommand, BattleCommand]);
    commands[0][1] = other;
    expect(() => replayCompletedPractice({ ...replay, commands })).toThrow(/public-state practice partner/);
  });

  it("rejects surrender and accessor-backed input without reading its getter", () => {
    const replay = completeReplay();
    const initial = createBattle(replay.battleId, ...replay.teams);
    const surrender = { ...replay, commands: [[createBattleCommand(initial, "one", "surrender"), choosePracticeCommand(initial, "two")]] };
    expect(() => replayCompletedPractice(surrender)).toThrow(/non-surrender/);
    let reads = 0;
    const accessor = { ...replay };
    Object.defineProperty(accessor, "rulesVersion", { enumerable: true, get() { reads += 1; throw new Error("Getter ran"); } });
    expect(() => replayCompletedPractice(accessor)).toThrow(/Invalid practice replay/);
    expect(reads).toBe(0);
  });

  it("adds one explicit receipt with no care, field, identity or appearance reward", () => {
    const journey = createJourney("practice-no-reward", createdAt);
    const before = serializeJourney(journey);
    const reviewed = attempt(journey);
    expect(derivePracticeSummaries(journey)).toEqual([]);
    const kept = commitPracticeCompletion(journey, reviewed, sessionId, completedAt);
    expect(serializeJourney(journey)).toBe(before);
    expect(kept.version).toBe(5);
    expect(kept.events).toHaveLength(1);
    expect(kept.events[0]).toMatchObject({ schema: 4, kind: "practice-complete", originDigest: reviewed.originDigest,
      baseRevision: reviewed.baseRevision, sessionId, committedAt: completedAt });
    expect([kept.id, kept.seed, kept.provenance, kept.core, kept.plays, kept.bond, kept.expression, kept.affinities, kept.care])
      .toEqual([journey.id, journey.seed, journey.provenance, journey.core, journey.plays, journey.bond, journey.expression, journey.affinities, journey.care]);
    expect(stageForJourney(kept)).toEqual(stageForJourney(journey));
    expect(journeyOriginSha256(kept)).toBe(reviewed.originDigest);
    const verified = replayCompletedPractice(reviewed.replay);
    expect(derivePracticeSummaries(kept)).toEqual([{ originDigest: reviewed.originDigest,
      eventId: kept.events[0].eventId, battleId: reviewed.replay.battleId, rulesVersion: 1,
      rounds: verified.state.history.length, outcome: verified.state.winner === "one" ? "won" : verified.state.winner === "two" ? "lost" : "draw",
      replayDigest: verified.digest, committedAt: completedAt }]);
  });

  it("makes exact duplicate Keep harmless after later care but rejects reused battle IDs", () => {
    const journey = createJourney("practice-idempotence", createdAt), reviewed = attempt(journey);
    const kept = commitPracticeCompletion(journey, reviewed, sessionId, completedAt);
    expect(commitPracticeCompletion(kept, copy(reviewed), sessionId, exportedAt)).toBe(kept);
    const cared = commitCareAction(kept, createCareIntent(kept, "greet"), exportedAt);
    expect(commitPracticeCompletion(cared, reviewed, sessionId, exportedAt)).toBe(cared);
    expect(derivePracticeSummaries(cared)).toHaveLength(1);
    expect(() => commitPracticeCompletion(cared, { ...reviewed, baseRevision: revisionForJourney(cared) }, sessionId, exportedAt)).toThrow(/already uses/);
    const changed = { ...reviewed, sessionId: uuid(998) };
    expect(() => commitPracticeCompletion(cared, changed, changed.sessionId, exportedAt)).toThrow(/already uses/);
  });

  it("rejects stale origin, source revision, session and extra input fields without altering history", () => {
    const journey = createJourney("practice-fences", createdAt), reviewed = attempt(journey);
    const before = serializeJourney(journey);
    const foreign = createJourney("another-practice-origin", createdAt);
    expect(() => commitPracticeCompletion(foreign, reviewed, sessionId, completedAt)).toThrow(/Journey\/session/);
    expect(() => commitPracticeCompletion(journey, reviewed, uuid(99), completedAt)).toThrow(/Journey\/session/);
    expect(() => commitPracticeCompletion(journey, { ...reviewed, sessionId: "not-a-uuid" }, "not-a-uuid", completedAt)).toThrow();
    expect(() => commitPracticeCompletion(journey, { ...reviewed, originDigest: "0".repeat(64) }, sessionId, completedAt)).toThrow();
    expect(() => commitPracticeCompletion(journey, { ...reviewed, baseRevision: "stale" }, sessionId, completedAt)).toThrow(/Journey changed/);
    expect(() => commitPracticeCompletion(journey, { ...reviewed, reward: true } as PracticeAttempt, sessionId, completedAt)).toThrow();
    const cared = commitCareAction(journey, createCareIntent(journey, "greet"), completedAt);
    expect(() => commitPracticeCompletion(cared, reviewed, sessionId, exportedAt)).toThrow(/Journey changed/);
    expect(serializeJourney(journey)).toBe(before);
  });

  it("bounds retained practice events without evicting earlier history", () => {
    const origin = createJourney("practice-cap", createdAt);
    const authority = JSON.parse(serializeJourney(origin));
    authority.version = 5;
    let previousEventId = `origin-${journeyOriginSha256(origin)}`;
    // A near-limit saved chain avoids repeatedly hydrating all earlier events
    // while still exercising production hydration and both Keep boundary cases.
    for (let index = 1; index < MAX_KEPT_PRACTICES; index += 1) {
      const event: Record<string, any> = { schema: 4, kind: "practice-complete", sequence: index,
        previousEventId, committedAt: completedAt, originDigest: journeyOriginSha256(origin),
        baseRevision: `${origin.id}:${index - 1}:${previousEventId}`, sessionId, replay: completeReplay(index) };
      rehashPractice(event); authority.events.push(event); previousEventId = event.eventId;
    }
    const loaded = hydrateJourney(authority);
    if (!loaded) throw new Error("Near-limit archive fixture must replay completely");
    expect(derivePracticeSummaries(loaded)).toHaveLength(MAX_KEPT_PRACTICES - 1);
    const journey = keep(loaded, MAX_KEPT_PRACTICES);
    const before = serializeJourney(journey), first = journey.events[0];
    expect(derivePracticeSummaries(journey)).toHaveLength(64);
    expect(() => keep(journey, 65)).toThrow(/limit/);
    expect(serializeJourney(journey)).toBe(before);
    expect(journey.events[0]).toEqual(first);
  });

  it("round-trips v5 archives while retaining unchanged v3/v4 compatibility and origin", () => {
    const v3 = createJourney("practice-portability", createdAt), v4 = withRelay(v3);
    for (const baseline of [v3, v4]) {
      const oldBytes = serializeJourney(baseline), oldArchive = serializeJourneyArchive(baseline, exportedAt);
      const kept = keep(baseline);
      expect(serializeJourney(baseline)).toBe(oldBytes);
      expect(serializeJourneyArchive(baseline, exportedAt)).toBe(oldArchive);
      expect(kept.events.slice(0, -1)).toEqual(baseline.events);
      expect(journeyOriginSha256(kept)).toBe(journeyOriginSha256(baseline));
      for (const value of [baseline, kept]) {
        const inspection = inspectJourneyArchive(serializeJourneyArchive(value, exportedAt));
        expect(inspection.status).toBe("valid");
        if (inspection.status !== "valid") throw new Error(inspection.message);
        expect(serializeJourney(inspection.preview.journey)).toBe(serializeJourney(value));
        expect(derivePracticeSummaries(inspection.preview.journey)).toEqual(derivePracticeSummaries(value));
      }
      expect(hydrateJourney({ ...JSON.parse(oldBytes), version: 5 })).toBeNull();
    }
    const afterPracticeThenRelay = withRelay(keep(v3));
    expect(afterPracticeThenRelay.version).toBe(5);
    expect(hydrateJourney(JSON.parse(serializeJourney(afterPracticeThenRelay)))).toEqual(afterPracticeThenRelay);
  });

  it.each(["rules", "command", "origin", "base", "outcome"] as const)("rejects forged %s even after recomputing the event hash", (kind) => {
    const saved = JSON.parse(serializeJourney(keep(createJourney("practice-tamper", createdAt))));
    const event = saved.events[0];
    if (kind === "rules") event.replay.rulesVersion = 2;
    if (kind === "command") event.replay.commands[0][0].baseRevision = "sha256:forged";
    if (kind === "origin") event.originDigest = "0".repeat(64);
    if (kind === "base") event.baseRevision = "forged";
    if (kind === "outcome") event.outcome = "won";
    rehashPractice(event);
    expect(hydrateJourney(saved)).toBeNull();
  });

  it.each([1, 2] as const)("rejects a practice falsely included in a v%s migrated prefix with coherent hashes", (version) => {
    const kept = keep(createJourney("practice-false-migration", createdAt));
    const authority = JSON.parse(serializeJourney(kept));
    authority.provenance = { source: `migrated-v${version}`, ordering: version === 1 ? "source-order" : "timestamp-play-before-care",
      ambiguousEqualTimeTies: 0, migratedEventCount: 0,
      sourceDigest: sha256String(JSON.stringify([`v${version}`, createdAt, [], []])) };
    const rebind = (count: number): void => {
      authority.provenance.migratedEventCount = count;
      const p = authority.provenance;
      const origin = sha256String(JSON.stringify(["journey-v3-origin", authority.seed, createdAt, createdAt,
        p.source, p.ordering, p.ambiguousEqualTimeTies, count, p.sourceDigest]));
      const event = authority.events[0];
      event.originDigest = origin; event.previousEventId = `origin-${origin}`;
      event.baseRevision = `${kept.id}:0:origin-${origin}`;
      rehashPractice(event);
    };
    rebind(0);
    expect(hydrateJourney(authority), "The fixture has a valid empty migrated prefix before the forged count").not.toBeNull();
    rebind(1);
    expect(() => replayCompletedPractice(authority.events[0].replay)).not.toThrow();
    expect(hydrateJourney(authority)).toBeNull();
    const envelope = JSON.parse(serializeJourneyArchive(kept, exportedAt));
    envelope.authority = authority;
    envelope.manifest = { journeyId: kept.id, revision: `${kept.id}:1:${authority.events[0].eventId}`,
      eventCount: 1, headEventId: authority.events[0].eventId, authoritySha256: sha256String(JSON.stringify(authority)) };
    expect(inspectJourneyArchive(JSON.stringify(envelope)).status).toBe("invalid");
  });
});
