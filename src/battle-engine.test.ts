import { describe, expect, it } from "vitest";
import {
  BATTLE_LIMITS,
  battleRevision,
  choosePracticeCommand,
  createBattle,
  createBattleCommand,
  resolveBattleRound,
  previewBattleCommand,
  teamIntegrity,
  type BattleState,
  type BattleTeamId,
  type BattleTeamSetup,
} from "./battle-engine";
import { ROLE_ORDER, type RoleId } from "./model";

function setup(id: BattleTeamId, roles: readonly RoleId[], bondRole: RoleId = roles[0] ?? "hearth"): BattleTeamSetup {
  return {
    id,
    label: id === "one" ? "Player One" : "Player Two",
    bondRole,
    roster: roles.map((role, index) => ({ id: `${id}-qimon-${index + 1}`, name: `${role}-${index + 1}`, role })),
  };
}

function battle(
  one: readonly RoleId[] = ["scout"],
  two: readonly RoleId[] = ["guardian"],
  oneBond: RoleId = one[0],
  twoBond: RoleId = two[0],
): BattleState {
  return createBattle("practice-battle", setup("one", one, oneBond), setup("two", two, twoBond));
}

function resolve(
  state: BattleState,
  oneAction: Parameters<typeof createBattleCommand>[2],
  twoAction: Parameters<typeof createBattleCommand>[2],
  oneTarget?: string,
  twoTarget?: string,
): BattleState {
  const result = resolveBattleRound(
    state,
    createBattleCommand(state, "one", oneAction, oneTarget),
    createBattleCommand(state, "two", twoAction, twoTarget),
  );
  expect(result.accepted).toBe(true);
  if (!result.accepted) throw new Error(result.reason);
  return result.state;
}

