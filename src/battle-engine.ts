import { ROLE_ORDER, sha256String, type RoleId } from "./model";

export const BATTLE_SCHEMA = 1 as const;
export const BATTLE_TEAM_IDS = Object.freeze(["one", "two"] as const);
export const BATTLE_ACTIONS = Object.freeze(["pulse", "guard", "signature", "swap", "surrender"] as const);
export const BATTLE_LIMITS = Object.freeze({
  minimumRoster: 1,
  maximumRoster: 3,
  teamIntegrity: 36,
  teamResonance: 12,
  teamSpark: 3,
  maximumRounds: 20,
});

export type BattleTeamId = (typeof BATTLE_TEAM_IDS)[number];
export type BattleAction = (typeof BATTLE_ACTIONS)[number];
export type BattleWinner = BattleTeamId | "draw" | null;

export interface QiMonCard {
  readonly id: string;
  readonly name: string;
  readonly role: RoleId;
}

export interface BattleTeamSetup {
  readonly id: BattleTeamId;
  readonly label: string;
  readonly bondRole: RoleId;
  readonly roster: readonly QiMonCard[];
}

export interface BattleQiMonState extends QiMonCard {
  readonly integrity: number;
  readonly maximumIntegrity: number;
  readonly resonance: number;
  readonly exposed: boolean;
}

export interface BattleTeamState {
  readonly id: BattleTeamId;
  readonly label: string;
  readonly bondRole: RoleId;
  readonly concentration: number;
  readonly spark: number;
  readonly activeQiMonId: string | null;
  readonly roster: readonly BattleQiMonState[];
}

export interface BattleCommand {
  readonly battleId: string;
  readonly round: number;
  readonly baseRevision: string;
  readonly teamId: BattleTeamId;
  readonly activeQiMonId: string;
  readonly action: BattleAction;
  readonly targetQiMonId?: string;
}

export interface BattleOutcome {
  readonly teamId: BattleTeamId;
  readonly actorQiMonId: string;
  readonly damageRecipientQiMonId: string;
  readonly action: BattleAction;
  readonly targetQiMonId: string | null;
  readonly damageDealt: number;
  readonly damageTaken: number;
  readonly damageAbsorbed: number;
  readonly integrityRestored: number;
  readonly selfDamage: number;
  readonly shieldRaised: number;
  readonly sparkSpent: number;
  readonly exposedApplied: boolean;
  readonly exposedCleared: boolean;
  readonly alignmentBonus: number;
  readonly replacementQiMonId: string | null;
}

export interface BattleRoundEvent {
  readonly round: number;
  readonly baseRevision: string;
  readonly commands: readonly [BattleCommand, BattleCommand];
  readonly outcomes: readonly [BattleOutcome, BattleOutcome];
  readonly winner: BattleWinner;
}

export interface BattleState {
  readonly schema: typeof BATTLE_SCHEMA;
  readonly battleId: string;
  readonly round: number;
  readonly status: "active" | "complete";
  readonly winner: BattleWinner;
  readonly teams: readonly [BattleTeamState, BattleTeamState];
  readonly history: readonly BattleRoundEvent[];
}

export type BattleResolution =
  | { readonly accepted: true; readonly state: BattleState; readonly event: BattleRoundEvent }
  | { readonly accepted: false; readonly state: BattleState; readonly reason: string };

interface MutableQiMonState {
  id: string;
  name: string;
  role: RoleId;
  integrity: number;
  maximumIntegrity: number;
  resonance: number;
  exposed: boolean;
}

interface MutableTeamState {
  id: BattleTeamId;
  label: string;
  bondRole: RoleId;
  concentration: number;
  spark: number;
  activeQiMonId: string | null;
  roster: MutableQiMonState[];
}

interface MutableEffect {
  damage: number;
  heal: number;
  selfDamage: number;
  shield: number;
  applyExposed: boolean;
  clearExposed: boolean;
  passageTargetId: string | null;
  sparkSpent: number;
  alignmentBonus: number;
}

function validRole(value: string): value is RoleId {
  return (ROLE_ORDER as readonly string[]).includes(value);
}

function safeId(value: string): boolean {
  return /^[a-z0-9][a-z0-9-]{0,39}$/.test(value);
}

