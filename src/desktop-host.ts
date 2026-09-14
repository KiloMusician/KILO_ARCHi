/** The native host receives a projection only. Journey authority stays in the game. */
export const DESKTOP_HOST_VERSION = 1;
export const DESKTOP_PROJECTION_VERSION = 4;
export const DESKTOP_HOST_NAME = "archi-desktop";

export interface DesktopHostBootstrap {
  version: 1;
  host: "archi-desktop";
  sessionId: string;
  visible: boolean;
}

export type DesktopPlayMode = "habitat" | "field" | "proposal" | "reflection" | "battle" | "relay";
export interface DesktopPracticeSummary {
  originDigest: string; eventId: string; battleId: string; rulesVersion: 1; rounds: number;
  outcome: "won" | "lost" | "draw"; replayDigest: string; committedAt: string;
}
export interface DesktopArenaAction { id: string; label: string; detail: string }
export interface DesktopArenaWhatIf {
  choices: readonly DesktopArenaAction[];
  firstId: string; secondId: string;
  cases: readonly { opponentId: string; opponentLabel: string; first: string; second: string }[];
}
export interface DesktopArenaMember {
  id: string; name: string; role: "hearth" | "muse" | "scout" | "beacon" | "keeper" | "guardian";
  integrity: number; maximumIntegrity: number; active: boolean; exposed: boolean;
}
export interface DesktopArenaTeam {
  id: "one" | "two"; label: string; spark: number; roster: readonly DesktopArenaMember[];
}
export interface DesktopArenaRound { round: number; summary: string }
export interface DesktopArenaResult {
  winner: "one" | "two" | "draw"; reason: "eliminated" | "round-limit" | "surrender";
  retention: "unsaved" | "saving" | "saved" | "session-only" | "unavailable"; message: string;
}
/** Public resolved state only. Pending commands and partner policy are never included. */
export interface DesktopArenaReadback {
  teams: readonly [DesktopArenaTeam, DesktopArenaTeam]; rounds: readonly DesktopArenaRound[];
  result: DesktopArenaResult | null;
}
export interface DesktopArenaState {
  battleId: string | null; revision: string; phase: "entry" | "planning" | "sealed" | "finished";
  round: number; summary: string; actions: readonly DesktopArenaAction[];
  whatIf: DesktopArenaWhatIf | null;
  readback: DesktopArenaReadback | null;
}
interface DesktopExperienceState {
  originDigest: string | null; practices: readonly DesktopPracticeSummary[]; arena: DesktopArenaState | null;
}
export type DesktopJourneyState = DesktopExperienceState & (
  | { readiness: "loading"; storage: "unknown"; mode: "habitat"; journeyId: null; revision: null; eventCount: null }
  | {
      readiness: "ready";
      storage: "local-browser" | "session-only" | "qa-ephemeral";
      mode: DesktopPlayMode;
      journeyId: string;
      revision: string;
      eventCount: number;
    });

export type DesktopJourneyProjection = DesktopJourneyState & {
  version: 4;
  host: "archi-desktop";
  sessionId: string;
  sequence: number;
  kind: "journey-projection";
  visible: boolean;
};

interface DesktopVisibilityMessage extends DesktopHostBootstrap {
  sequence: number;
}

export interface DesktopHostAPI {
  setVisibility(message: unknown): boolean;
  setAppearance(message: unknown): boolean;
  performArenaAction(message: unknown): boolean;
}

/** Rendered by the existing native CompanionPresenceArt; no save or identity payload. */
export interface DesktopAppearance {
  id: string;
  label: string;
  png: string;
  reduceMotion: boolean;
}

export interface DesktopHostEnvironment {
  __ARCHI_DESKTOP_BOOTSTRAP__?: unknown;
  __ARCHI_DESKTOP_HOST__?: DesktopHostAPI;
  webkit?: { messageHandlers?: { archiJourneyProjection?: { postMessage(message: DesktopJourneyProjection): void } } };
  document?: { visibilityState: string };
}

declare global {
  interface Window extends DesktopHostEnvironment {}
}