describe("QiMon Battle v1", () => {
  it("previews each role using the same own effects as resolution without altering the state", () => {
    for (const role of ROLE_ORDER) {
      for (const count of [1, 2, 3]) {
        const state = battle(Array(count).fill(role), ["guardian"]);
        const before = JSON.stringify(state);
        for (const action of ["pulse", "guard", "signature"] as const) {
          const command = createBattleCommand(state, "one", action);
          const preview = previewBattleCommand(state, command)!;
          expect(Object.isFrozen(preview)).toBe(true);
          const result = resolveBattleRound(state, command, createBattleCommand(state, "two", "guard"));
          expect(result.accepted).toBe(true);
          if (!result.accepted) throw new Error(result.reason);
          const own = result.event.outcomes[0];
          expect({ damage: own.damageDealt, shield: own.shieldRaised, selfDamage: own.selfDamage,
            sparkSpent: own.sparkSpent, alignmentBonus: own.alignmentBonus }).toEqual({
            damage: preview.damage, shield: preview.shield, selfDamage: preview.selfDamage,
            sparkSpent: preview.sparkSpent, alignmentBonus: preview.alignmentBonus });
          expect(own.integrityRestored).toBeLessThanOrEqual(preview.heal);
          expect(result.event.outcomes[1].damageTaken).toBeLessThanOrEqual(preview.damage);
        }
        expect(JSON.stringify(state)).toBe(before);
      }
    }
  });

  it("keeps tactical previews legal across stale commands, Spark exhaustion, swaps and completion", () => {
    const initial = battle(["guardian", "beacon"], ["guardian"]);
    const swap = createBattleCommand(initial, "one", "swap", "one-qimon-2");
    expect(previewBattleCommand(initial, swap)).toMatchObject({ damage: 0, heal: 0, shield: 0, sparkSpent: 0 });
    expect(previewBattleCommand(initial, createBattleCommand(initial, "one", "swap", "missing"))).toBeNull();
    const stale = createBattleCommand(initial, "one", "pulse");
    let state = initial;
    for (let round = 0; round < 3; round += 1) state = resolve(state, "signature", "guard");
    expect(state.teams[0].spark).toBe(0);
    expect(previewBattleCommand(state, createBattleCommand(state, "one", "signature"))).toBeNull();
    expect(previewBattleCommand(state, stale)).toBeNull();
    expect(previewBattleCommand(state, createBattleCommand(state, "one", "pulse"))).not.toBeNull();
    const complete = resolve(state, "surrender", "guard");
    expect(previewBattleCommand(complete, createBattleCommand(complete, "one", "pulse"))).toBeNull();
  });

  it("separates own move strength from public exposure and the opposing shield outcome", () => {
    const exposed = resolve(battle(["scout"], ["guardian"]), "signature", "guard");
    const command = createBattleCommand(exposed, "one", "pulse");
    const preview = previewBattleCommand(exposed, command)!;
    const guard = resolve(exposed, "pulse", "guard");
    const pulse = resolve(exposed, "pulse", "pulse");
    expect(guard.history.at(-1)!.outcomes[0].damageDealt).toBe(preview.damage + 3);
    expect(pulse.history.at(-1)!.outcomes[0].damageDealt).toBe(preview.damage + 3);
    expect(guard.history.at(-1)!.outcomes[1].damageTaken).toBeLessThan(pulse.history.at(-1)!.outcomes[1].damageTaken);
    expect(previewBattleCommand(exposed, command)).toEqual(preview);
  });

  it("creates a deeply frozen, deterministic, in-memory battle state", () => {
    const state = battle();
    expect(state).toMatchObject({ schema: 1, battleId: "practice-battle", round: 1, status: "active", winner: null });
    expect(Object.isFrozen(state)).toBe(true);
    expect(Object.isFrozen(state.teams)).toBe(true);
    expect(Object.isFrozen(state.teams[0].roster[0])).toBe(true);
    expect(battleRevision(state)).toBe(battleRevision(battle()));
    expect(Object.keys(state).sort()).toEqual(["battleId", "history", "round", "schema", "status", "teams", "winner"]);
  });

  it("keeps total Integrity, Resonance, Spark, and command count independent of roster size", () => {
    const state = battle(["hearth"], ["muse", "scout", "beacon"]);
    expect(teamIntegrity(state.teams[0])).toBe(BATTLE_LIMITS.teamIntegrity);
    expect(teamIntegrity(state.teams[1])).toBe(BATTLE_LIMITS.teamIntegrity);
    expect(state.teams[0].roster.map((card) => [card.maximumIntegrity, card.resonance])).toEqual([[36, 12]]);
    expect(state.teams[1].roster.map((card) => [card.maximumIntegrity, card.resonance])).toEqual([
      [12, 4],
      [12, 4],
      [12, 4],
    ]);
    expect(state.teams.map((team) => [team.concentration, team.spark])).toEqual([
      [2, 3],
      [0, 3],
    ]);
  });

  it("rejects empty, oversized, duplicated, and cross-team QiMon cards", () => {
    expect(() => createBattle("bad-empty", setup("one", []), setup("two", ["hearth"]))).toThrow("1–3");
    expect(() => createBattle("bad-four", setup("one", ["hearth", "muse", "scout", "beacon"]), setup("two", ["keeper"]))).toThrow(
      "1–3",
    );
    const duplicated = setup("one", ["hearth", "muse"]);
    const duplicateRoster = { ...duplicated, roster: [duplicated.roster[0], duplicated.roster[0]] };
    expect(() => createBattle("bad-local", duplicateRoster, setup("two", ["keeper"]))).toThrow("more than once");
    const one = setup("one", ["hearth"]);
    const two = { ...setup("two", ["keeper"]), roster: [{ ...setup("two", ["keeper"]).roster[0], id: one.roster[0].id }] };
    expect(() => createBattle("bad-cross", one, two)).toThrow("cannot appear on both teams");
  });

  it("resolves simultaneous aligned Pulse commands without first-player advantage", () => {
    const state = battle();
    const next = resolve(state, "pulse", "pulse");
    expect(next.teams[0].roster[0].integrity).toBe(29);
    expect(next.teams[1].roster[0].integrity).toBe(29);
    expect(next.history[0].outcomes.map((outcome) => [outcome.damageDealt, outcome.alignmentBonus])).toEqual([
      [7, 1],
      [7, 1],
    ]);
  });

  it("makes the explicit player Bond role worth one bounded alignment point", () => {
    const state = battle(["scout"], ["guardian"], "hearth", "guardian");
    const next = resolve(state, "pulse", "pulse");
    expect(next.history[0].outcomes[0].alignmentBonus).toBe(0);
    expect(next.history[0].outcomes[1].alignmentBonus).toBe(1);
    expect(next.teams[1].roster[0].integrity).toBe(30);
    expect(next.teams[0].roster[0].integrity).toBe(29);
  });

  it("lets Guard absorb only the simultaneous round and never creates persistent extra Integrity", () => {
    const state = battle();
    const guarded = resolve(state, "guard", "pulse");
    expect(guarded.teams[0].roster[0].integrity).toBe(36);
    expect(guarded.history[0].outcomes[0]).toMatchObject({ shieldRaised: 7, damageAbsorbed: 7, damageTaken: 0 });
    const next = resolve(guarded, "pulse", "pulse");
    expect(next.teams[0].roster[0].integrity).toBe(29);
  });

  it("resolves Hearth repair in the same net calculation as lethal incoming damage", () => {
    let state = battle(["hearth"], ["muse"]);
    state = resolve(state, "pulse", "signature");
    state = resolve(state, "pulse", "signature");
    state = resolve(state, "pulse", "signature");
    expect(state.teams[0].roster[0].integrity).toBe(3);
    expect(state.teams[1].roster[0].integrity).toBe(9);
    const complete = resolve(state, "signature", "pulse");
    expect(complete.teams[0].roster[0].integrity).toBe(0);
    expect(complete.history.at(-1)?.outcomes[0]).toMatchObject({ integrityRestored: 0, damageTaken: 7 });
    expect(complete).toMatchObject({ status: "complete", winner: "two" });
  });

  it("applies Scout Mark to the next damaging technique and then clears it", () => {
    let state = battle(["scout"], ["guardian"]);
    state = resolve(state, "signature", "guard");
    expect(state.teams[1].roster[0].exposed).toBe(true);
    expect(state.teams[0].spark).toBe(2);
    state = resolve(state, "pulse", "guard");
    expect(state.history[1].outcomes[0].damageDealt).toBe(10);
    expect(state.teams[1].roster[0].exposed).toBe(false);
  });

  it("lets Keeper Clear remove an existing Mark before simultaneous damage", () => {
    let state = battle(["keeper"], ["scout"]);
    state = resolve(state, "pulse", "signature");
    expect(state.teams[0].roster[0].exposed).toBe(true);
    state = resolve(state, "signature", "pulse");
    expect(state.history[1].outcomes[0].exposedCleared).toBe(true);
    expect(state.history[1].outcomes[0].damageTaken).toBe(7);
    expect(state.teams[0].roster[0].exposed).toBe(false);
  });

  it("makes a normal Swap consume the command and sends incoming damage to the reserve", () => {
    const state = battle(["hearth", "guardian"], ["muse"]);
    const reserve = state.teams[0].roster[1];
    const next = resolve(state, "swap", "pulse", reserve.id);
    expect(next.teams[0].activeQiMonId).toBe(reserve.id);
    expect(next.teams[0].roster[0].integrity).toBe(18);
    expect(next.teams[0].roster[1].integrity).toBe(11);
    expect(next.history[0].outcomes[0]).toMatchObject({
      actorQiMonId: state.teams[0].roster[0].id,
      damageRecipientQiMonId: reserve.id,
      damageDealt: 0,
      damageTaken: 7,
    });
  });

  it("uses shared Spark and rejects a fourth signature without changing state", () => {
    let state = battle(["hearth"], ["guardian"]);
    for (let index = 0; index < 3; index += 1) state = resolve(state, "signature", "guard");
    expect(state.teams[0].spark).toBe(0);
    const command = createBattleCommand(state, "one", "signature");
    const result = resolveBattleRound(state, command, createBattleCommand(state, "two", "guard"));
    expect(result).toMatchObject({ accepted: false, state, reason: "No shared Spark remains for a signature." });
    expect(result.state).toBe(state);
  });

  it("rejects stale commands and preserves the exact current state", () => {
    const state = battle();
    const oldOne = createBattleCommand(state, "one", "pulse");
    const oldTwo = createBattleCommand(state, "two", "pulse");
    const next = resolve(state, "pulse", "pulse");
    const result = resolveBattleRound(next, oldOne, oldTwo);
    expect(result.accepted).toBe(false);
    expect(result.state).toBe(next);
    expect(battleRevision(result.state)).toBe(battleRevision(next));
  });

  it("preserves prior states and produces byte-identical replay for identical commands", () => {
    const first = battle(["beacon", "muse"], ["keeper", "guardian"]);
    const before = JSON.stringify(first);
    const firstResult = resolve(
      first,
      "signature",
      "pulse",
      first.teams[0].roster[1].id,
    );
    const second = battle(["beacon", "muse"], ["keeper", "guardian"]);
    const secondResult = resolve(
      second,
      "signature",
      "pulse",
      second.teams[0].roster[1].id,
    );
    expect(JSON.stringify(first)).toBe(before);
    expect(JSON.stringify(firstResult)).toBe(JSON.stringify(secondResult));
    expect(battleRevision(firstResult)).toBe(battleRevision(secondResult));
  });

  it("replays sealed round commands into the byte-identical state and rejects an altered actor", () => {
    const initial = battle(["beacon", "muse"], ["guardian", "keeper"]);
    let completed = resolve(initial, "signature", "pulse", initial.teams[0].roster[1].id);
    completed = resolve(completed, "pulse", "signature");

    let replayed = battle(["beacon", "muse"], ["guardian", "keeper"]);
    for (const event of completed.history) {
      expect(Object.isFrozen(event.commands[0])).toBe(true);
      const result = resolveBattleRound(replayed, event.commands[0], event.commands[1]);
      expect(result.accepted).toBe(true);
      if (!result.accepted) throw new Error(result.reason);
      replayed = result.state;
    }
    expect(JSON.stringify(replayed)).toBe(JSON.stringify(completed));
    expect(battleRevision(replayed)).toBe(battleRevision(completed));

    const altered = { ...createBattleCommand(initial, "one", "pulse"), activeQiMonId: "one-qimon-99" };
    const rejected = resolveBattleRound(initial, altered, createBattleCommand(initial, "two", "guard"));
    expect(rejected).toMatchObject({ accepted: false, state: initial, reason: "Only the current active QiMon may act." });
    expect(rejected.state).toBe(initial);
  });

  it("keeps every role, signature, and 1–3 formation mirrored across player slots", () => {
    const outcomeMath = (outcome: BattleState["history"][number]["outcomes"][number]) => ({
      damageDealt: outcome.damageDealt,
      damageTaken: outcome.damageTaken,
      damageAbsorbed: outcome.damageAbsorbed,
      integrityRestored: outcome.integrityRestored,
      selfDamage: outcome.selfDamage,
      shieldRaised: outcome.shieldRaised,
      sparkSpent: outcome.sparkSpent,
      exposedApplied: outcome.exposedApplied,
      exposedCleared: outcome.exposedCleared,
      alignmentBonus: outcome.alignmentBonus,
    });
    for (const oneRole of ROLE_ORDER) {
      for (const twoRole of ROLE_ORDER) {
        for (let oneSize = 1; oneSize <= 3; oneSize += 1) {
          for (let twoSize = 1; twoSize <= 3; twoSize += 1) {
            const forward = resolve(
              battle(Array(oneSize).fill(oneRole), Array(twoSize).fill(twoRole)),
              "signature",
              "signature",
            );
            const mirrored = resolve(
              battle(Array(twoSize).fill(twoRole), Array(oneSize).fill(oneRole)),
              "signature",
              "signature",
            );
            expect(teamIntegrity(forward.teams[0])).toBe(teamIntegrity(mirrored.teams[1]));
            expect(teamIntegrity(forward.teams[1])).toBe(teamIntegrity(mirrored.teams[0]));
            expect(outcomeMath(forward.history[0].outcomes[0])).toEqual(outcomeMath(mirrored.history[0].outcomes[1]));
            expect(outcomeMath(forward.history[0].outcomes[1])).toEqual(outcomeMath(mirrored.history[0].outcomes[0]));
          }
        }
      }
    }
  });

  it("ends surrender immediately and locks all later commands", () => {
    const state = battle();
    const complete = resolve(state, "surrender", "guard");
    expect(complete).toMatchObject({ status: "complete", winner: "two" });
    const result = resolveBattleRound(
      complete,
      createBattleCommand(complete, "one", "pulse"),
      createBattleCommand(complete, "two", "pulse"),
    );
    expect(result).toMatchObject({ accepted: false, reason: "The battle is already complete." });
  });

  it("resolves surrender before an opponent swap can alter the terminal formation", () => {
    const state = battle(["scout"], ["guardian", "keeper"]);
    const originalActive = state.teams[1].activeQiMonId;
    const reserve = state.teams[1].roster[1].id;
    const complete = resolve(state, "surrender", "swap", undefined, reserve);
    expect(complete).toMatchObject({ status: "complete", winner: "two" });
    expect(complete.teams[1].activeQiMonId).toBe(originalActive);
    expect(complete.history[0].outcomes[1]).toMatchObject({ action: "swap", replacementQiMonId: null });
  });

  it("declares a deterministic draw after twenty damage-free rounds", () => {
    let state = battle();
    for (let round = 1; round <= BATTLE_LIMITS.maximumRounds; round += 1) state = resolve(state, "guard", "guard");
    expect(state).toMatchObject({ round: 21, status: "complete", winner: "draw" });
    expect(state.history).toHaveLength(20);
  });
});

