export const PRESENCE_PHASES = Object.freeze([
  "core",
  "field",
  "light",
  "reveal",
  "proto",
  "context",
] as const);

export type PresencePhase = (typeof PRESENCE_PHASES)[number];
export type PresenceDirection = "reveal" | "return" | "settled";

export const PRESENCE_STOPS: Readonly<Record<PresencePhase, number>> = Object.freeze({
  core: 0,
  field: 0.2,
  light: 0.42,
  reveal: 0.58,
  proto: 0.74,
  context: 1,
});

export const PRESENCE_TRAVEL_SECONDS = 1.6;

export interface PresenceSequenceState {
  readonly position: number;
  readonly startPosition: number;
  readonly targetPosition: number;
  readonly elapsedSeconds: number;
  readonly durationSeconds: number;
  readonly direction: PresenceDirection;
}

export interface PresenceMix {
  readonly position: number;
  readonly phase: PresencePhase;
  readonly fromPhase: PresencePhase;
  readonly toPhase: PresencePhase;
  readonly fromWeight: number;
  readonly toWeight: number;
  readonly weights: Readonly<Record<PresencePhase, number>>;
  readonly bodyReveal: number;
  readonly contextAmount: number;
  readonly petalAmount: number;
  readonly fieldAmount: number;
}

function clampUnit(value: number): number {
  if (Number.isNaN(value)) return 0;
  return Math.max(0, Math.min(1, value));
}

function amountBetween(position: number, start: number, end: number): number {
  return clampUnit((position - start) / (end - start));
}

function frozenSequenceState(state: PresenceSequenceState): PresenceSequenceState {
  return Object.freeze({ ...state });
}

function emptyWeights(): Record<PresencePhase, number> {
  return {
    core: 0,
    field: 0,
    light: 0,
    reveal: 0,
    proto: 0,
    context: 0,
  };
}

function surroundingPhases(position: number): readonly [PresencePhase, PresencePhase, number] {
  for (let index = 0; index < PRESENCE_PHASES.length - 1; index += 1) {
    const fromPhase = PRESENCE_PHASES[index];
    const toPhase = PRESENCE_PHASES[index + 1];
    const fromPosition = PRESENCE_STOPS[fromPhase];
    const toPosition = PRESENCE_STOPS[toPhase];
    if (position <= toPosition) {
      return [fromPhase, toPhase, amountBetween(position, fromPosition, toPosition)];
    }
  }
  return ["proto", "context", 1];
}

export function positionForPresencePhase(phase: PresencePhase): number {
  return PRESENCE_STOPS[phase];
}

export function presencePhaseForPosition(position: number): PresencePhase {
  const normalizedPosition = clampUnit(position);
  const [fromPhase, toPhase, progress] = surroundingPhases(normalizedPosition);
  return progress < 0.5 ? fromPhase : toPhase;
}

export function presenceMix(position: number): PresenceMix {
  const normalizedPosition = clampUnit(position);
  const [fromPhase, toPhase, progress] = surroundingPhases(normalizedPosition);
  const weights = emptyWeights();
  weights[fromPhase] = 1 - progress;
  weights[toPhase] = progress;

  return Object.freeze({
    position: normalizedPosition,
    phase: progress < 0.5 ? fromPhase : toPhase,
    fromPhase,
    toPhase,
    fromWeight: weights[fromPhase],
    toWeight: weights[toPhase],
    weights: Object.freeze(weights),
    fieldAmount: amountBetween(normalizedPosition, PRESENCE_STOPS.core, PRESENCE_STOPS.field),
    petalAmount: amountBetween(normalizedPosition, PRESENCE_STOPS.field, PRESENCE_STOPS.light),
    bodyReveal: amountBetween(normalizedPosition, PRESENCE_STOPS.light, PRESENCE_STOPS.proto),
    contextAmount: amountBetween(normalizedPosition, PRESENCE_STOPS.proto, PRESENCE_STOPS.context),
  });
}

export function createPresenceSequence(initialPhase: PresencePhase): PresenceSequenceState {
  const position = positionForPresencePhase(initialPhase);
  return frozenSequenceState({
    position,
    startPosition: position,
    targetPosition: position,
    elapsedSeconds: 0,
    durationSeconds: 0,
    direction: "settled",
  });
}

export function retargetPresenceSequence(
  state: PresenceSequenceState,
  targetPhase: PresencePhase,
  reducedMotion = false,
): PresenceSequenceState {
  const position = clampUnit(state.position);
  const targetPosition = positionForPresencePhase(targetPhase);

  if (reducedMotion || position === targetPosition) {
    return frozenSequenceState({
      position: targetPosition,
      startPosition: targetPosition,
      targetPosition,
      elapsedSeconds: 0,
      durationSeconds: 0,
      direction: "settled",
    });
  }

  return frozenSequenceState({
    position,
    startPosition: position,
    targetPosition,
    elapsedSeconds: 0,
    durationSeconds: Math.abs(targetPosition - position) * PRESENCE_TRAVEL_SECONDS,
    direction: targetPosition > position ? "reveal" : "return",
  });
}

export function advancePresenceSequence(
  state: PresenceSequenceState,
  deltaSeconds: number,
): PresenceSequenceState {
  if (state.direction === "settled") return state;

  const safeDelta = Number.isFinite(deltaSeconds) ? Math.max(0, deltaSeconds) : 0;
  if (safeDelta === 0) return state;

  const durationSeconds = Math.max(0, state.durationSeconds);
  const elapsedSeconds = Math.min(durationSeconds, Math.max(0, state.elapsedSeconds) + safeDelta);
  const progress = durationSeconds === 0 ? 1 : elapsedSeconds / durationSeconds;
  const position = clampUnit(
    state.startPosition + (state.targetPosition - state.startPosition) * progress,
  );

  return frozenSequenceState({
    ...state,
    position: progress === 1 ? clampUnit(state.targetPosition) : position,
    elapsedSeconds,
    direction: progress === 1 ? "settled" : state.direction,
  });
}
