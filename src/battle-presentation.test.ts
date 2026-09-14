import { describe, expect, it, vi } from "vitest";
import * as battleEngine from "./battle-engine";
import { BATTLE_ACTIONS, choosePracticeCommand, createBattle, createBattleCommand, resolveBattleRound,
  type BattleAction, type BattleState, type BattleTeamId, type BattleTeamSetup } from "./battle-engine";
import { compareBattleChoices, describeBattleAction, displayedBattleRound, listBattleChoices } from "./battle-presentation";
import { ROLE_ORDER, type RoleId } from "./model";

const setup = (id: BattleTeamId, role: "scout" | "muse" | "guardian" = "scout"): BattleTeamSetup => ({
  id, label: id, bondRole: role, roster: [{ id: `${id}-qimon`, name: role, role }],
});

const formation = (id: BattleTeamId, roles: readonly RoleId[]): BattleTeamSetup => ({
  id, label: id === "one" ? "Player" : "Partner", bondRole: roles[0],
  roster: roles.map((role, index) => ({ id: `${id}-member-${index}`, name: `${role} ${index + 1}`, role })),
});
function field(one: readonly RoleId[], two: readonly RoleId[]): BattleState {
  return createBattle("what-if", formation("one", one), formation("two", two));
}
function applyRound(state: BattleState, one: BattleAction, two: BattleAction, oneTarget?: string, twoTarget?: string) {
  const result = resolveBattleRound(state, createBattleCommand(state, "one", one, oneTarget),
    createBattleCommand(state, "two", two, twoTarget));
  if (!result.accepted) throw new Error(result.reason);
  return result.state;
}
function expectFrozen(value: unknown): void {
  if (!value || typeof value !== "object") return;
  expect(Object.isFrozen(value)).toBe(true);
  for (const child of Object.values(value)) expectFrozen(child);
}
/** Match the displayed quantities against the accepted reducer event, including shield semantics. */
function expectReportedResult(state: BattleState, player: BattleTeamId, choiceId: string, opponentId: string, summary: string) {
  const chosen = listBattleChoices(state, player).find((choice) => choice.id === choiceId)!;
  const opposing = listBattleChoices(state, player === "one" ? "two" : "one").find((choice) => choice.id === opponentId)!;
  const result = player === "one" ? resolveBattleRound(state, chosen.command, opposing.command) :
    resolveBattleRound(state, opposing.command, chosen.command);
  expect(result.accepted).toBe(true);
  if (!result.accepted) throw new Error(result.reason);
  result.state.teams.forEach((team, index) => {
    const side = team.id === player ? "Your side" : "Other side";
    const outcome = result.event.outcomes[index];
    const section = summary.slice(summary.indexOf(`${side}:`)).split(".")[0];
    expect(section).toContain(`team integrity ${battleEngine.teamIntegrity(team)}/36`);
    expect(section).toContain(`Spark ${team.spark}`);
    expect(section).toContain(`impact taken ${outcome.damageTaken}, absorbed ${outcome.damageAbsorbed}`);
    if (outcome.damageDealt) expect(section).toContain(`impact sent ${outcome.damageDealt} before shields`);
    if (outcome.integrityRestored) expect(section).toContain(`restored ${outcome.integrityRestored}`);
    if (outcome.selfDamage) expect(section).toContain(`self-cost ${outcome.selfDamage}`);
    if (outcome.sparkSpent) expect(section).toContain(`spent ${outcome.sparkSpent} Spark`);
    expect(section.includes("marks opponent")).toBe(outcome.exposedApplied);
    expect(section.includes("clears own exposure")).toBe(outcome.exposedCleared);
    if (outcome.action === "swap") expect(section).toContain("reserve takes impact on entry");
    if (outcome.action === "signature" && outcome.targetQiMonId && team.activeQiMonId === outcome.targetQiMonId) {
      expect(section).toContain("reserve enters after impact");
    }
    if (outcome.replacementQiMonId) expect(section).toContain("settled active replaced");
  });
  if (result.state.winner) expect(summary).toContain(result.state.winner === "draw" ? "Encounter ends in a draw." :
    `${result.state.winner === player ? "Your side" : "Other side"} wins the encounter.`);
  else expect(summary).not.toContain("encounter");
  expect(new TextEncoder().encode(summary).length).toBeLessThanOrEqual(700);
  expect(summary).not.toMatch(/probably|likely|probability|best move|recommend|\d%/i);
}