function safeLabel(value: string): boolean {
  const trimmed = value.trim();
  return trimmed.length >= 1 && trimmed.length <= 28 && !/[\u0000-\u001f\u007f]/.test(trimmed);
}

function frozenCard(card: QiMonCard): QiMonCard {
  return Object.freeze({ id: card.id, name: card.name.trim(), role: card.role });
}

function frozenQiMon(card: BattleQiMonState): BattleQiMonState {
  return Object.freeze({ ...card });
}

function frozenTeam(team: BattleTeamState): BattleTeamState {
  return Object.freeze({ ...team, roster: Object.freeze(team.roster.map(frozenQiMon)) });
}

function frozenCommand(command: BattleCommand): BattleCommand {
  return Object.freeze({ ...command });
}

function frozenOutcome(outcome: BattleOutcome): BattleOutcome {
  return Object.freeze({ ...outcome });
}

function frozenEvent(event: BattleRoundEvent): BattleRoundEvent {
  return Object.freeze({
    ...event,
    commands: Object.freeze(event.commands.map(frozenCommand)) as readonly [BattleCommand, BattleCommand],
    outcomes: Object.freeze(event.outcomes.map(frozenOutcome)) as readonly [BattleOutcome, BattleOutcome],
  });
}

function frozenState(state: BattleState): BattleState {
  return Object.freeze({
    ...state,
    teams: Object.freeze(state.teams.map(frozenTeam)) as readonly [BattleTeamState, BattleTeamState],
    history: Object.freeze(state.history.map(frozenEvent)),
  });
}

function validateSetup(setup: BattleTeamSetup, expectedId: BattleTeamId): void {
  if (setup.id !== expectedId) throw new Error(`Expected team ${expectedId}.`);
  if (!safeLabel(setup.label)) throw new Error(`Team ${expectedId} needs a 1–28 character label.`);
  if (!validRole(setup.bondRole)) throw new Error(`Team ${expectedId} has an unknown Bond role.`);
  if (setup.roster.length < BATTLE_LIMITS.minimumRoster || setup.roster.length > BATTLE_LIMITS.maximumRoster) {
    throw new Error(`Team ${expectedId} must field 1–3 QiMon.`);
  }
  const localIds = new Set<string>();
  for (const card of setup.roster) {
    if (!safeId(card.id)) throw new Error(`QiMon id ${JSON.stringify(card.id)} is invalid.`);
    if (!safeLabel(card.name)) throw new Error(`QiMon ${card.id} needs a 1–28 character name.`);
    if (!validRole(card.role)) throw new Error(`QiMon ${card.id} has an unknown role.`);
    if (localIds.has(card.id)) throw new Error(`QiMon ${card.id} appears more than once on team ${expectedId}.`);
    localIds.add(card.id);
  }
}

function createTeam(setup: BattleTeamSetup): BattleTeamState {
  const maximumIntegrity = BATTLE_LIMITS.teamIntegrity / setup.roster.length;
  const resonance = BATTLE_LIMITS.teamResonance / setup.roster.length;
  const roster = setup.roster.map((source) => {
    const card = frozenCard(source);
    return frozenQiMon({ ...card, integrity: maximumIntegrity, maximumIntegrity, resonance, exposed: false });
  });
  return frozenTeam({
    id: setup.id,
    label: setup.label.trim(),
    bondRole: setup.bondRole,
    concentration: Math.floor(resonance / 6),
    spark: BATTLE_LIMITS.teamSpark,
    activeQiMonId: roster[0]?.id ?? null,
    roster,
  });
}

export function createBattle(
  battleId: string,
  teamOne: BattleTeamSetup,
  teamTwo: BattleTeamSetup,
): BattleState {
  if (!safeId(battleId)) throw new Error("Battle id is invalid.");
  validateSetup(teamOne, "one");
  validateSetup(teamTwo, "two");
  const allIds = [...teamOne.roster, ...teamTwo.roster].map((card) => card.id);
  if (new Set(allIds).size !== allIds.length) throw new Error("A QiMon card cannot appear on both teams.");
  return frozenState({
    schema: BATTLE_SCHEMA,
    battleId,
    round: 1,
    status: "active",
    winner: null,
    teams: [createTeam(teamOne), createTeam(teamTwo)],
    history: [],
  });
}

