import { describe, expect, it } from "vitest";
import { buildBattleReadback, type BattleResultRetention } from "./battle-readback";
import { BATTLE_LIMITS, createBattle, createBattleCommand, resolveBattleRound,
  type BattleAction, type BattleState, type BattleTeamSetup } from "./battle-engine";
import { compareBattleChoices, displayedBattleRound } from "./battle-presentation";
import { connectDesktopHost, type DesktopJourneyProjection } from "./desktop-host";
import { ROLE_ORDER, createJourney, journeyOriginSha256, revisionForJourney, type RoleId } from "./model";

const battleId = "12345678-abcd-4abc-8abc-123456789abc";
const retention: BattleResultRetention = { status: "unsaved", message: "Keep this practice in Journey." };
function setup(id: "one" | "two", role: RoleId, count = 1): BattleTeamSetup {
  return { id, label: `${id} team`, bondRole: role, roster: Array.from({ length: count }, (_, index) => ({
    id: `${id}-${index}`, name: `${id} member ${index}`, role,
  })) };
}
function battle(one: RoleId = "hearth", two: RoleId = "guardian", count = 1): BattleState {
  return createBattle(battleId, setup("one", one, count), setup("two", two, count));
}
function round(state: BattleState, one: BattleAction, two: BattleAction, target?: string): BattleState {
  const resolved = resolveBattleRound(state, createBattleCommand(state, "one", one, target), createBattleCommand(state, "two", two));
  expect(resolved.accepted).toBe(true);
  return resolved.state;
}