const bootstrapKeys = ["version", "host", "sessionId", "visible"];
const uuidPattern = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const modes: readonly string[] = ["habitat", "field", "proposal", "reflection", "battle", "relay"];

function exactRecord(value: unknown, keys: readonly string[]): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value) &&
    [Object.prototype, null].includes(Object.getPrototypeOf(value)) &&
    Reflect.ownKeys(value).length === keys.length && keys.every((key) => {
      const field = Object.getOwnPropertyDescriptor(value, key);
      return field && Object.hasOwn(field, "value");
    });
}

function denseArray(value: unknown): boolean {
  return Array.isArray(value) && Reflect.ownKeys(value).length === value.length + 1 &&
    Array.from({ length: value.length }, (_, index) => Object.getOwnPropertyDescriptor(value, String(index)))
      .every((field) => field && Object.hasOwn(field, "value"));
}

function boundedText(value: unknown, maximum: number, allowEmpty = false): value is string {
  return typeof value === "string" && (allowEmpty || value.length > 0) && new TextEncoder().encode(value).length <= maximum;
}

function validArenaAction(value: unknown): value is DesktopArenaAction {
  return exactRecord(value, ["id", "label", "detail"]) && boundedText(value.id, 160) &&
    boundedText(value.label, 120) && boundedText(value.detail, 300, true);
}

function validWhatIf(value: unknown): value is DesktopArenaWhatIf {
  if (!exactRecord(value, ["choices", "firstId", "secondId", "cases"]) ||
      !Array.isArray(value.choices) || !denseArray(value.choices) || value.choices.length < 2 || value.choices.length > 7 ||
      !value.choices.every(validArenaAction) || new Set(value.choices.map((choice) => choice.id)).size !== value.choices.length ||
      !boundedText(value.firstId, 160) || !boundedText(value.secondId, 160) || value.firstId === value.secondId ||
      !value.choices.some((choice) => choice.id === value.firstId) || !value.choices.some((choice) => choice.id === value.secondId) ||
      !Array.isArray(value.cases) || !denseArray(value.cases) || value.cases.length < 1 || value.cases.length > 7 ||
      !value.cases.every((item) => exactRecord(item, ["opponentId", "opponentLabel", "first", "second"]) &&
        boundedText(item.opponentId, 160) && boundedText(item.opponentLabel, 120) &&
        boundedText(item.first, 700) && boundedText(item.second, 700)) ||
      new Set(value.cases.map((item) => item.opponentId)).size !== value.cases.length) return false;
  return true;
}

function boundedInteger(value: unknown, minimum: number, maximum: number): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= minimum && value <= maximum;
}

function validReadback(value: unknown): value is DesktopArenaReadback {
  if (!exactRecord(value, ["teams", "rounds", "result"]) || !Array.isArray(value.teams) ||
      !denseArray(value.teams) || value.teams.length !== 2) return false;
  const memberIDs = new Set<string>();
  for (const [index, team] of value.teams.entries()) {
    if (!exactRecord(team, ["id", "label", "spark", "roster"]) || team.id !== ["one", "two"][index] ||
        !boundedText(team.label, 120) || !boundedInteger(team.spark, 0, 3) || !Array.isArray(team.roster) ||
        !denseArray(team.roster) || team.roster.length < 1 || team.roster.length > 3) return false;
    let maximumIntegrity = 0; let activeCount = 0;
    for (const member of team.roster) {
      if (!exactRecord(member, ["id", "name", "role", "integrity", "maximumIntegrity", "active", "exposed"]) ||
          !boundedText(member.id, 160) || memberIDs.has(member.id) || !boundedText(member.name, 120) ||
          !["hearth", "muse", "scout", "beacon", "keeper", "guardian"].includes(member.role as string) ||
          !boundedInteger(member.maximumIntegrity, 1, 36) || !boundedInteger(member.integrity, 0, member.maximumIntegrity) ||
          typeof member.active !== "boolean" || typeof member.exposed !== "boolean" ||
          (member.active && member.integrity === 0)) return false;
      memberIDs.add(member.id); maximumIntegrity += member.maximumIntegrity;
      if (member.active) activeCount += 1;
    }
    if (maximumIntegrity !== 36 || activeCount > 1) return false;
  }
  if (!Array.isArray(value.rounds) || !denseArray(value.rounds) || value.rounds.length > 20 ||
      !value.rounds.every((item, index) => exactRecord(item, ["round", "summary"]) && item.round === index + 1 &&
        boundedText(item.summary, 500))) return false;
  const result = value.result;
  return result === null || (exactRecord(result, ["winner", "reason", "retention", "message"]) &&
    ["one", "two", "draw"].includes(result.winner as string) &&
    ["eliminated", "round-limit", "surrender"].includes(result.reason as string) &&
    ["unsaved", "saving", "saved", "session-only", "unavailable"].includes(result.retention as string) && boundedText(result.message, 300));
}

