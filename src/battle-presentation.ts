import { BATTLE_LIMITS, createBattleCommand, previewBattleCommand, resolveBattleRound, teamIntegrity,
  type BattleAction, type BattleCommand, type BattleOutcome, type BattleState, type BattleTeamId,
  type BattleTeamState } from "./battle-engine";
import type { RoleId } from "./model";

/** The reducer's next-round cursor advances after completion; show accepted rounds then. */
export function displayedBattleRound(state: BattleState | null): number {
  if (!state) return 0;
  return state.status === "complete" ? state.history.length : Math.min(state.round, BATTLE_LIMITS.maximumRounds);
}

/** Shared by the current command help and native move details, including terminal redraws. */
export function describeBattleAction(state: BattleState | null, teamId: BattleTeamId, action: BattleAction, target?: string): string {
  if (!state) return "Choose a formation to see what each move does.";
  // A settled formation has no actor. Presentation must never construct another command for it.
  if (state.status === "complete") return "Practice complete. Review the round history, then keep the result or choose another formation.";
  const team = state.teams[teamId === "one" ? 0 : 1];
  if (!team.activeQiMonId) return "This formation has no active QiMon.";
  const command = createBattleCommand(state, teamId, action, target);
  const effect = previewBattleCommand(state, command);
  if (!effect) return "This move is unavailable in the current round.";
  if (action === "surrender") return "End this encounter. An early ending cannot become a kept practice.";
  if (action === "swap") return "Swap uses this turn. The incoming reserve takes this round's impact.";
  const parts = [`${effect.damage} potential impact`, `${effect.shield} shield`, `${effect.sparkSpent} Spark cost`];
  if (effect.heal) parts.push(`up to ${effect.heal} restoration`);
  if (effect.selfDamage) parts.push(`${effect.selfDamage} self-cost`);
  if (effect.applyExposed) parts.push("marks the opponent: +3 to the next damaging impact");
  if (effect.clearExposed) parts.push("clears your exposure before impact");
  if (effect.passageTargetId) parts.push("reserve enters after impact");
  parts.push(`includes +${team.concentration} concentration and +${effect.alignmentBonus} alignment`);
  return parts.join(" · ") + ". Opposing shields can reduce impact.";
}

export interface BattleChoice {
  readonly id: string;
  readonly label: string;
  readonly detail: string;
  readonly command: BattleCommand;
}

export interface BattleChoiceComparison {
  readonly choices: readonly Readonly<Pick<BattleChoice, "id" | "label" | "detail">>[];
  readonly firstId: string;
  readonly secondId: string;
  readonly cases: readonly Readonly<{
    opponentId: string;
    opponentLabel: string;
    first: string;
    second: string;
  }>[];
}

const SIGNATURE_LABELS: Readonly<Record<RoleId, string>> = Object.freeze({
  hearth: "Mend", muse: "Burst", scout: "Mark", beacon: "Passage", keeper: "Clear", guardian: "Hold",
});
// Three-member Beacon formation: Pulse, Guard, three Passage choices and two swaps.
// Fail closed if later rules introduce more branches until the UI budget is reviewed.
const MAXIMUM_COMPARISON_CHOICES = 7;

/** Current public, legal choices only. No sealed command or partner policy is an input. */
export function listBattleChoices(state: BattleState, teamId: BattleTeamId): readonly BattleChoice[] {
  const team = state.teams.find((candidate) => candidate.id === teamId);
  const active = team?.roster.find((card) => card.id === team.activeQiMonId && card.integrity > 0);
  if (state.status !== "active" || !team || !active) return Object.freeze([]);
  const choices: BattleChoice[] = [];
  const add = (action: BattleAction, label: string, target?: string): void => {
    const command = createBattleCommand(state, teamId, action, target);
    if (!previewBattleCommand(state, command)) return;
    choices.push(Object.freeze({ id: `${teamId}:${action}${target ? `:${target}` : ""}`, label,
      detail: describeBattleAction(state, teamId, action, target), command }));
  };
  add("pulse", "Pulse");
  add("guard", "Guard");
  add("signature", SIGNATURE_LABELS[active.role]);
  const reserves = team.roster.filter((card) => card.id !== active.id && card.integrity > 0);
  const reserveName = (value: string): string => Array.from(value).slice(0, 24).join("");
  if (active.role === "beacon") {
    for (const reserve of reserves) add("signature", `Passage to ${reserveName(reserve.name)}`, reserve.id);
  }
  for (const reserve of reserves) add("swap", `Swap to ${reserveName(reserve.name)}`, reserve.id);
  return Object.freeze(choices.length <= MAXIMUM_COMPARISON_CHOICES ? choices : []);
}

