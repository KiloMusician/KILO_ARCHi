import { describe, expect, it } from "vitest";
import {
  DEFAULT_PRESENTATION_STATE,
  PRESENTATION_FORMS,
  PRESENTATION_MOTIONS,
  PRESENTATION_SCALE,
  PRESENTATION_VIEWS,
  presentationLabel,
  updatePresentationState,
} from "./presentation-control";

describe("ephemeral ARCHi presentation controls", () => {
  it("defines a frozen Proto/front/idle default without authority-bearing fields", () => {
    expect(DEFAULT_PRESENTATION_STATE).toEqual({ form: "proto", view: "front", motion: "idle", scale: 1 });
    expect(Object.isFrozen(DEFAULT_PRESENTATION_STATE)).toBe(true);
    expect(Object.keys(DEFAULT_PRESENTATION_STATE).sort()).toEqual(["form", "motion", "scale", "view"]);
  });

  it("exposes the exact bounded form, view, and motion vocabularies", () => {
    expect(PRESENTATION_FORMS).toEqual(["core", "field", "light", "reveal", "proto", "context"]);
    expect(PRESENTATION_VIEWS).toEqual(["front", "three-quarter", "side", "back"]);
    expect(PRESENTATION_MOTIONS).toEqual(["idle", "focus", "play"]);
    expect([PRESENTATION_FORMS, PRESENTATION_VIEWS, PRESENTATION_MOTIONS].every(Object.isFrozen)).toBe(true);
  });

  it("updates one presentation dimension without mutating the prior state", () => {
    const next = updatePresentationState(DEFAULT_PRESENTATION_STATE, { type: "view", value: "side" });
    expect(next).toEqual({ ...DEFAULT_PRESENTATION_STATE, view: "side" });
    expect(next).not.toBe(DEFAULT_PRESENTATION_STATE);
    expect(Object.isFrozen(next)).toBe(true);
    expect(DEFAULT_PRESENTATION_STATE.view).toBe("front");
  });

  it("clamps scale changes and resets to the canonical presentation scale", () => {
    let state = DEFAULT_PRESENTATION_STATE;
    for (let index = 0; index < 20; index += 1) {
      state = updatePresentationState(state, { type: "scale", value: "increase" });
    }
    expect(state.scale).toBe(PRESENTATION_SCALE.maximum);
    for (let index = 0; index < 20; index += 1) {
      state = updatePresentationState(state, { type: "scale", value: "decrease" });
    }
    expect(state.scale).toBe(PRESENTATION_SCALE.minimum);
    expect(updatePresentationState(state, { type: "scale", value: "reset" }).scale).toBe(1);
  });

  it("returns presentation to the Core without rewriting view or scale", () => {
    const active = { form: "context", view: "back", motion: "play", scale: 1.2 } as const;
    expect(updatePresentationState(active, { type: "return" })).toEqual({
      form: "core",
      view: "back",
      motion: "idle",
      scale: 1.2,
    });
  });

  it("produces a concise accessible state label", () => {
    expect(presentationLabel({ form: "proto", view: "three-quarter", motion: "focus", scale: 1.2 })).toBe(
      "Proto · Three-quarter · Focus · 120%",
    );
    expect(presentationLabel({ form: "context", view: "back", motion: "idle", scale: 1 })).toBe(
      "Context · Back · Idle · 100%",
    );
  });
});
