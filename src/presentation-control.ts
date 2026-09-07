import { PRESENCE_PHASES, type PresencePhase } from "./presence-sequence";

export const PRESENTATION_FORMS = PRESENCE_PHASES;
export const PRESENTATION_VIEWS = Object.freeze(["front", "three-quarter", "side", "back"] as const);
export const PRESENTATION_MOTIONS = Object.freeze(["idle", "focus", "play"] as const);

export type PresentationForm = PresencePhase;
export type PresentationView = (typeof PRESENTATION_VIEWS)[number];
export type PresentationMotion = (typeof PRESENTATION_MOTIONS)[number];

export interface PresentationState {
  readonly form: PresentationForm;
  readonly view: PresentationView;
  readonly motion: PresentationMotion;
  readonly scale: number;
}

export type PresentationAction =
  | { readonly type: "form"; readonly value: PresentationForm }
  | { readonly type: "view"; readonly value: PresentationView }
  | { readonly type: "motion"; readonly value: PresentationMotion }
  | { readonly type: "scale"; readonly value: "decrease" | "reset" | "increase" }
  | { readonly type: "return" };

export const PRESENTATION_SCALE = Object.freeze({
  minimum: 0.75,
  maximum: 1.3,
  step: 0.1,
  default: 1,
});

export const DEFAULT_PRESENTATION_STATE: PresentationState = Object.freeze({
  form: "proto",
  view: "front",
  motion: "idle",
  scale: PRESENTATION_SCALE.default,
});

function clampScale(value: number): number {
  const clamped = Math.max(PRESENTATION_SCALE.minimum, Math.min(PRESENTATION_SCALE.maximum, value));
  return Math.round(clamped * 100) / 100;
}

function frozenState(state: PresentationState): PresentationState {
  return Object.freeze({ ...state });
}

export function updatePresentationState(
  state: PresentationState,
  action: PresentationAction,
): PresentationState {
  switch (action.type) {
    case "form":
      return action.value === state.form ? state : frozenState({ ...state, form: action.value });
    case "view":
      return action.value === state.view ? state : frozenState({ ...state, view: action.value });
    case "motion":
      return action.value === state.motion ? state : frozenState({ ...state, motion: action.value });
    case "scale": {
      const nextScale =
        action.value === "reset"
          ? PRESENTATION_SCALE.default
          : state.scale + (action.value === "increase" ? PRESENTATION_SCALE.step : -PRESENTATION_SCALE.step);
      const scale = clampScale(nextScale);
      return scale === state.scale ? state : frozenState({ ...state, scale });
    }
    case "return":
      return state.form === "core" && state.motion === "idle"
        ? state
        : frozenState({ ...state, form: "core", motion: "idle" });
  }
  const unhandled: never = action;
  throw new Error(`Unhandled presentation action: ${JSON.stringify(unhandled)}`);
}

export function presentationLabel(state: PresentationState): string {
  const view = state.view === "three-quarter" ? "Three-quarter" : `${state.view[0].toUpperCase()}${state.view.slice(1)}`;
  return `${state.form === "proto" ? "Proto" : `${state.form[0].toUpperCase()}${state.form.slice(1)}`} · ${view} · ${
    state.motion[0].toUpperCase()
  }${state.motion.slice(1)} · ${Math.round(state.scale * 100)}%`;
}
