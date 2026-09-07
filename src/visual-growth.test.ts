import { describe, expect, it } from "vitest";
import { CORE_PEARL_VISUAL, visualProfileForStage } from "./visual-growth";

describe("ARCHi visual growth profiles", () => {
  it("maps Hatchling and every admitted post-Hatchling stage to bounded presentation profiles", () => {
    expect(visualProfileForStage("Hatchling").tier).toBe("hatchling");
    for (const stage of ["Young", "Adolescent", "Mature", "Advanced"] as const) {
      expect(visualProfileForStage(stage).tier).toBe("young-foundation");
    }
  });

  it("makes Young legible in static silhouette, aura, and motion language", () => {
    const hatchling = visualProfileForStage("Hatchling");
    const young = visualProfileForStage("Young");

    expect(young.geometry.earAnchorY + young.geometry.earTipY).toBeLessThan(
      hatchling.geometry.earAnchorY + hatchling.geometry.earTipY,
    );
    expect(young.geometry.bodyRadiusY).toBeGreaterThan(hatchling.geometry.bodyRadiusY);
    expect(young.geometry.armX).toBeGreaterThan(hatchling.geometry.armX);
    expect(young.auraGeometry.outerGroundRing).toBe(true);
    expect(young.auraGeometry.orbitMotes).toBe(3);
    expect(young.motion).not.toBe(hatchling.motion);
    expect(young.movement.earSway).toBeGreaterThan(hatchling.movement.earSway);
    expect(young.movement.armSway).toBeGreaterThan(hatchling.movement.armSway);
    expect(young.movement.opposingEarPhase).toBeGreaterThan(hatchling.movement.opposingEarPhase);
    expect(young.movement.travelLean).toBeGreaterThan(hatchling.movement.travelLean);
  });

  it("shares one unchanged local Core Pearl contract across growth", () => {
    const hatchling = visualProfileForStage("Hatchling");
    const young = visualProfileForStage("Young");

    expect(hatchling.corePearl).toBe(CORE_PEARL_VISUAL);
    expect(young.corePearl).toBe(CORE_PEARL_VISUAL);
    expect(young.corePearl).toEqual({ x: 0, y: 29, innerRadius: 12, glowRadius: 33 });
  });

  it("adds seeded body specks as the aura develops", () => {
    const hatchling = visualProfileForStage("Hatchling");
    const young = visualProfileForStage("Young");
    expect(young.auraGeometry.speckCount).toBeGreaterThan(hatchling.auraGeometry.speckCount);
  });
});
