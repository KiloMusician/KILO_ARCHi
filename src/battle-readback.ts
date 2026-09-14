import { BATTLE_LIMITS, type BattleOutcome, type BattleRoundEvent, type BattleState } from "./battle-engine";
import type { DesktopArenaReadback, DesktopArenaResult, DesktopArenaTeam } from "./desktop-host";
import type { RoleId } from "./model";

export interface BattleResultRetention { status: DesktopArenaResult["retention"]; message: string }

const signatureLabels: Readonly<Record<RoleId, string>> = Object.freeze({
  hearth: "Mend", muse: "Burst", scout: "Mark", beacon: "Passage", keeper: "Clear", guardian: "Hold",
});

function boundedText(value: string, maximum: number): string {
  let text = ""; let bytes = 0;
  for (const character of value) {
    const size = new TextEncoder().encode(character).length;
    if (bytes + size > maximum) break;
    text += character; bytes += size;
  }
  return text;
}

function describeOutcome(state: BattleState, outcome: BattleOutcome): string {
  const team = state.teams[outcome.teamId === "one" ? 0 : 1];
  const actor = team.roster.find((member) => member.id === outcome.actorQiMonId)!;
  const move = outcome.action === "signature" ? signatureLabels[actor.role] :
    outcome.action === "pulse" ? "Pulse" : outcome.action === "guard" ? "Guard" : "Swap";
  const parts = [`Side ${team.id === "one" ? 1 : 2}: ${move}`,
    `impact taken ${outcome.damageTaken}, blocked ${outcome.damageAbsorbed}`];
  // This engine value precedes the opposing shield and can exceed remaining Integrity.
  // Neither value is represented as a claimed reduction in health.
  if (outcome.damageDealt) parts.push(`sent ${outcome.damageDealt} before shields`);
  if (outcome.integrityRestored) parts.push(`restored ${outcome.integrityRestored}`);
  if (outcome.selfDamage) parts.push(`self-cost ${outcome.selfDamage}`);
  if (outcome.sparkSpent) parts.push(`spent ${outcome.sparkSpent} Spark`);
  if (outcome.exposedApplied) parts.push("marked other side");
  if (outcome.exposedCleared) parts.push("cleared exposure");
  if (outcome.action === "swap") parts.push("reserve took impact on entry");
  if (outcome.action === "signature" && outcome.targetQiMonId) parts.push("reserve entered after impact");
  if (outcome.replacementQiMonId) parts.push("settled active replaced");
  return parts.join("; ") + ".";
}

function describeRound(state: BattleState, event: BattleRoundEvent): string {
  const surrendered = event.outcomes.filter((outcome) => outcome.action === "surrender");
  if (surrendered.length === 2) return "Both sides surrendered. Neither move dealt impact.";
  if (surrendered.length === 1) return `Side ${surrendered[0].teamId === "one" ? 1 : 2} surrendered. The other side's move did not execute.`;
  return boundedText(event.outcomes.map((outcome) => describeOutcome(state, outcome)).join(" "), 500);
}

/**
 * Read-only rendering of the sole reducer's public state. This function does not resolve,
 * predict, save, choose a move, or accept pending sealed commands. Retention is supplied
 * by the existing Journey owner after it observes its own Keep operation.
 */
export function buildBattleReadback(state: BattleState, retention: BattleResultRetention): DesktopArenaReadback {
  const teams = Object.freeze(state.teams.map((team) => Object.freeze({
    id: team.id, label: team.label, spark: team.spark,
    roster: Object.freeze(team.roster.map((member) => Object.freeze({
      id: member.id, name: member.name, role: member.role, integrity: member.integrity,
      maximumIntegrity: member.maximumIntegrity, active: member.id === team.activeQiMonId, exposed: member.exposed,
    }))),
  }))) as readonly [DesktopArenaTeam, DesktopArenaTeam];
  let result: DesktopArenaResult | null = null;
  if (state.status === "complete") {
    if (!state.winner || state.history.length < 1 || state.history.length > BATTLE_LIMITS.maximumRounds) {
      throw new Error("A completed battle needs a resolved result.");
    }
    const surrendered = state.history.at(-1)!.outcomes.some((outcome) => outcome.action === "surrender");
    const eliminated = state.teams.some((team) => team.roster.every((member) => member.integrity === 0));
    result = Object.freeze({ winner: state.winner, reason: surrendered ? "surrender" : eliminated ? "eliminated" : "round-limit",
      retention: retention.status, message: boundedText(retention.message, 300) });
  }
  return Object.freeze({ teams, rounds: Object.freeze(state.history.map((event) => Object.freeze({
    round: event.round, summary: describeRound(state, event),
  }))), result });
}