function canonicalBattleState(state: BattleState): unknown {
  return {
    schema: state.schema,
    battleId: state.battleId,
    round: state.round,
    status: state.status,
    winner: state.winner,
    teams: state.teams.map((team) => ({
      id: team.id,
      label: team.label,
      bondRole: team.bondRole,
      concentration: team.concentration,
      spark: team.spark,
      activeQiMonId: team.activeQiMonId,
      roster: team.roster.map((card) => ({
        id: card.id,
        name: card.name,
        role: card.role,
        integrity: card.integrity,
        maximumIntegrity: card.maximumIntegrity,
        resonance: card.resonance,
        exposed: card.exposed,
      })),
    })),
    history: state.history,
  };
}

export function battleRevision(state: BattleState): string {
  return `sha256:${sha256String(JSON.stringify(canonicalBattleState(state)))}`;
}

export function createBattleCommand(
  state: BattleState,
  teamId: BattleTeamId,
  action: BattleAction,
  targetQiMonId?: string,
): BattleCommand {
  const team = state.teams.find((candidate) => candidate.id === teamId);
  if (!team?.activeQiMonId) throw new Error(`Team ${teamId} has no active QiMon.`);
  return frozenCommand({
    battleId: state.battleId,
    round: state.round,
    baseRevision: battleRevision(state),
    teamId,
    activeQiMonId: team.activeQiMonId,
    action,
    ...(targetQiMonId ? { targetQiMonId } : {}),
  });
}

function cloneTeam(team: BattleTeamState): MutableTeamState {
  return { ...team, roster: team.roster.map((card) => ({ ...card })) };
}

function activeQiMon(team: MutableTeamState): MutableQiMonState {
  const active = team.roster.find((card) => card.id === team.activeQiMonId && card.integrity > 0);
  if (!active) throw new Error(`Team ${team.id} has no living active QiMon.`);
  return active;
}

function validateCommand(state: BattleState, command: BattleCommand, expectedTeam: BattleTeamId): string | null {
  const team = state.teams.find((candidate) => candidate.id === expectedTeam);
  if (state.status !== "active") return "The battle is already complete.";
  if (command.battleId !== state.battleId) return "The command belongs to another battle.";
  if (command.round !== state.round) return "The command is for a stale round.";
  if (command.baseRevision !== battleRevision(state)) return "The command is based on stale battle state.";
  if (command.teamId !== expectedTeam) return `Expected a command from team ${expectedTeam}.`;
  if (!team?.activeQiMonId || command.activeQiMonId !== team.activeQiMonId) return "Only the current active QiMon may act.";
  if (!(BATTLE_ACTIONS as readonly string[]).includes(command.action)) return "The command uses an unknown action.";
  if (command.action === "signature" && team.spark < 1) return "No shared Spark remains for a signature.";
  if (command.action === "swap") {
    const target = team.roster.find((card) => card.id === command.targetQiMonId);
    if (!target || target.integrity <= 0 || target.id === team.activeQiMonId) return "Swap target must be a living reserve QiMon.";
  } else if (command.action === "signature") {
    const active = team.roster.find((card) => card.id === team.activeQiMonId);
    if (active?.role === "beacon" && command.targetQiMonId) {
      const target = team.roster.find((card) => card.id === command.targetQiMonId);
      if (!target || target.integrity <= 0 || target.id === team.activeQiMonId) {
        return "Beacon passage target must be a living reserve QiMon.";
      }
    } else if (command.targetQiMonId) {
      return "Only Swap or Beacon Passage may name a reserve target.";
    }
  } else if (command.targetQiMonId) {
    return "This action does not accept a QiMon target.";
  }
  return null;
}