describe("Bounded public-state Arena move comparisons", () => {
  it("lists exactly legal non-surrender choices, including every living Beacon passage and swap target", () => {
    const state = field(["beacon", "hearth", "scout"], ["keeper"]);
    const choices = listBattleChoices(state, "one");
    expect(choices.map((choice) => choice.id)).toEqual([
      "one:pulse", "one:guard", "one:signature", "one:signature:one-member-1", "one:signature:one-member-2",
      "one:swap:one-member-1", "one:swap:one-member-2",
    ]);
    expectFrozen(choices);
    for (const choice of choices) {
      expect(choice.command.baseRevision).toBe(battleEngine.battleRevision(state));
      expect(battleEngine.previewBattleCommand(state, choice.command)).not.toBeNull();
      expect(choice.command.action).not.toBe("surrender");
      expect(new TextEncoder().encode(choice.label).length).toBeLessThanOrEqual(120);
      expect(new TextEncoder().encode(choice.detail).length).toBeLessThanOrEqual(300);
    }
    expect(listBattleChoices(field(["scout", "hearth", "beacon"], ["keeper"]), "one")).toHaveLength(5);
  });

  it("reports the same resolved team quantities for every role, roster size and opposing role", () => {
    for (const role of ROLE_ORDER) for (const otherRole of ROLE_ORDER) for (const size of [1, 2, 3]) {
      const state = field(Array<RoleId>(size).fill(role), [otherRole]);
      const comparison = compareBattleChoices(state, "one", "one:pulse", "one:signature")!;
      expect(comparison.cases.map((row) => row.opponentId)).toEqual(listBattleChoices(state, "two").map((choice) => choice.id));
      for (const row of comparison.cases) {
        expectReportedResult(state, "one", comparison.firstId, row.opponentId, row.first);
        expectReportedResult(state, "one", comparison.secondId, row.opponentId, row.second);
      }
    }
  });

  it("uses only public hypothetical alternatives and never asks the practice partner for its hidden choice", () => {
    const state = field(["beacon", "hearth", "scout"], ["beacon", "muse", "guardian"]);
    const policy = vi.spyOn(battleEngine, "choosePracticeCommand").mockImplementation(() => { throw new Error("Private policy consulted"); });
    const resolver = vi.spyOn(battleEngine, "resolveBattleRound");
    try {
      const comparison = compareBattleChoices(state, "one", "one:signature:one-member-1", "one:swap:one-member-2")!;
      expect(comparison.cases).toHaveLength(7);
      expect(resolver).toHaveBeenCalledTimes(14);
      expect(policy).not.toHaveBeenCalled();
      for (const call of resolver.mock.calls) {
        expect(call[0]).toBe(state);
        expect(call[1].baseRevision).toBe(battleEngine.battleRevision(state));
        expect(call[2].baseRevision).toBe(battleEngine.battleRevision(state));
      }
    } finally { resolver.mockRestore(); policy.mockRestore(); }
  });

  it("keeps hypothetical state, history, commands and all returned presentation data immutable", () => {
    const state = applyRound(field(["scout", "hearth"], ["guardian", "keeper"]), "pulse", "guard");
    const before = JSON.stringify(state);
    const teams = state.teams, history = state.history, event = state.history[0];
    const result = compareBattleChoices(state, "one", "one:pulse", "one:guard")!;
    expect(JSON.stringify(state)).toBe(before);
    expect(state.teams).toBe(teams);
    expect(state.history).toBe(history);
    expect(state.history[0]).toBe(event);
    expect(state.history).toHaveLength(1);
    expectFrozen(result);
    expect(Reflect.set(result.cases[0], "first", "changed")).toBe(false);
    expect(result.choices.every((choice) => !Object.hasOwn(choice, "command"))).toBe(true);
    expect(compareBattleChoices(state, "one", "one:pulse", "one:guard")).toEqual(result);
  });

  it("distinguishes incoming impact from shields, restoration and self-cost through actual outcomes", () => {
    const state = applyRound(field(["hearth"], ["muse"]), "pulse", "pulse");
    const comparison = compareBattleChoices(state, "one", "one:signature", "one:guard")!;
    const burst = comparison.cases.find((row) => row.opponentId === "two:signature")!;
    expect(burst.first).toContain("restored 4");
    expect(burst.first).toContain("self-cost 2");
    expect(burst.second).toContain("absorbed 7");
    expectReportedResult(state, "one", comparison.firstId, burst.opponentId, burst.first);
    expectReportedResult(state, "one", comparison.secondId, burst.opponentId, burst.second);
  });

  it("shows exposure clearing, marks, reserve entry timing, replacements and terminal outcomes", () => {
    const exposed = applyRound(field(["keeper"], ["scout"]), "guard", "signature");
    expect(exposed.teams[0].roster[0].exposed).toBe(true);
    const comparison = compareBattleChoices(exposed, "one", "one:signature", "one:pulse")!;
    const pulse = comparison.cases.find((row) => row.opponentId === "two:pulse")!;
    expect(pulse.first).toContain("clears own exposure");
    expectReportedResult(exposed, "one", comparison.firstId, pulse.opponentId, pulse.first);
    expectReportedResult(exposed, "one", comparison.secondId, pulse.opponentId, pulse.second);

    const beacon = field(["beacon", "hearth", "muse"], ["guardian"]);
    const crossing = compareBattleChoices(beacon, "one", "one:signature:one-member-1", "one:swap:one-member-1")!;
    for (const row of crossing.cases) {
      expect(row.first).toContain("reserve enters after impact");
      expect(row.second).toContain("reserve takes impact on entry");
      expectReportedResult(beacon, "one", crossing.firstId, row.opponentId, row.first);
      expectReportedResult(beacon, "one", crossing.secondId, row.opponentId, row.second);
    }

    let hurt = field(["scout", "hearth", "beacon"], ["guardian"]);
    hurt = applyRound(applyRound(hurt, "pulse", "signature"), "pulse", "signature");
    const replacement = compareBattleChoices(hurt, "one", "one:pulse", "one:guard")!;
    expect(replacement.cases.find((row) => row.opponentId === "two:pulse")!.first).toContain("settled active replaced");

    let close = field(["scout"], ["scout"]);
    for (let index = 0; index < 5; index++) close = applyRound(close, "pulse", "pulse");
    const finish = compareBattleChoices(close, "one", "one:pulse", "one:guard")!;
    const finishingPulse = finish.cases.find((row) => row.opponentId === "two:pulse")!;
    expect(finishingPulse.first).toContain("Encounter ends in a draw.");
    expectReportedResult(close, "one", finish.firstId, finishingPulse.opponentId, finishingPulse.first);
    expectReportedResult(close, "one", finish.secondId, finishingPulse.opponentId, finishingPulse.second);
  });

  it("rejects targets that became active or settled and signatures after shared Spark is spent", () => {
    let state = field(["scout", "hearth", "beacon"], ["guardian"]);
    const initial = listBattleChoices(state, "one");
    state = applyRound(state, "swap", "guard", "one-member-1");
    expect(initial.some((choice) => choice.id === "one:swap:one-member-1")).toBe(true);
    expect(compareBattleChoices(state, "one", "one:swap:one-member-1", "one:pulse")).toBeNull();
    expect(listBattleChoices(state, "one").find((choice) => choice.id === "one:pulse")!.command.baseRevision)
      .not.toBe(initial[0].command.baseRevision);

    state = field(["scout", "hearth", "beacon"], ["guardian"]);
    for (let index = 0; index < 3; index++) state = applyRound(state, "pulse", "signature");
    expect(state.teams[0].roster[0].integrity).toBe(0);
    expect(compareBattleChoices(state, "one", "one:swap:one-member-0", "one:pulse")).toBeNull();
    expect(state.teams[1].spark).toBe(0);
    expect(compareBattleChoices(state, "two", "two:signature", "two:pulse")).toBeNull();
    const remaining = compareBattleChoices(state, "one", "one:pulse", "one:guard")!;
    expect(remaining.cases.map((row) => row.opponentId)).toEqual(["two:pulse", "two:guard"]);
  });

  it("handles the second player's perspective, invalid choices and completion without resolving work", () => {
    const state = field(["muse"], ["guardian"]);
    const comparison = compareBattleChoices(state, "two", "two:signature", "two:guard")!;
    for (const row of comparison.cases) {
      expectReportedResult(state, "two", comparison.firstId, row.opponentId, row.first);
      expectReportedResult(state, "two", comparison.secondId, row.opponentId, row.second);
    }
    const complete = applyRound(state, "surrender", "guard");
    const resolver = vi.spyOn(battleEngine, "resolveBattleRound");
    try {
      for (const pair of [["one:pulse", "one:pulse"], ["unknown", "one:pulse"], ["two:pulse", "one:guard"],
        ["one:surrender", "one:pulse"], ["one:signature:missing", "one:pulse"]]) {
        expect(compareBattleChoices(state, "one", pair[0], pair[1])).toBeNull();
      }
      expect(listBattleChoices(complete, "one")).toEqual([]);
      expect(compareBattleChoices(complete, "one", "one:pulse", "one:guard")).toBeNull();
      expect(compareBattleChoices(state, "invalid" as BattleTeamId, "one:pulse", "one:guard")).toBeNull();
      expect(resolver).not.toHaveBeenCalled();
    } finally { resolver.mockRestore(); }
  });

  it("keeps native receipt sizes bounded even with multibyte formation names", () => {
    const labeled = (id: BattleTeamId): BattleTeamSetup => ({
      ...formation(id, ["beacon", "guardian", "scout"]), label: "🌱".repeat(14),
      roster: formation(id, ["beacon", "guardian", "scout"]).roster.map((card) => ({ ...card, name: "生".repeat(28) })),
    });
    const state = createBattle("unicode-comparison", labeled("one"), labeled("two"));
    const comparison = compareBattleChoices(state, "one", "one:signature:one-member-1", "one:swap:one-member-2")!;
    for (const choice of comparison.choices) {
      expect(new TextEncoder().encode(choice.label).length).toBeLessThanOrEqual(120);
      expect(new TextEncoder().encode(choice.detail).length).toBeLessThanOrEqual(300);
    }
    for (const row of comparison.cases) {
      expect(new TextEncoder().encode(row.opponentLabel).length).toBeLessThanOrEqual(120);
      expectReportedResult(state, "one", comparison.firstId, row.opponentId, row.first);
      expectReportedResult(state, "one", comparison.secondId, row.opponentId, row.second);
    }
  });
});
function round(state: BattleState, action: BattleAction, opponent: BattleAction | "partner"): BattleState {
  const result = resolveBattleRound(state, createBattleCommand(state, "one", action),
    opponent === "partner" ? choosePracticeCommand(state, "two") : createBattleCommand(state, "two", opponent));
  if (!result.accepted) throw new Error(result.reason);
  return result.state;
}
function expectTerminalHelp(state: BattleState) {
  expect(state.status).toBe("complete");
  expect(displayedBattleRound(state)).toBe(state.history.length);
  expect(displayedBattleRound(state)).toBe(state.round - 1);
  const before = JSON.stringify(state);
  for (const id of ["one", "two"] as const) for (const action of BATTLE_ACTIONS) {
    expect(() => describeBattleAction(state, id, action)).not.toThrow();
    expect(describeBattleAction(state, id, action)).toMatch(/^Practice complete/);
  }
  expect(JSON.stringify(state)).toBe(before);
}