function copyArena(arena: DesktopArenaState | null): DesktopArenaState | null {
  const copyTeam = (team: DesktopArenaTeam): DesktopArenaTeam => ({ ...team, roster: team.roster.map((member) => ({ ...member })) });
  return arena ? { ...arena, actions: arena.actions.map((item) => ({ ...item })),
    whatIf: arena.whatIf ? { ...arena.whatIf, choices: arena.whatIf.choices.map((item) => ({ ...item })),
      cases: arena.whatIf.cases.map((item) => ({ ...item })) } : null,
    readback: arena.readback ? { teams: [copyTeam(arena.readback.teams[0]), copyTeam(arena.readback.teams[1])],
      rounds: arena.readback.rounds.map((round) => ({ ...round })), result: arena.readback.result ? { ...arena.readback.result } : null } : null } : null;
}

/** Query parameters, user agents, or a similarly named global alone never enable embedding. */
export function readDesktopHostBootstrap(environment: DesktopHostEnvironment): DesktopHostBootstrap | null {
  try {
    const raw = environment.__ARCHI_DESKTOP_BOOTSTRAP__;
    if (!exactRecord(raw, bootstrapKeys) || raw.version !== DESKTOP_HOST_VERSION ||
        raw.host !== DESKTOP_HOST_NAME || typeof raw.sessionId !== "string" || !uuidPattern.test(raw.sessionId) ||
        typeof raw.visible !== "boolean" ||
        typeof environment.webkit?.messageHandlers?.archiJourneyProjection?.postMessage !== "function") return null;
    return { version: 1, host: DESKTOP_HOST_NAME, sessionId: raw.sessionId, visible: raw.visible };
  } catch {
    return null;
  }
}

function isVisibilityMessage(value: unknown, sessionId: string): value is DesktopVisibilityMessage {
  return exactRecord(value, [...bootstrapKeys, "sequence"]) && value.version === DESKTOP_HOST_VERSION &&
    value.host === DESKTOP_HOST_NAME && value.sessionId === sessionId && typeof value.visible === "boolean" &&
    Number.isSafeInteger(value.sequence) && (value.sequence as number) > 0;
}