function effectFor(team: MutableTeamState, command: BattleCommand): MutableEffect {
  const actor = activeQiMon(team);
  const alignmentBonus = actor.role === team.bondRole ? 1 : 0;
  const focus = team.concentration + alignmentBonus;
  const effect: MutableEffect = {
    damage: 0,
    heal: 0,
    selfDamage: 0,
    shield: 0,
    applyExposed: false,
    clearExposed: false,
    passageTargetId: null,
    sparkSpent: 0,
    alignmentBonus,
  };
  if (command.action === "pulse") effect.damage = 4 + focus;
  else if (command.action === "guard") effect.shield = 4 + focus;
  else if (command.action === "signature") {
    effect.sparkSpent = 1;
    if (actor.role === "hearth") {
      effect.damage = 2 + focus;
      effect.heal = 4;
    } else if (actor.role === "muse") {
      effect.damage = 8 + focus;
      effect.selfDamage = 2;
    } else if (actor.role === "scout") {
      effect.damage = 3 + focus;
      effect.applyExposed = true;
    } else if (actor.role === "beacon") {
      effect.damage = 3 + focus;
      effect.passageTargetId = command.targetQiMonId ?? null;
      if (!effect.passageTargetId && team.roster.filter((card) => card.integrity > 0).length === 1) effect.damage += 2;
    } else if (actor.role === "keeper") {
      effect.clearExposed = true;
      effect.damage = 4 + focus + (actor.exposed ? 0 : 2);
    } else {
      effect.shield = 4 + focus;
      effect.damage = 2 + focus;
    }
  }
  return effect;
}

/** A local practice policy over public state; sealed commands are never an input. */
export function choosePracticeCommand(state: BattleState, teamId: BattleTeamId): BattleCommand {
  if (state.status !== "active") throw new Error("The battle is already complete.");
  const team = state.teams.find((candidate) => candidate.id === teamId);
  const opponent = state.teams.find((candidate) => candidate.id !== teamId);
  const actor = team?.roster.find((card) => card.id === team.activeQiMonId && card.integrity > 0);
  const opposingActor = opponent?.roster.find((card) => card.id === opponent.activeQiMonId && card.integrity > 0);
  if (!team || !actor) throw new Error(`Team ${teamId} has no living active QiMon.`);
  if (!opponent || !opposingActor) throw new Error("The opposing team has no living active QiMon.");

  const choose = (action: BattleAction, targetQiMonId?: string): BattleCommand => {
    const command = createBattleCommand(state, teamId, action, targetQiMonId);
    const invalid = validateCommand(state, command, teamId);
    if (invalid) throw new Error(invalid);
    return command;
  };
  const pulse = choose("pulse");
  // Reuse the reducer's effects, rather than maintain a second power formula.
  const pulseEffect = effectFor(cloneTeam(team), pulse);
  if (opposingActor.integrity <= pulseEffect.damage) return pulse;

  const canUseSpark = team.spark >= 1;
  const hurt = actor.integrity <= actor.maximumIntegrity * 2 / 3;
  if (canUseSpark && actor.role === "hearth" && hurt) return choose("signature");
  if (canUseSpark && actor.role === "keeper" && actor.exposed) return choose("signature");

  // Stable roster order breaks equal-health ties. Never target an exhausted member.
  const reserve = team.roster.reduce<BattleQiMonState | null>((best, card) =>
    card.id !== actor.id && card.integrity > 0 && (!best || card.integrity > best.integrity) ? card : best, null);
  const needsRelief = actor.integrity <= actor.maximumIntegrity / (actor.role === "beacon" ? 2 : 3);
  if (needsRelief && reserve && reserve.integrity > actor.integrity) {
    return canUseSpark && actor.role === "beacon" ? choose("signature", reserve.id) : choose("swap", reserve.id);
  }

  const pressingRound = state.round % 3 === 1;
  if (canUseSpark) {
    const signature = choose("signature");
    const effect = effectFor(cloneTeam(team), signature);
    const survivesOwnEffect = actor.integrity > effect.selfDamage;
    const canFinish = effect.damage >= opposingActor.integrity;
    if (survivesOwnEffect && canFinish) return signature;
    if (actor.role === "muse" && survivesOwnEffect && pressingRound) return signature;
    if (actor.role === "scout" && !opposingActor.exposed && pressingRound) return signature;
    if (actor.role === "beacon" && !reserve && pressingRound) return signature;
    if (actor.role === "keeper" && pressingRound) return signature;
    if (actor.role === "guardian" && (pressingRound || hurt || actor.exposed)) return signature;
  }
  // Guard does not regenerate Spark. A brief defensive beat is followed by attack,
  // and the final round remains active rather than waiting out the round limit.
  if (state.round % 3 === 0 && state.round < BATTLE_LIMITS.maximumRounds && (hurt || actor.exposed)) {
    return choose("guard");
  }
  return pulse;
}

function totalIntegrity(team: MutableTeamState | BattleTeamState): number {
  let total = 0;
  for (const card of team.roster) total += card.integrity;
  return total;
}

