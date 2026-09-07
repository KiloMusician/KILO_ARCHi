import { describe, expect, it } from "vitest";
import {
  ENCOUNTER_COMPOSITION_VERSION,
  battleEncounterComposition,
  encounterViewportClass,
  habitatEncounterComposition,
} from "./encounter-composition";

describe("Encounter Composition v1", () => {
  it("classifies the supported responsive surfaces deterministically", () => {
    expect(encounterViewportClass(1280, 720)).toBe("wide");
    expect(encounterViewportClass(1024, 640)).toBe("standard");
    expect(encounterViewportClass(768, 900)).toBe("compact");
    expect(encounterViewportClass(698, 837)).toBe("compact");
    expect(encounterViewportClass(390, 844)).toBe("portrait");
    expect(encounterViewportClass(390, 500)).toBe("portrait");
    expect(encounterViewportClass(500, 390)).toBe("short");
    expect(encounterViewportClass(844, 390)).toBe("short");
  });

  it("keeps Habitat on one enlarged, frozen composition contract", () => {
    const composition = habitatEncounterComposition(1280, 720);
    expect(composition.schemaVersion).toBe(ENCOUNTER_COMPOSITION_VERSION);
    expect(composition.kind).toBe("habitat");
    expect(composition.viewportClass).toBe("wide");
    expect(composition.anchor.x).toBeCloseTo(921.6);
    expect(composition.anchor.y).toBeCloseTo(331.2);
    expect(composition.scaleMultiplier).toBeGreaterThan(1);
    expect(Object.isFrozen(composition)).toBe(true);
    expect(Object.isFrozen(composition.anchor)).toBe(true);
    expect(habitatEncounterComposition(1280, 720)).toEqual(composition);
  });

  it("mirrors equal formations and keeps reserves subordinate to the active fighter", () => {
    const composition = battleEncounterComposition(1280, 720, { one: 3, two: 3 });
    const one = composition.teams.one;
    const two = composition.teams.two;
    expect(one.active.x + two.active.x).toBeCloseTo(1280);
    expect(one.active.y).toBe(two.active.y);
    expect(one.active.facing).toBe(1);
    expect(two.active.facing).toBe(-1);
    expect(one.reserves).toHaveLength(2);
    expect(two.reserves).toHaveLength(2);
    expect(one.reserves.map((reserve) => reserve.x + two.reserves[reserve.slot - 1].x)).toEqual([
      1280,
      1280,
    ]);
    expect(one.reserves.every((reserve) => reserve.drawScale < one.active.drawScale)).toBe(true);
    expect(two.reserves.every((reserve) => reserve.drawScale < two.active.drawScale)).toBe(true);
    expect(Object.isFrozen(composition)).toBe(true);
    expect(Object.isFrozen(composition.teams)).toBe(true);
    expect(Object.isFrozen(one.reserves)).toBe(true);
  });

  it("renders solo versus formation as one primary fighter and two reserve projections", () => {
    const composition = battleEncounterComposition(1280, 720, { one: 1, two: 3 });
    expect(composition.teams.one.reserves).toEqual([]);
    expect(composition.teams.two.reserves.map((reserve) => reserve.slot)).toEqual([1, 2]);
    expect(composition.teams.one.active.drawScale).toBe(composition.teams.two.active.drawScale);
  });

  it("keeps primary and reserve anchors inside desktop, portrait, and short surfaces", () => {
    for (const [width, height] of [
      [1280, 720],
      [698, 837],
      [390, 844],
      [390, 500],
      [844, 390],
    ] as const) {
      const composition = battleEncounterComposition(width, height, { one: 3, two: 3 });
      for (const team of Object.values(composition.teams)) {
        for (const point of [team.active, team.ground, ...team.reserves]) {
          expect(point.x).toBeGreaterThan(0);
          expect(point.x).toBeLessThan(width);
          expect(point.y).toBeGreaterThan(0);
          expect(point.y).toBeLessThan(height);
        }
      }
    }
  });

  it("contains no Journey, battle-power, persistence, network, identity, or authority fields", () => {
    const forbidden = new Set([
      "journey",
      "integrity",
      "resonance",
      "concentration",
      "damage",
      "power",
      "storage",
      "persistence",
      "network",
      "identity",
      "authority",
    ]);
    const inspect = (value: unknown): void => {
      if (!value || typeof value !== "object") return;
      for (const [key, child] of Object.entries(value)) {
        expect(forbidden.has(key.toLowerCase())).toBe(false);
        inspect(child);
      }
    };
    inspect(habitatEncounterComposition(1280, 720));
    inspect(battleEncounterComposition(1280, 720, { one: 3, two: 1 }));
  });

  it("rejects invalid viewports and roster sizes", () => {
    expect(() => habitatEncounterComposition(0, 720)).toThrow("Viewport width");
    expect(() => encounterViewportClass(Number.NaN, 720)).toThrow("Viewport width");
    expect(() => battleEncounterComposition(1280, 720, { one: 0, two: 1 })).toThrow("Team one");
    expect(() => battleEncounterComposition(1280, 720, { one: 1, two: 4 })).toThrow("Team two");
  });
});