function validExperience(state: DesktopExperienceState): boolean {
  const digest = (value: unknown): value is string => typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
  if (state.originDigest !== null && !digest(state.originDigest)) return false;
  if (!Array.isArray(state.practices) || state.practices.length > 8 || !denseArray(state.practices) ||
      new Set(state.practices.map((item) => item.eventId)).size !== state.practices.length) return false;
  for (const item of state.practices) {
    if (!exactRecord(item, ["originDigest", "eventId", "battleId", "rulesVersion", "rounds", "outcome", "replayDigest", "committedAt"]) ||
        item.originDigest !== state.originDigest || !digest(item.originDigest) || typeof item.eventId !== "string" ||
        !/^event-[1-9][0-9]*-[a-f0-9]{64}$/.test(item.eventId) || typeof item.battleId !== "string" || !uuidPattern.test(item.battleId) ||
        item.rulesVersion !== 1 || typeof item.rounds !== "number" || !Number.isInteger(item.rounds) || item.rounds < 1 || item.rounds > 20 ||
        (typeof item.outcome !== "string" || !["won", "lost", "draw"].includes(item.outcome)) || !digest(item.replayDigest) ||
        typeof item.committedAt !== "string" || !Number.isFinite(Date.parse(item.committedAt)) || new Date(item.committedAt).toISOString() !== item.committedAt) return false;
  }
  const arena = state.arena;
  if (arena !== null && (!exactRecord(arena, ["battleId", "revision", "phase", "round", "summary", "actions", "whatIf", "readback"]) ||
      (arena.battleId !== null && (typeof arena.battleId !== "string" || !uuidPattern.test(arena.battleId))) ||
      !digest(arena.revision) || !["entry", "planning", "sealed", "finished"].includes(arena.phase) ||
      !Number.isInteger(arena.round) || arena.round < 0 || arena.round > 20 || !boundedText(arena.summary, 500) ||
      !Array.isArray(arena.actions) || arena.actions.length > 32 || !denseArray(arena.actions) || new Set(arena.actions.map((item) => item.id)).size !== arena.actions.length ||
      !arena.actions.every(validArenaAction) || (arena.whatIf !== null && !validWhatIf(arena.whatIf)) ||
      (arena.readback !== null && !validReadback(arena.readback)))) return false;
  if (arena && (arena.phase === "entry" ? arena.battleId !== null || arena.round !== 0 : arena.battleId === null || arena.round < 1)) return false;
  if (arena?.whatIf && arena.phase !== "planning") return false;
  if (arena && (arena.phase === "entry" ? arena.readback !== null : arena.readback === null)) return false;
  if (arena?.readback && (arena.phase === "finished" ?
    arena.readback.result === null || arena.readback.rounds.length !== arena.round :
    arena.readback.result !== null || arena.readback.rounds.length !== arena.round - 1)) return false;
  return true;
}

function validState(state: DesktopJourneyState): boolean {
  if (!validExperience(state)) return false;
  if (state.readiness === "loading") {
    return state.storage === "unknown" && state.mode === "habitat" && state.journeyId === null &&
      state.revision === null && state.eventCount === null && state.originDigest === null && state.practices.length === 0 && state.arena === null;
  }
  return state.readiness === "ready" && ["local-browser", "session-only", "qa-ephemeral"].includes(state.storage) &&
    state.originDigest !== null &&
    (state.arena === null || ["habitat", "battle"].includes(state.mode)) &&
    modes.includes(state.mode) && typeof state.journeyId === "string" && /^ARCHI-[A-F0-9]{8}$/.test(state.journeyId) &&
    typeof state.revision === "string" && state.revision.length > 0 && state.revision.length <= 160 &&
    Number.isSafeInteger(state.eventCount) && state.eventCount >= 0;
}

export interface DesktopHostBridge {
  readonly visible: boolean;
  publish(state: DesktopJourneyState): boolean;
  onVisibilityChange(listener: (visible: boolean) => void): void;
  onAppearanceChange(listener: (appearance: DesktopAppearance) => void): void;
  onArenaAction(listener: (actionId: string, expectedRevision: string) => boolean): void;
  setDocumentVisibility(visible: boolean): void;
  dispose(): void;
}

export interface DesktopInteractionLease {
  readonly signal: AbortSignal;
  isCurrent(): boolean;
  finish(): void;
}

/** A hide retires pending interactions permanently, even if a lock ignores cancellation. */
export function createDesktopInteractionScope(isVisible: () => boolean): {
  capture(): (() => boolean) | null;
  begin(): DesktopInteractionLease | null;
  invalidate(): void;
} {
  let generation = 0;
  const active = new Set<AbortController>();
  return {
    capture(): (() => boolean) | null {
      if (!isVisible()) return null;
      const capturedGeneration = generation;
      return () => capturedGeneration === generation && isVisible();
    },
    begin(): DesktopInteractionLease | null {
      if (!isVisible()) return null;
      const capturedGeneration = generation;
      const controller = new AbortController();
      active.add(controller);
      return {
        signal: controller.signal,
        isCurrent: () => capturedGeneration === generation && !controller.signal.aborted && isVisible(),
        finish: () => { active.delete(controller); },
      };
    },
    invalidate(): void {
      generation += 1;
      for (const controller of active) controller.abort();
      active.clear();
    },
  };
}