function replacementFor(team: MutableTeamState): string | null {
  return team.roster.find((card) => card.integrity > 0)?.id ?? null;
}

function winnerFor(teams: readonly [MutableTeamState, MutableTeamState], atRoundLimit: boolean): BattleWinner {
  const oneIntegrity = totalIntegrity(teams[0]);
  const twoIntegrity = totalIntegrity(teams[1]);
  if (oneIntegrity <= 0 && twoIntegrity <= 0) return "draw";
  if (oneIntegrity <= 0) return "two";
  if (twoIntegrity <= 0) return "one";
  if (!atRoundLimit) return null;
  if (oneIntegrity !== twoIntegrity) return oneIntegrity > twoIntegrity ? "one" : "two";
  if (teams[0].spark !== teams[1].spark) return teams[0].spark > teams[1].spark ? "one" : "two";
  return "draw";
}

function emptyOutcome(team: MutableTeamState, command: BattleCommand): BattleOutcome {
  return {
    teamId: team.id,
    actorQiMonId: command.activeQiMonId,
    damageRecipientQiMonId: command.activeQiMonId,
    action: command.action,
    targetQiMonId: command.targetQiMonId ?? null,
    damageDealt: 0,
    damageTaken: 0,
    damageAbsorbed: 0,
    integrityRestored: 0,
    selfDamage: 0,
    shieldRaised: 0,
    sparkSpent: 0,
    exposedApplied: false,
    exposedCleared: false,
    alignmentBonus: 0,
    replacementQiMonId: null,
  };
}

export function resolveBattleRound(
  state: BattleState,
  commandOne: BattleCommand,
  commandTwo: BattleCommand,
): BattleResolution {
  const invalidOne = validateCommand(state, commandOne, "one");
  if (invalidOne) return Object.freeze({ accepted: false, state, reason: invalidOne });
  const invalidTwo = validateCommand(state, commandTwo, "two");
  if (invalidTwo) return Object.freeze({ accepted: false, state, reason: invalidTwo });

  const teams = [cloneTeam(state.teams[0]), cloneTeam(state.teams[1])] as [MutableTeamState, MutableTeamState];
  const commands = [commandOne, commandTwo] as const;
  const mutableOutcomes = [emptyOutcome(teams[0], commandOne), emptyOutcome(teams[1], commandTwo)] as [BattleOutcome, BattleOutcome];

  let winner: BattleWinner = null;
  const surrenderOne = commandOne.action === "surrender";
  const surrenderTwo = commandTwo.action === "surrender";
  if (surrenderOne || surrenderTwo) winner = surrenderOne && surrenderTwo ? "draw" : surrenderOne ? "two" : "one";

  if (!winner) {
    for (let index = 0; index < 2; index += 1) {
      const command = commands[index];
      if (command.action === "swap") teams[index].activeQiMonId = command.targetQiMonId ?? null;
    }

    const effects = commands.map((command, index) => effectFor(teams[index], command)) as [MutableEffect, MutableEffect];
    const actors = [activeQiMon(teams[0]), activeQiMon(teams[1])] as const;

    const exposedCleared = [false, false] as [boolean, boolean];
    for (let index = 0; index < 2; index += 1) {
      const effect = effects[index];
      const actor = actors[index];
      exposedCleared[index] = effect.clearExposed && actor.exposed;
      if (exposedCleared[index]) actor.exposed = false;
    }

    const rawIncoming = [effects[1].damage, effects[0].damage] as [number, number];
    const exposedBonuses = [
      actors[0].exposed && rawIncoming[0] > 0 ? 3 : 0,
      actors[1].exposed && rawIncoming[1] > 0 ? 3 : 0,
    ] as const;
    const outgoingDamage = [
      effects[0].damage + exposedBonuses[1],
      effects[1].damage + exposedBonuses[0],
    ] as const;
    for (let index = 0; index < 2; index += 1) {
      const actor = actors[index];
      const effect = effects[index];
      const exposedBonus = exposedBonuses[index];
      const incoming = rawIncoming[index] + exposedBonus;
      const absorbed = Math.min(effect.shield, incoming);
      const taken = incoming - absorbed;
      const before = actor.integrity;
      const withoutHealing = Math.max(0, before - taken - effect.selfDamage);
      actor.integrity = Math.max(
        0,
        Math.min(actor.maximumIntegrity, before - taken - effect.selfDamage + effect.heal),
      );
      const restored = Math.max(0, actor.integrity - withoutHealing);
      if (exposedBonus > 0) actor.exposed = false;
      teams[index].spark -= effect.sparkSpent;
      mutableOutcomes[index] = {
        ...mutableOutcomes[index],
        damageRecipientQiMonId: actor.id,
        damageDealt: outgoingDamage[index],
        damageTaken: taken,
        damageAbsorbed: absorbed,
        integrityRestored: restored,
        selfDamage: effect.selfDamage,
        shieldRaised: effect.shield,
        sparkSpent: effect.sparkSpent,
        exposedCleared: exposedCleared[index],
        alignmentBonus: effect.alignmentBonus,
      };
    }

    for (let index = 0; index < 2; index += 1) {
      const target = actors[1 - index];
      if (effects[index].applyExposed && target.integrity > 0) {
        target.exposed = true;
        mutableOutcomes[index] = { ...mutableOutcomes[index], exposedApplied: true };
      }
      const passageTargetId = effects[index].passageTargetId;
      if (passageTargetId && teams[index].roster.some((card) => card.id === passageTargetId && card.integrity > 0)) {
        teams[index].activeQiMonId = passageTargetId;
      }
    }

    for (let index = 0; index < 2; index += 1) {
      const active = teams[index].roster.find((card) => card.id === teams[index].activeQiMonId);
      if (!active || active.integrity <= 0) {
        const replacementQiMonId = replacementFor(teams[index]);
        teams[index].activeQiMonId = replacementQiMonId;
        mutableOutcomes[index] = { ...mutableOutcomes[index], replacementQiMonId };
      }
    }

    winner = winnerFor(teams, state.round >= BATTLE_LIMITS.maximumRounds);
  }

  const nextTeams = teams.map((team) =>
    frozenTeam({ ...team, roster: team.roster.map((card) => frozenQiMon(card)) }),
  ) as [BattleTeamState, BattleTeamState];
  const event = frozenEvent({
    round: state.round,
    baseRevision: battleRevision(state),
    commands: [commandOne, commandTwo],
    outcomes: mutableOutcomes,
    winner,
  });
  const nextState = frozenState({
    ...state,
    round: state.round + 1,
    status: winner ? "complete" : "active",
    winner,
    teams: nextTeams,
    history: [...state.history, event],
  });
  return Object.freeze({ accepted: true, state: nextState, event });
}

