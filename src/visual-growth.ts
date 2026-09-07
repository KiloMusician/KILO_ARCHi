import type { GrowthStageName } from "./model";

export type GrowthVisualTier = "hatchling" | "young-foundation";

export interface GrowthVisualProfile {
  readonly tier: GrowthVisualTier;
  readonly silhouette: "round-sprout" | "rising-leaf";
  readonly motion: "whole-body-breath" | "coordinated-leaf-sway";
  readonly aura: "single-bloom" | "double-orbit";
  readonly geometry: {
    readonly earAnchorX: number;
    readonly earAnchorY: number;
    readonly earTipY: number;
    readonly earWidth: number;
    readonly earRotation: number;
    readonly headY: number;
    readonly headRadiusX: number;
    readonly headRadiusY: number;
    readonly bodyY: number;
    readonly bodyRadiusX: number;
    readonly bodyRadiusY: number;
    readonly armX: number;
    readonly armY: number;
    readonly armRadiusX: number;
    readonly armRadiusY: number;
    readonly armRotation: number;
    readonly footX: number;
    readonly footY: number;
    readonly footRadiusX: number;
    readonly footRadiusY: number;
    readonly eyeX: number;
  };
  readonly movement: {
    readonly bobRate: number;
    readonly habitatLift: number;
    readonly fieldLift: number;
    readonly earSway: number;
    readonly earSwayRate: number;
    readonly opposingEarPhase: number;
    readonly armSway: number;
    readonly idleLean: number;
    readonly travelLean: number;
    readonly corePulse: number;
  };
  readonly auraGeometry: {
    readonly radius: number;
    readonly baseStrength: number;
    readonly groundRadiusX: number;
    readonly groundRadiusY: number;
    readonly outerGroundRing: boolean;
    readonly orbitRadiusX: number;
    readonly orbitRadiusY: number;
    readonly orbitMotes: number;
    readonly speckCount: number;
  };
  readonly corePearl: typeof CORE_PEARL_VISUAL;
}

export const CORE_PEARL_VISUAL = Object.freeze({
  x: 0,
  y: 29,
  innerRadius: 12,
  glowRadius: 33,
});

const HATCHLING_VISUAL: GrowthVisualProfile = Object.freeze({
  tier: "hatchling",
  silhouette: "round-sprout",
  motion: "whole-body-breath",
  aura: "single-bloom",
  geometry: Object.freeze({
    earAnchorX: 25,
    earAnchorY: -54,
    earTipY: -40,
    earWidth: 25,
    earRotation: 0.42,
    headY: -20,
    headRadiusX: 56,
    headRadiusY: 48,
    bodyY: 29,
    bodyRadiusX: 40,
    bodyRadiusY: 45,
    armX: 40,
    armY: 29,
    armRadiusX: 10,
    armRadiusY: 22,
    armRotation: 0.24,
    footX: 18,
    footY: 69,
    footRadiusX: 16,
    footRadiusY: 10,
    eyeX: 19,
  }),
  movement: Object.freeze({
    bobRate: 0.86,
    habitatLift: 0.68,
    fieldLift: 1.8,
    earSway: 0.018,
    earSwayRate: 0.84,
    opposingEarPhase: 0,
    armSway: 0.018,
    idleLean: 0,
    travelLean: 0,
    corePulse: 0.045,
  }),
  auraGeometry: Object.freeze({
    radius: 104,
    baseStrength: 0.13,
    groundRadiusX: 58,
    groundRadiusY: 15,
    outerGroundRing: false,
    orbitRadiusX: 0,
    orbitRadiusY: 0,
    orbitMotes: 0,
    speckCount: 14,
  }),
  corePearl: CORE_PEARL_VISUAL,
});

const YOUNG_VISUAL: GrowthVisualProfile = Object.freeze({
  tier: "young-foundation",
  silhouette: "rising-leaf",
  motion: "coordinated-leaf-sway",
  aura: "double-orbit",
  geometry: Object.freeze({
    earAnchorX: 28,
    earAnchorY: -64,
    earTipY: -56,
    earWidth: 30,
    earRotation: 0.36,
    headY: -28,
    headRadiusX: 55,
    headRadiusY: 47,
    bodyY: 27,
    bodyRadiusX: 45,
    bodyRadiusY: 57,
    armX: 47,
    armY: 25,
    armRadiusX: 13,
    armRadiusY: 31,
    armRotation: 0.32,
    footX: 22,
    footY: 76,
    footRadiusX: 18,
    footRadiusY: 12,
    eyeX: 20,
  }),
  movement: Object.freeze({
    bobRate: 1,
    habitatLift: 1,
    fieldLift: 2.5,
    earSway: 0.038,
    earSwayRate: 1.04,
    opposingEarPhase: 0.72,
    armSway: 0.03,
    idleLean: 0.012,
    travelLean: 0.055,
    corePulse: 0.06,
  }),
  auraGeometry: Object.freeze({
    radius: 124,
    baseStrength: 0.17,
    groundRadiusX: 68,
    groundRadiusY: 18,
    outerGroundRing: true,
    orbitRadiusX: 78,
    orbitRadiusY: 55,
    orbitMotes: 3,
    speckCount: 24,
  }),
  corePearl: CORE_PEARL_VISUAL,
});

export function visualProfileForStage(stageName: GrowthStageName): GrowthVisualProfile {
  switch (stageName) {
    case "Hatchling":
      return HATCHLING_VISUAL;
    case "Young":
    case "Adolescent":
    case "Mature":
    case "Advanced":
      return YOUNG_VISUAL;
  }
  const unhandledStage: never = stageName;
  throw new Error(`Unhandled ARCHi growth stage: ${String(unhandledStage)}`);
}