function outcomeDescription(before: BattleTeamState, after: BattleTeamState, outcome: BattleOutcome,
  playerId: BattleTeamId): string {
  const parts = [
    `${after.id === playerId ? "Your side" : "Other side"}: team integrity ${teamIntegrity(after)}/${after.roster.reduce((sum, card) => sum + card.maximumIntegrity, 0)}`,
    `Spark ${after.spark}`,
    `impact taken ${outcome.damageTaken}, absorbed ${outcome.damageAbsorbed}`,
  ];
  // The engine's damageDealt is before the opponent's shield; do not label it as HP removed.
  if (outcome.damageDealt) parts.push(`impact sent ${outcome.damageDealt} before shields`);
  if (outcome.integrityRestored) parts.push(`restored ${outcome.integrityRestored}`);
  if (outcome.selfDamage) parts.push(`self-cost ${outcome.selfDamage}`);
  if (outcome.sparkSpent) parts.push(`spent ${outcome.sparkSpent} Spark`);
  if (outcome.exposedApplied) parts.push("marks opponent exposed");
  if (outcome.exposedCleared) parts.push("clears own exposure");
  if (!outcome.exposedCleared && before.roster.some((card) => card.id === outcome.damageRecipientQiMonId && card.exposed) &&
    after.roster.some((card) => card.id === outcome.damageRecipientQiMonId && !card.exposed)) parts.push("exposure ended");
  const exposed = after.roster.filter((card) => card.integrity > 0 && card.exposed).length;
  if (exposed) parts.push(`${exposed} exposed`);
  if (outcome.action === "swap") parts.push("reserve takes impact on entry");
  if (outcome.action === "signature" && outcome.targetQiMonId && after.activeQiMonId === outcome.targetQiMonId) {
    parts.push("reserve enters after impact");
  }
  if (outcome.replacementQiMonId) parts.push("settled active replaced");
  const settled = after.roster.filter((card) => card.integrity <= 0 &&
    (before.roster.find((prior) => prior.id === card.id)?.integrity ?? 0) > 0);
  if (settled.length) parts.push(`${settled.length} settled`);
  return parts.join("; ") + ".";
}

function describeComparisonResult(state: BattleState, first: BattleCommand, second: BattleCommand,
  playerId: BattleTeamId): string | null {
  const result = resolveBattleRound(state, first, second);
  if (!result.accepted) return null;
  const parts = result.state.teams.map((team, index) =>
    outcomeDescription(state.teams[index], team, result.event.outcomes[index], playerId));
  if (result.state.winner) parts.push(result.state.winner === "draw" ? "Encounter ends in a draw." :
    `${result.state.winner === playerId ? "Your side" : "Other side"} wins the encounter.`);
  return parts.join(" ");
}

/**
 * Disposable one-round rehearsals through the sole battle resolver, at most 14 calls.
 * IDs are current action/target labels, not authorization: callers must separately bind
 * a UI request to its battle session/revision before presenting or accepting it.
 */
export function compareBattleChoices(state: BattleState, teamId: BattleTeamId,
  firstId: string, secondId: string): BattleChoiceComparison | null {
  if (firstId === secondId) return null;
  const choices = listBattleChoices(state, teamId);
  const first = choices.find((choice) => choice.id === firstId);
  const second = choices.find((choice) => choice.id === secondId);
  if (!first || !second) return null;
  const opposing = listBattleChoices(state, teamId === "one" ? "two" : "one");
  if (!opposing.length) return null;
  const cases: BattleChoiceComparison["cases"][number][] = [];
  for (const opponent of opposing) {
    const describe = (choice: BattleChoice): string | null => teamId === "one"
      ? describeComparisonResult(state, choice.command, opponent.command, teamId)
      : describeComparisonResult(state, opponent.command, choice.command, teamId);
    const firstDescription = describe(first);
    const secondDescription = describe(second);
    if (firstDescription === null || secondDescription === null) return null;
    cases.push(Object.freeze({ opponentId: opponent.id, opponentLabel: opponent.label,
      first: firstDescription, second: secondDescription }));
  }
  return Object.freeze({ choices: Object.freeze(choices.map(({ id, label, detail }) => Object.freeze({ id, label, detail }))),
    firstId, secondId, cases: Object.freeze(cases) });
}