export function livingQiMon(team: BattleTeamState): readonly BattleQiMonState[] {
  return Object.freeze(team.roster.filter((card) => card.integrity > 0));
}

export function teamIntegrity(team: BattleTeamState): number {
  return totalIntegrity(team);
}

/** A legal move's own effects, not a prediction of the opposing sealed move. */
export function previewBattleCommand(state: BattleState, command: BattleCommand): Readonly<MutableEffect> | null {
  if (!BATTLE_TEAM_IDS.includes(command.teamId) || validateCommand(state, command, command.teamId)) return null;
  const team = cloneTeam(state.teams[command.teamId === "one" ? 0 : 1]);
  if (command.action === "surrender") return Object.freeze({ damage: 0, heal: 0, selfDamage: 0, shield: 0,
    applyExposed: false, clearExposed: false, passageTargetId: null, sparkSpent: 0, alignmentBonus: 0 });
  if (command.action === "swap") team.activeQiMonId = command.targetQiMonId ?? null;
  return Object.freeze(effectFor(team, command));
}

export interface PracticeReplay {
  readonly rulesVersion: 1;
  readonly battleId: string;
  readonly teams: readonly [BattleTeamSetup, BattleTeamSetup];
  readonly commands: readonly (readonly [BattleCommand, BattleCommand])[];
}

function exactRecord(value: unknown, keys: readonly string[]): value is Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value) || ![Object.prototype, null].includes(Object.getPrototypeOf(value))) return false;
  const names = Reflect.ownKeys(value);
  return names.length === keys.length && keys.every((key) => {
    const field = Object.getOwnPropertyDescriptor(value, key);
    return field && Object.hasOwn(field, "value");
  });
}

