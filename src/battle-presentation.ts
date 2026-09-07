import { BATTLE_LIMITS, createBattleCommand, previewBattleCommand, type BattleAction, type BattleState, type BattleTeamId } from "./battle-engine";

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