describe("local practice partner", () => {
  it("returns one frozen current command without changing public state or accepting a sealed command", () => {
    const state = battle(["muse", "hearth"], ["keeper", "beacon"]);
    const before = JSON.stringify(state);
    const publicState = Object.defineProperty({ ...state }, "sealedCommands", {
      get() { throw new Error("A practice partner must not inspect sealed input."); },
    });
    const chosen = choosePracticeCommand(publicState, "one");
    expect(chosen).toEqual(choosePracticeCommand(state, "one"));
    expect(chosen).toMatchObject({ battleId: state.battleId, round: 1, baseRevision: battleRevision(state), teamId: "one" });
    expect(Object.isFrozen(chosen)).toBe(true);
    for (const opposingAction of ["pulse", "guard", "signature"] as const) {
      const result = resolveBattleRound(state, chosen, createBattleCommand(state, "two", opposingAction));
      expect(result.accepted).toBe(true);
      expect(choosePracticeCommand(state, "one")).toEqual(chosen);
    }
    expect(JSON.stringify(state)).toBe(before);
  });

  it("repairs a hurt Hearth using the existing Signature outcome", () => {
    let state = battle(["hearth"], ["scout"]);
    for (let round = 0; round < 3; round += 1) state = resolve(state, "pulse", "pulse");
    const chosen = choosePracticeCommand(state, "one");
    expect(chosen.action).toBe("signature");
    const next = resolveBattleRound(state, chosen, createBattleCommand(state, "two", "guard"));
    expect(next.accepted).toBe(true);
    if (!next.accepted) throw new Error(next.reason);
    expect(next.event.outcomes[0]).toMatchObject({ integrityRestored: 4, sparkSpent: 1 });
    expect(next.state.teams[0].roster[0].integrity).toBe(state.teams[0].roster[0].integrity + 4);
  });

  it("clears an exposed Keeper and does not waste another Scout mark on an exposed opponent", () => {
    const keeper = resolve(battle(["keeper"], ["scout"]), "guard", "signature");
    expect(choosePracticeCommand(keeper, "one").action).toBe("signature");
    const cleared = resolveBattleRound(keeper, choosePracticeCommand(keeper, "one"), createBattleCommand(keeper, "two", "pulse"));
    expect(cleared.accepted).toBe(true);
    if (!cleared.accepted) throw new Error(cleared.reason);
    expect(cleared.event.outcomes[0].exposedCleared).toBe(true);

    let scout = resolve(battle(["scout"], ["guardian"]), "signature", "guard");
    scout = resolve(scout, "guard", "guard");
    scout = resolve(scout, "guard", "guard");
    expect(scout.round).toBe(4);
    expect(scout.teams[1].roster[0].exposed).toBe(true);
    expect(choosePracticeCommand(scout, "one").action).toBe("pulse");
  });

  it("uses Beacon Passage for a healthier reserve and an ordinary Swap when Spark is exhausted", () => {
    let passage = battle(["beacon", "hearth"], ["muse"]);
    passage = resolve(passage, "pulse", "pulse");
    passage = resolve(passage, "pulse", "pulse");
    const reserve = passage.teams[0].roster[1].id;
    const command = choosePracticeCommand(passage, "one");
    expect(command).toMatchObject({ action: "signature", targetQiMonId: reserve });
    const next = resolveBattleRound(passage, command, createBattleCommand(passage, "two", "guard"));
    expect(next.accepted).toBe(true);
    if (!next.accepted) throw new Error(next.reason);
    expect(next.state.teams[0].activeQiMonId).toBe(reserve);
    expect(next.event.outcomes[0].sparkSpent).toBe(1);

    let depleted = battle(["beacon", "hearth"], ["muse"]);
    for (let round = 0; round < 3; round += 1) depleted = resolve(depleted, "signature", "guard");
    depleted = resolve(depleted, "guard", "signature");
    depleted = resolve(depleted, "guard", "signature");
    expect(depleted.teams[0].spark).toBe(0);
    expect(choosePracticeCommand(depleted, "one")).toMatchObject({ action: "swap", targetQiMonId: reserve });
  });

  it("swaps an endangered member without selecting an exhausted reserve", () => {
    let state = battle(["scout", "keeper", "hearth"], ["muse"]);
    state = resolve(state, "pulse", "signature");
    const initialSwap = choosePracticeCommand(state, "one");
    expect(initialSwap).toMatchObject({ action: "swap", targetQiMonId: state.teams[0].roster[1].id });
    state = resolve(state, "pulse", "signature");
    state = resolve(state, "pulse", "signature");
    expect(state.teams[0].roster[0].integrity).toBe(0);
    const chosen = choosePracticeCommand(state, "one");
    expect(chosen).toMatchObject({ action: "swap", targetQiMonId: state.teams[0].roster[2].id });
    expect(resolveBattleRound(state, chosen, createBattleCommand(state, "two", "pulse")).accepted).toBe(true);
  });

  it("conserves Spark for a Pulse finish and never selects a signature after depletion", () => {
    let finish = battle(["keeper"], ["guardian"]);
    for (let round = 0; round < 5; round += 1) finish = resolve(finish, "pulse", "guard");
    // Guard absorbed those attacks; produce a low target through actual damage.
    for (let round = 0; round < 5; round += 1) finish = resolve(finish, "pulse", "pulse");
    expect(finish.teams[1].roster[0].integrity).toBe(1);
    expect(choosePracticeCommand(finish, "one").action).toBe("pulse");

    let depleted = battle(["guardian"], ["hearth"]);
    for (let round = 0; round < 3; round += 1) depleted = resolve(depleted, "signature", "guard");
    expect(depleted.teams[0].spark).toBe(0);
    const command = choosePracticeCommand(depleted, "one");
    expect(command.action).toBe("pulse");
    expect(resolveBattleRound(depleted, command, createBattleCommand(depleted, "two", "guard")).accepted).toBe(true);
  });

  it("takes a defensive beat under pressure and resumes attacking without inventing Spark recovery", () => {
    let state = battle(["scout"], ["guardian"]);
    state = resolve(state, "pulse", "pulse");
    state = resolve(state, "pulse", "pulse");
    expect(state.round).toBe(3);
    const command = choosePracticeCommand(state, "one");
    expect(command.action).toBe("guard");
    const next = resolveBattleRound(state, command, createBattleCommand(state, "two", "pulse"));
    expect(next.accepted).toBe(true);
    if (!next.accepted) throw new Error(next.reason);
    expect(next.state.teams[0].spark).toBe(state.teams[0].spark);
    expect(choosePracticeCommand(next.state, "one").action).toBe("signature");
  });

  it("does not choose a finishing Muse signature that would exhaust its own Integrity", () => {
    let state = battle(["muse"], ["scout"]);
    for (let round = 0; round < 3; round += 1) state = resolve(state, "pulse", "signature");
    state = resolve(state, "pulse", "pulse");
    expect(state.teams[0].roster[0].integrity).toBe(2);
    expect(state.teams[0].spark).toBe(3);
    expect(state.teams[1].roster[0].integrity).toBe(8);
    const command = choosePracticeCommand(state, "one");
    expect(command.action).toBe("pulse");
    const next = resolveBattleRound(state, command, createBattleCommand(state, "two", "guard"));
    expect(next.accepted).toBe(true);
    if (!next.accepted) throw new Error(next.reason);
    expect(next.state.teams[0].roster[0].integrity).toBe(2);
    expect(next.event.outcomes[0].selfDamage).toBe(0);
  });

  it("rejects completed battles, unknown teams and missing or exhausted active members", () => {
    const state = battle();
    expect(() => choosePracticeCommand(resolve(state, "surrender", "guard"), "two")).toThrow("already complete");
    expect(() => choosePracticeCommand(state, "three" as BattleTeamId)).toThrow("no living active");
    for (const invalidActive of [null, "missing-member"]) {
      const invalid: BattleState = { ...state, teams: [{ ...state.teams[0], activeQiMonId: invalidActive }, state.teams[1]] };
      expect(() => choosePracticeCommand(invalid, "one")).toThrow("no living active");
      expect(() => choosePracticeCommand(invalid, "two")).toThrow("opposing team");
    }
    const exhausted: BattleState = {
      ...state, teams: [{ ...state.teams[0], roster: [{ ...state.teams[0].roster[0], integrity: 0 }] }, state.teams[1]],
    };
    expect(() => choosePracticeCommand(exhausted, "one")).toThrow("no living active");
  });

  it("plays legal, deterministic mirrored matches across every role and 1–3 mixed formations", () => {
    const play = (initial: BattleState): BattleState => {
      let current = initial;
      for (let round = 0; current.status === "active" && round < BATTLE_LIMITS.maximumRounds; round += 1) {
        const before = JSON.stringify(current);
        const one = choosePracticeCommand(current, "one");
        const two = choosePracticeCommand(current, "two");
        expect(one.action).not.toBe("surrender");
        expect(two.action).not.toBe("surrender");
        const next = resolveBattleRound(current, one, two);
        expect(next.accepted).toBe(true);
        expect(JSON.stringify(current)).toBe(before);
        if (!next.accepted) throw new Error(next.reason);
        expect(next.state.teams.every((team) => team.spark >= 0)).toBe(true);
        current = next.state;
      }
      expect(current.status).toBe("complete");
      return current;
    };
    for (let role = 0; role < ROLE_ORDER.length; role += 1) {
      for (let oneSize = 1; oneSize <= 3; oneSize += 1) {
        for (let twoSize = 1; twoSize <= 3; twoSize += 1) {
          const one = Array.from({ length: oneSize }, (_, index) => ROLE_ORDER[(role + index) % ROLE_ORDER.length]);
          const two = Array.from({ length: twoSize }, (_, index) => ROLE_ORDER[(role + index + 3) % ROLE_ORDER.length]);
          const initial = battle(one, two);
          const final = play(initial);
          expect(JSON.stringify(play(initial))).toBe(JSON.stringify(final));
          const mirrored = play(battle(two, one));
          expect(final.teams.map(teamIntegrity)).toEqual(mirrored.teams.map(teamIntegrity).reverse());
          expect(final.teams.map((team) => team.spark)).toEqual(mirrored.teams.map((team) => team.spark).reverse());
          expect(final.history.length).toBe(mirrored.history.length);
        }
      }
    }
  });
});