describe("native public battle readback", () => {
  it("matches public resources and active/reserve flags without modifying the engine or exposing command data", () => {
    const state = round(battle("beacon", "guardian", 3), "swap", "pulse", "one-1");
    const before = JSON.stringify(state);
    const view = buildBattleReadback(state, retention);
    for (const [index, team] of view.teams.entries()) {
      const actual = state.teams[index];
      expect(team).toEqual({ id: actual.id, label: actual.label, spark: actual.spark,
        roster: actual.roster.map(({ id, name, role, integrity, maximumIntegrity, exposed }) => ({
          id, name, role, integrity, maximumIntegrity, exposed, active: id === actual.activeQiMonId,
        })) });
    }
    expect(view.teams[0].roster.map((member) => member.active)).toEqual([false, true, false]);
    expect(view.rounds[0].summary).toContain("reserve took impact on entry");
    expect(view.result).toBeNull();
    expect(JSON.stringify(view)).not.toMatch(/commands|baseRevision|activeQiMonId|policy|sealed/);
    expect(JSON.stringify(state)).toBe(before);
    expect(Object.isFrozen(view)).toBe(true);
    expect(Object.isFrozen(view.teams[0].roster[0])).toBe(true);
    expect(Object.isFrozen(view.rounds[0])).toBe(true);
    expect(view.teams[0].roster[0]).not.toBe(state.teams[0].roster[0]);
  });

  it.each(ROLE_ORDER)("explains resolved %s signature effects and Spark from actual outcomes", (role) => {
    let state = round(battle(role, "scout"), "guard", "signature");
    state = round(state, "signature", "pulse");
    const outcome = state.history[1].outcomes[0];
    const view = buildBattleReadback(state, retention);
    const summary = view.rounds[1].summary;
    expect(view.teams[0].spark).toBe(2);
    expect(summary).toContain(`impact taken ${outcome.damageTaken}, blocked ${outcome.damageAbsorbed}`);
    expect(summary).toContain(`sent ${outcome.damageDealt} before shields`);
    expect(summary).toContain("spent 1 Spark");
    if (outcome.integrityRestored) expect(summary).toContain(`restored ${outcome.integrityRestored}`);
    if (outcome.selfDamage) expect(summary).toContain(`self-cost ${outcome.selfDamage}`);
    if (outcome.exposedApplied) expect(summary).toContain("marked other side");
    if (outcome.exposedCleared) expect(summary).toContain("cleared exposure");
    expect(new TextEncoder().encode(summary).length).toBeLessThanOrEqual(500);
  });

  it("distinguishes blocked impact, a Passage after impact, and replacement after settling", () => {
    const guarded = round(battle(), "pulse", "guard");
    expect(buildBattleReadback(guarded, retention).rounds[0].summary).toContain("impact taken 0, blocked");
    const passage = round(battle("beacon", "hearth", 3), "signature", "pulse", "one-1");
    expect(buildBattleReadback(passage, retention).rounds[0].summary).toContain("reserve entered after impact");
    expect(buildBattleReadback(passage, retention).teams[0].roster[1].active).toBe(true);
    let state = battle("hearth", "muse", 3);
    state = round(state, "pulse", "signature");
    state = round(state, "pulse", "pulse");
    const view = buildBattleReadback(state, retention);
    expect(view.rounds.at(-1)!.summary).toContain("settled active replaced");
    expect(view.teams[0].roster[0]).toMatchObject({ active: false, integrity: 0 });
  });

  it("does not claim the other move executed when surrender ended the round", () => {
    const state = round(battle(), "surrender", "signature");
    const view = buildBattleReadback(state, { status: "unavailable", message: "An early ending cannot be kept." });
    expect(view.rounds[0].summary).toBe("Side 1 surrendered. The other side's move did not execute.");
    expect(view.teams[1].spark).toBe(3);
    expect(view.result).toMatchObject({ winner: "two", reason: "surrender", retention: "unavailable" });
    expect(buildBattleReadback(round(battle(), "surrender", "surrender"), retention).result?.winner).toBe("draw");
  });

  it("reports elimination and all result retention states without changing the resolved match", () => {
    let state = battle("muse", "hearth");
    while (state.status === "active") state = round(state, "pulse", "pulse");
    const before = JSON.stringify(state);
    for (const status of ["unsaved", "saving", "saved", "session-only", "unavailable"] as const) {
      const view = buildBattleReadback(state, { status, message: `Result ${status}` });
      expect(view.result).toEqual({ winner: state.winner, reason: "eliminated", retention: status, message: `Result ${status}` });
      expect(view.rounds).toHaveLength(state.history.length);
      expect(Object.isFrozen(view.result)).toBe(true);
    }
    expect(JSON.stringify(state)).toBe(before);
  });

  it("fits the longest legal history, comparison choices and saved summaries inside the existing transport budget", () => {
    const longSetup = (id: "one" | "two"): BattleTeamSetup => ({ ...setup(id, "beacon", 3), label: "蝶".repeat(28),
      roster: setup(id, "beacon", 3).roster.map((card) => ({ ...card, name: "蝶".repeat(28) })) });
    let state = createBattle(battleId, longSetup("one"), longSetup("two"));
    for (let index = 0; index < 19; index += 1) state = round(state, "guard", "guard");
    const readback = buildBattleReadback(state, retention);
    const whatIf = compareBattleChoices(state, "one", "one:pulse", "one:guard")!;
    expect(whatIf.choices).toHaveLength(7);
    expect(whatIf.cases).toHaveLength(7);
    const messages: DesktopJourneyProjection[] = [];
    const host = connectDesktopHost({ __ARCHI_DESKTOP_BOOTSTRAP__: { version: 1, host: "archi-desktop", sessionId: battleId, visible: true },
      webkit: { messageHandlers: { archiJourneyProjection: { postMessage: (value) => { messages.push(value); } } } } })!;
    const journey = createJourney("readback-budget", "2026-09-08T12:00:00.000Z");
    const common = { readiness: "ready" as const, storage: "local-browser" as const, mode: "battle" as const,
      journeyId: journey.id, revision: revisionForJourney(journey), eventCount: 8, originDigest: journeyOriginSha256(journey),
      practices: Array.from({ length: 8 }, (_, index) => ({ originDigest: journeyOriginSha256(journey), eventId: `event-${index + 1}-${"c".repeat(64)}`,
        battleId, rulesVersion: 1 as const, rounds: 20, outcome: "draw" as const, replayDigest: "d".repeat(64), committedAt: "2026-09-08T12:00:00.000Z" })) };
    const actions = [...whatIf.choices, ...whatIf.choices.map((choice) => ({ ...choice, id: `what-if:first:${choice.id}` })),
      ...whatIf.choices.map((choice) => ({ ...choice, id: `what-if:second:${choice.id}` })),
      { id: "leave", label: "Return to Habitat", detail: "Leave practice." }];
    expect(host.publish({ ...common, arena: { battleId, revision: "e".repeat(64), phase: "planning", round: 20,
      summary: "Round 20.", actions, whatIf, readback } })).toBe(true);
    expect(new TextEncoder().encode(JSON.stringify(messages.at(-1))).length).toBeLessThan(32_768);
    state = round(state, "guard", "guard");
    const finished = buildBattleReadback(state, retention);
    expect(finished.result).toMatchObject({ winner: "draw", reason: "round-limit" });
    expect(finished.rounds).toHaveLength(BATTLE_LIMITS.maximumRounds);
    expect(host.publish({ ...common, arena: { battleId, revision: "f".repeat(64), phase: "finished", round: displayedBattleRound(state),
      summary: "Practice complete.", actions: [], whatIf: null, readback: finished } })).toBe(true);
  });
});