/** Native owns presence and its appearance; it cannot call a game reducer or replace a save. */
export function connectDesktopHost(environment: DesktopHostEnvironment): DesktopHostBridge | null {
  const bootstrap = readDesktopHostBootstrap(environment);
  if (!bootstrap) return null;
  const transport = environment.webkit!.messageHandlers!.archiJourneyProjection!;
  let hostVisible = bootstrap.visible;
  let documentVisible = environment.document?.visibilityState !== "hidden";
  let visibilitySequence = 0;
  let projectionSequence = 0;
  let disposed = false;
  let lastSent = "";
  let listener: ((visible: boolean) => void) | null = null;
  let appearanceListener: ((appearance: DesktopAppearance) => void) | null = null;
  let appearance: DesktopAppearance | null = null;
  let appearanceSequence = 0;
  let arenaListener: ((actionId: string, expectedRevision: string) => boolean) | null = null;
  const usedCommandIDs = new Set<string>();
  let state: DesktopJourneyState = {
    readiness: "loading", storage: "unknown", mode: "habitat", journeyId: null, revision: null, eventCount: null,
    originDigest: null, practices: [], arena: null,
  };
  const visible = (): boolean => hostVisible && documentVisible;

  function emit(): boolean {
    if (disposed) return false;
    // Select fields explicitly: caller objects cannot smuggle documents, events, or other data to native.
    const selected = {
      readiness: state.readiness, storage: state.storage, mode: state.mode,
      journeyId: state.journeyId, revision: state.revision, eventCount: state.eventCount, visible: visible(),
      originDigest: state.originDigest, practices: state.practices.map((item) => ({...item})),
      arena: copyArena(state.arena),
    };
    const fingerprint = JSON.stringify(selected);
    if (fingerprint === lastSent || projectionSequence === Number.MAX_SAFE_INTEGER) return false;
    const projection = Object.freeze({
      version: DESKTOP_PROJECTION_VERSION, host: DESKTOP_HOST_NAME, sessionId: bootstrap!.sessionId,
      sequence: projectionSequence + 1, kind: "journey-projection", ...selected,
    }) as DesktopJourneyProjection;
    if (new TextEncoder().encode(JSON.stringify(projection)).length > 32_768) return false;
    projectionSequence += 1;
    try {
      transport.postMessage(projection);
      lastSent = fingerprint;
      return true;
    } catch {
      // A closed host never prevents the game from keeping its own local state.
      return false;
    }
  }

  function changedVisibility(previous: boolean): void {
    if (previous !== visible()) listener?.(visible());
    emit();
  }

  const api = Object.freeze({
    performArenaAction(message: unknown): boolean {
      if (disposed || !visible() || !arenaListener || state.readiness !== "ready" || !state.arena ||
          !exactRecord(message, ["version", "host", "sessionId", "commandId", "expectedRevision", "actionId", "visibilitySequence"]) ||
          message.version !== 1 || message.host !== DESKTOP_HOST_NAME || message.sessionId !== bootstrap.sessionId ||
          !Number.isSafeInteger(message.visibilitySequence) || message.visibilitySequence !== visibilitySequence ||
          typeof message.commandId !== "string" || !uuidPattern.test(message.commandId) || usedCommandIDs.has(message.commandId.toLowerCase()) ||
          usedCommandIDs.size >= 2048 || message.expectedRevision !== state.arena.revision ||
          typeof message.actionId !== "string" || !state.arena.actions.some((action) => action.id === message.actionId)) return false;
      usedCommandIDs.add(message.commandId.toLowerCase());
      try { return arenaListener(message.actionId, state.arena.revision); } catch { return false; }
      finally { emit(); }
    },
    setAppearance(message: unknown): boolean {
      if (disposed || !exactRecord(message, ["version", "host", "sessionId", "sequence", "id", "label", "png", "reduceMotion"]) ||
          message.version !== 1 || message.host !== DESKTOP_HOST_NAME || message.sessionId !== bootstrap.sessionId ||
          !Number.isSafeInteger(message.sequence) || (message.sequence as number) <= appearanceSequence ||
          typeof message.id !== "string" || !message.id.length || message.id.length > 100 ||
          typeof message.label !== "string" || !message.label.length || message.label.length > 80 ||
          typeof message.reduceMotion !== "boolean" || typeof message.png !== "string" || message.png.length > 2_000_000 ||
          !/^data:image\/png;base64,iVBORw0KGgo[A-Za-z0-9+/=]+$/.test(message.png)) return false;
      appearanceSequence = message.sequence as number;
      appearance = Object.freeze({id: message.id, label: message.label, png: message.png, reduceMotion: message.reduceMotion});
      appearanceListener?.(appearance);
      return true;
    },
    setVisibility(message: unknown): boolean {
      if (disposed || !isVisibilityMessage(message, bootstrap.sessionId) || message.sequence <= visibilitySequence) return false;
      visibilitySequence = message.sequence;
      const previous = visible();
      hostVisible = message.visible;
      changedVisibility(previous);
      return true;
    },
  });
  environment.__ARCHI_DESKTOP_HOST__ = api;
  emit();
  return {
    get visible() { return visible(); },
    publish(next): boolean {
      try {
        if (disposed || !validState(next) || (state.readiness === "ready" && next.readiness !== "ready")) return false;
        const copied = { ...next, practices: next.practices.map((item) => ({ ...item })), arena: copyArena(next.arena) };
        // Reject an oversized publication before replacing the last admitted projection.
        const bounded = { version: DESKTOP_PROJECTION_VERSION, host: DESKTOP_HOST_NAME, sessionId: bootstrap.sessionId,
          sequence: Number.MAX_SAFE_INTEGER, kind: "journey-projection", visible: false,
          readiness: copied.readiness, storage: copied.storage, mode: copied.mode, journeyId: copied.journeyId,
          revision: copied.revision, eventCount: copied.eventCount, originDigest: copied.originDigest,
          practices: copied.practices, arena: copied.arena };
        if (new TextEncoder().encode(JSON.stringify(bounded)).length > 32_768) return false;
        state = copied;
      } catch { return false; }
      return emit();
    },
    onVisibilityChange(next): void {
      if (disposed) return;
      listener = next;
      next(visible());
    },
    onArenaAction(next): void { if (!disposed) arenaListener = next; },
    onAppearanceChange(next): void {
      if (disposed) return;
      appearanceListener = next;
      if (appearance) next(appearance);
    },
    setDocumentVisibility(next): void {
      if (disposed || typeof next !== "boolean") return;
      const previous = visible();
      documentVisible = next;
      changedVisibility(previous);
    },
    dispose(): void {
      disposed = true;
      listener = null;
      appearanceListener = null;
      arenaListener = null;
      if (environment.__ARCHI_DESKTOP_HOST__ === api) delete environment.__ARCHI_DESKTOP_HOST__;
    },
  };
}

/** Keeps download URLs alive through a native save panel, with a bounded lifetime and count. */
export function createDownloadLeasePool(environment: {
  revoke(url: string): void;
  later(callback: () => void, milliseconds: number): number;
  cancel(timer: number): void;
}, lifetime = 5 * 60_000, maximum = 8): { retain(url: string): void; dispose(): void } {
  const leases = new Map<string, number>();
  function release(url: string): void {
    const timer = leases.get(url);
    if (timer === undefined) return;
    leases.delete(url);
    environment.cancel(timer);
    environment.revoke(url);
  }
  return {
    retain(url): void {
      if (leases.has(url)) release(url);
      while (leases.size >= maximum) release(leases.keys().next().value!);
      leases.set(url, environment.later(() => release(url), lifetime));
    },
    dispose(): void { for (const url of [...leases.keys()]) release(url); },
  };
}
