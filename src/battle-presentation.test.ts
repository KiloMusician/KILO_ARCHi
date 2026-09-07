import { describe, expect, it } from "vitest";
import { BATTLE_ACTIONS, choosePracticeCommand, createBattle, createBattleCommand, resolveBattleRound,
  type BattleAction, type BattleState, type BattleTeamId, type BattleTeamSetup } from "./battle-engine";
import { describeBattleAction, displayedBattleRound } from "./battle-presentation";

const setup = (id: BattleTeamId, role: "scout" | "muse" | "guardian" = "scout"): BattleTeamSetup => ({
  id, label: id, bondRole: role, roster: [{ id: `${id}-qimon`, name: role, role }],
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