describe("Arena command presentation through terminal redraws", () => {
  it("redraws a practice loss with no living player actor instead of constructing a command", () => {
    let state = createBattle("terminal-loss", setup("one"), setup("two", "guardian"));
    const moves: BattleAction[] = ["guard", "signature", "signature", "signature", "pulse", "pulse", "pulse", "pulse"];
    let index = 0;
    while (state.status === "active") {
      expect(describeBattleAction(state, "one", moves[index] ?? "pulse")).toContain("potential impact");
      state = round(state, moves[index++] ?? "pulse", "partner");
    }
    expect(state.winner).toBe("two");
    expect(state.teams[0].activeQiMonId).toBeNull();
    expect(() => createBattleCommand(state, "one", "pulse")).toThrow(/no active/);
    expectTerminalHelp(state);
  });
  it("redraws a win with a settled opposing formation", () => {
    let state = createBattle("terminal-win", setup("one", "muse"), setup("two"));
    while (state.status === "active") state = round(state, state.teams[0].spark ? "signature" : "pulse", "pulse");
    expect(state.winner).toBe("one");
    expect(state.teams[1].activeQiMonId).toBeNull();
    expectTerminalHelp(state);
  });
  it("redraws a draw when both actors have settled", () => {
    let state = createBattle("terminal-draw", setup("one"), setup("two"));
    while (state.status === "active") state = round(state, "pulse", "pulse");
    expect(state.winner).toBe("draw");
    expect(state.teams.map((team) => team.activeQiMonId)).toEqual([null, null]);
    expectTerminalHelp(state);
  });
  it("handles entry, surrender and unavailable moves without manufacturing another action", () => {
    expect(displayedBattleRound(null)).toBe(0);
    expect(describeBattleAction(null, "one", "pulse")).toMatch(/^Choose a formation/);
    const initial = createBattle("terminal-surrender", setup("one"), setup("two"));
    expect(displayedBattleRound(initial)).toBe(1);
    expect(describeBattleAction(initial, "one", "swap", "missing")).toContain("unavailable");
    expectTerminalHelp(round(initial, "surrender", "pulse"));
  });
});
