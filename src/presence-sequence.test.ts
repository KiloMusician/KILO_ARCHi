import { describe, expect, it } from "vitest";
import {
  PRESENCE_PHASES,
  PRESENCE_STOPS,
  PRESENCE_TRAVEL_SECONDS,
  advancePresenceSequence,
  createPresenceSequence,
  positionForPresencePhase,
  presenceMix,
  presencePhaseForPosition,
  retargetPresenceSequence,
} from "./presence-sequence";

describe("ARCHi presentation-only presence sequence", () => {
  it("defines six frozen phases on one normalized position", () => {
    expect(PRESENCE_PHASES).toEqual(["core", "field", "light", "reveal", "proto", "context"]);
    expect(PRESENCE_STOPS).toEqual({
      core: 0,
      field: 0.2,
      light: 0.42,
      reveal: 0.58,
      proto: 0.74,
      context: 1,
    });
    expect(Object.isFrozen(PRESENCE_PHASES)).toBe(true);
    expect(Object.isFrozen(PRESENCE_STOPS)).toBe(true);
  });

  it("maps named phases to positions and positions back to the nearest phase", () => {
    for (const phase of PRESENCE_PHASES) {
      expect(presencePhaseForPosition(positionForPresencePhase(phase))).toBe(phase);
    }

    expect(presencePhaseForPosition(-1)).toBe("core");
    expect(presencePhaseForPosition(0.51)).toBe("reveal");
    expect(presencePhaseForPosition(2)).toBe("context");
  });

  it("mixes only adjacent phases with bounded weights summing to one", () => {
    for (const position of [-1, 0, 0.1, 0.2, 0.34, 0.5, 0.58, 0.7, 0.87, 1, 2]) {
      const mix = presenceMix(position);
      const nonZeroPhases = PRESENCE_PHASES.filter((phase) => mix.weights[phase] > 0);
      const weightTotal = PRESENCE_PHASES.reduce((total, phase) => total + mix.weights[phase], 0);

      expect(weightTotal).toBeCloseTo(1, 12);
      expect(PRESENCE_PHASES.every((phase) => mix.weights[phase] >= 0 && mix.weights[phase] <= 1)).toBe(true);
      expect(nonZeroPhases.length).toBeLessThanOrEqual(2);
      if (nonZeroPhases.length === 2) {
        expect(PRESENCE_PHASES.indexOf(nonZeroPhases[1]) - PRESENCE_PHASES.indexOf(nonZeroPhases[0])).toBe(1);
      }
      expect(Object.isFrozen(mix)).toBe(true);
      expect(Object.isFrozen(mix.weights)).toBe(true);
    }
  });

  it("derives bounded field, petal, body, and context reveal amounts", () => {
    expect(presenceMix(PRESENCE_STOPS.core)).toMatchObject({
      fieldAmount: 0,
      petalAmount: 0,
      bodyReveal: 0,
      contextAmount: 0,
    });
    const revealMix = presenceMix(PRESENCE_STOPS.reveal);
    expect(revealMix).toMatchObject({ fieldAmount: 1, petalAmount: 1, contextAmount: 0 });
    expect(revealMix.bodyReveal).toBeCloseTo(0.5, 12);
    expect(presenceMix(PRESENCE_STOPS.context)).toMatchObject({
      fieldAmount: 1,
      petalAmount: 1,
      bodyReveal: 1,
      contextAmount: 1,
    });

    for (const position of [Number.NaN, -1, 0.3, 0.6, 0.9, 2]) {
      const { fieldAmount, petalAmount, bodyReveal, contextAmount } = presenceMix(position);
      expect([fieldAmount, petalAmount, bodyReveal, contextAmount].every((amount) => amount >= 0 && amount <= 1)).toBe(
        true,
      );
    }
  });

  it("travels forward and back deterministically from the current position", () => {
    const reveal = retargetPresenceSequence(createPresenceSequence("core"), "context");
    expect(reveal).toMatchObject({
      position: 0,
      startPosition: 0,
      targetPosition: 1,
      elapsedSeconds: 0,
      durationSeconds: PRESENCE_TRAVEL_SECONDS,
      direction: "reveal",
    });

    const halfwayOut = advancePresenceSequence(reveal, PRESENCE_TRAVEL_SECONDS / 2);
    expect(halfwayOut.position).toBeCloseTo(0.5, 12);

    const returning = retargetPresenceSequence(halfwayOut, "core");
    expect(returning).toMatchObject({
      position: halfwayOut.position,
      startPosition: halfwayOut.position,
      targetPosition: 0,
      direction: "return",
    });
    expect(returning.durationSeconds).toBeCloseTo(PRESENCE_TRAVEL_SECONDS / 2, 12);

    const halfwayBack = advancePresenceSequence(returning, PRESENCE_TRAVEL_SECONDS / 4);
    expect(halfwayBack.position).toBeCloseTo(0.25, 12);
    const settled = advancePresenceSequence(halfwayBack, PRESENCE_TRAVEL_SECONDS);
    expect(settled).toMatchObject({ position: 0, targetPosition: 0, direction: "settled" });
  });

  it("ignores invalid deltas, clamps overshoot, and snaps for reduced motion", () => {
    const moving = retargetPresenceSequence(createPresenceSequence("field"), "context");
    expect(advancePresenceSequence(moving, -1)).toBe(moving);
    expect(advancePresenceSequence(moving, Number.NaN)).toBe(moving);
    expect(advancePresenceSequence(moving, Number.POSITIVE_INFINITY)).toBe(moving);

    const completed = advancePresenceSequence(moving, 100);
    expect(completed).toMatchObject({ position: 1, targetPosition: 1, direction: "settled" });
    expect(completed.elapsedSeconds).toBe(completed.durationSeconds);

    const snapped = retargetPresenceSequence(moving, "core", true);
    expect(snapped).toEqual({
      position: 0,
      startPosition: 0,
      targetPosition: 0,
      elapsedSeconds: 0,
      durationSeconds: 0,
      direction: "settled",
    });
  });

  it("contains presentation data only", () => {
    const state = retargetPresenceSequence(createPresenceSequence("core"), "context");
    const mix = presenceMix(state.position);
    const forbidden = ["identity", "journey", "authority", "persistence", "role", "permission"];

    expect(Object.keys(state).some((key) => forbidden.includes(key.toLowerCase()))).toBe(false);
    expect(Object.keys(mix).some((key) => forbidden.includes(key.toLowerCase()))).toBe(false);
  });
});