function denseArray(value: unknown): value is unknown[] {
  return Array.isArray(value) && Reflect.ownKeys(value).length === value.length + 1 &&
    Array.from({ length: value.length }, (_, index) => Object.getOwnPropertyDescriptor(value, String(index)))
      .every((field) => field && Object.hasOwn(field, "value"));
}

/** Reconstruct from setup and accepted commands; never trust submitted outcomes. */
export function replayCompletedPractice(value: unknown): Readonly<{ replay: PracticeReplay; state: BattleState; digest: string }> {
  if (!exactRecord(value, ["rulesVersion", "battleId", "teams", "commands"]) || value.rulesVersion !== 1 ||
      typeof value.battleId !== "string" || !/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(value.battleId) ||
      !Array.isArray(value.teams) || value.teams.length !== 2 || !denseArray(value.teams) || !Array.isArray(value.commands) ||
      value.commands.length < 1 || value.commands.length > BATTLE_LIMITS.maximumRounds || !denseArray(value.commands)) throw new Error("Invalid practice replay.");
  const teams = value.teams.map((team, index): BattleTeamSetup => {
    if (!exactRecord(team, ["id", "label", "bondRole", "roster"]) || team.id !== BATTLE_TEAM_IDS[index] ||
        typeof team.label !== "string" || typeof team.bondRole !== "string" || !validRole(team.bondRole) ||
        !Array.isArray(team.roster) || team.roster.length < 1 || team.roster.length > 3 || !denseArray(team.roster)) throw new Error("Invalid practice formation.");
    const roster = team.roster.map((card): QiMonCard => {
      if (!exactRecord(card, ["id", "name", "role"]) || typeof card.id !== "string" || typeof card.name !== "string" ||
          typeof card.role !== "string" || !validRole(card.role)) throw new Error("Invalid practice member.");
      return { id: card.id, name: card.name, role: card.role };
    });
    return { id: team.id as BattleTeamId, label: team.label, bondRole: team.bondRole, roster };
  }) as [BattleTeamSetup, BattleTeamSetup];
  let state = createBattle(value.battleId, teams[0], teams[1]);
  const commands: [BattleCommand, BattleCommand][] = [];
  for (const pair of value.commands) {
    if (!Array.isArray(pair) || pair.length !== 2 || !denseArray(pair) || state.status !== "active") throw new Error("Invalid practice round sequence.");
    const canonical = pair.map((command, index): BattleCommand => {
      const keys = ["battleId", "round", "baseRevision", "teamId", "activeQiMonId", "action"];
      if (command && typeof command === "object" && Object.hasOwn(command, "targetQiMonId")) keys.push("targetQiMonId");
      if (!exactRecord(command, keys) || command.teamId !== BATTLE_TEAM_IDS[index] ||
          typeof command.action !== "string" || !(BATTLE_ACTIONS as readonly string[]).includes(command.action) || command.action === "surrender" ||
          (Object.hasOwn(command, "targetQiMonId") && typeof command.targetQiMonId !== "string")) throw new Error("A kept practice requires complete non-surrender rounds.");
      const expected = createBattleCommand(state, command.teamId as BattleTeamId, command.action as BattleAction, command.targetQiMonId as string | undefined);
      if (keys.some((key) => command[key] !== expected[key as keyof BattleCommand]) ||
          validateCommand(state, expected, expected.teamId)) throw new Error("A practice command is stale or invalid.");
      return expected;
    }) as [BattleCommand, BattleCommand];
    if (JSON.stringify(canonical[1]) !== JSON.stringify(choosePracticeCommand(state, "two"))) throw new Error("Only the public-state practice partner can supply the kept opponent command.");
    const result = resolveBattleRound(state, canonical[0], canonical[1]);
    if (!result.accepted) throw new Error(result.reason);
    commands.push(canonical);
    state = result.state;
  }
  if (state.status !== "complete") throw new Error("Finish the practice before keeping it.");
  const replay: PracticeReplay = Object.freeze({ rulesVersion: 1, battleId: value.battleId,
    teams: Object.freeze(teams.map((team) => Object.freeze({ ...team, roster: Object.freeze(team.roster.map(frozenCard)) }))) as unknown as PracticeReplay["teams"],
    commands: Object.freeze(commands.map((pair) => Object.freeze(pair))) });
  return Object.freeze({ replay, state, digest: sha256String(JSON.stringify(replay)) });
}
