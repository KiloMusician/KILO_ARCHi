import { describe, expect, it } from "vitest";
import { PRESENTATION_VIEWS } from "./presentation-control";
import {
  PROTO_RIG_APPENDAGE_IDS,
  PROTO_VISUAL_RIG_VERSION,
  protoRigAppendage,
  protoVisualRigForView,
} from "./proto-visual-rig";
import { CORE_PEARL_VISUAL, visualProfileForStage } from "./visual-growth";

describe("Canonical Proto Visual Rig v1", () => {
  const profile = visualProfileForStage("Young");

  it("resolves one deeply frozen contract for every admitted view", () => {
    for (const view of PRESENTATION_VIEWS) {
      const rig = protoVisualRigForView(view, profile);
      expect(rig.schemaVersion).toBe(PROTO_VISUAL_RIG_VERSION);
      expect(rig.view).toBe(view);
      expect(Object.isFrozen(rig)).toBe(true);
      expect(Object.isFrozen(rig.body)).toBe(true);
      expect(Object.isFrozen(rig.head)).toBe(true);
      expect(Object.isFrozen(rig.appendages)).toBe(true);
      expect(rig.appendages.every(Object.isFrozen)).toBe(true);
      expect(Object.isFrozen(rig.face)).toBe(true);
      expect(Object.isFrozen(rig.face.eyes)).toBe(true);
      expect(Object.isFrozen(rig.core)).toBe(true);
      expect(Object.isFrozen(rig.occlusion)).toBe(true);
      expect(Object.isFrozen(rig.depthOrder)).toBe(true);
      expect(protoVisualRigForView(view, profile)).toBe(rig);
      expect(rig.appendages.map((appendage) => appendage.id).sort()).toEqual(
        [...PROTO_RIG_APPENDAGE_IDS].sort(),
      );
      const visibleLayers = [
        ...rig.appendages.filter((appendage) => appendage.visible).map((appendage) => appendage.id),
        "body",
        "head",
        ...(rig.face.visible ? ["face"] : []),
        ...(rig.dorsalSeam.visible ? ["dorsal-seam"] : []),
        "core",
      ];
      expect(new Set(rig.depthOrder).size).toBe(rig.depthOrder.length);
      expect([...rig.depthOrder].sort()).toEqual(visibleLayers.sort());
    }
  });

  it("preserves the exact shared Core Pearl object through every view", () => {
    for (const view of PRESENTATION_VIEWS) {
      expect(protoVisualRigForView(view, profile).core.visual).toBe(CORE_PEARL_VISUAL);
    }
  });

  it("makes the front rig bilateral and fully legible", () => {
    const rig = protoVisualRigForView("front", profile);
    expect(rig.silhouette).toBe("bilateral-open");
    expect(rig.nearSide).toBeNull();
    expect(rig.face.kind).toBe("full");
    expect(rig.face.eyes.map((eye) => eye.visible)).toEqual([true, true]);
    expect(rig.farSide).toBeNull();
    expect(rig.occlusion.hiddenAppendages).toEqual([]);
    expect(rig.occlusion.translucentAppendages).toEqual([]);
    expect(protoRigAppendage(rig, "ear", "left").x).toBe(
      -protoRigAppendage(rig, "ear", "right").x,
    );
  });

  it("gives three-quarter view explicit far and near depth", () => {
    const rig = protoVisualRigForView("three-quarter", profile);
    const farArm = protoRigAppendage(rig, "arm", "left");
    const nearArm = protoRigAppendage(rig, "arm", "right");
    expect(rig.silhouette).toBe("turned-volume");
    expect(rig.nearSide).toBe("right");
    expect(rig.farSide).toBe("left");
    expect(farArm.visible).toBe(true);
    expect(farArm.opacity).toBeLessThan(nearArm.opacity);
    expect(farArm.depth).toBeLessThan(rig.body.depth);
    expect(nearArm.depth).toBeGreaterThan(rig.body.depth);
    expect(rig.face.eyes[0].scaleX).toBeLessThan(rig.face.eyes[1].scaleX);
  });

  it("encodes real profile occlusion instead of whole-body squash", () => {
    const rig = protoVisualRigForView("side", profile);
    expect(rig.silhouette).toBe("profile-occluded");
    expect(rig.nearSide).toBe("right");
    expect(rig.farSide).toBe("left");
    expect(rig.face.kind).toBe("profile");
    expect(rig.face.eyes.map((eye) => eye.visible)).toEqual([false, true]);
    expect(rig.occlusion.hiddenAppendages).toEqual(["arm-left", "foot-left"]);
    expect(protoRigAppendage(rig, "arm", "left").visible).toBe(false);
    expect(protoRigAppendage(rig, "foot", "left").visible).toBe(false);
    expect(protoRigAppendage(rig, "ear", "left").opacity).toBeLessThan(0.3);
    expect(rig.head.radiusX).not.toBe(profile.geometry.headRadiusX);
    expect(rig.head.radiusY).toBe(profile.geometry.headRadiusY);
  });

  it("makes the back silhouette structurally face-free", () => {
    const rig = protoVisualRigForView("back", profile);
    expect(rig.silhouette).toBe("face-free-back");
    expect(rig.face.kind).toBe("none");
    expect(rig.face.visible).toBe(false);
    expect(rig.face.eyes.every((eye) => !eye.visible)).toBe(true);
    expect(rig.depthOrder).not.toContain("face");
    expect(rig.dorsalSeam.visible).toBe(true);
    expect(rig.dorsalSeam.opacity).toBeGreaterThan(0.5);
    expect(rig.core.occludedByShell).toBe(true);
    expect(rig.core.shellTransmission).toBeLessThan(0.5);
    expect(rig.core.shellTransmission).toBeLessThan(
      protoVisualRigForView("side", profile).core.shellTransmission,
    );
  });

  it("keeps the rig deterministic and growth-aware without mutating profiles", () => {
    for (const view of PRESENTATION_VIEWS) {
      expect(protoVisualRigForView(view, profile)).toEqual(protoVisualRigForView(view, profile));
    }
    const hatchling = protoVisualRigForView("side", visualProfileForStage("Hatchling"));
    const young = protoVisualRigForView("side", profile);
    expect(hatchling.body.radiusY).not.toBe(young.body.radiusY);
    expect(hatchling.core.visual).toBe(young.core.visual);
    expect(Object.isFrozen(profile)).toBe(true);
  });

  it("contains no product-authority, persistence, network, battle, or identity fields", () => {
    const forbidden = new Set([
      "journey",
      "identity",
      "permission",
      "permissions",
      "authority",
      "persistence",
      "network",
      "storage",
      "battle",
      "power",
    ]);
    const inspect = (value: unknown): void => {
      if (!value || typeof value !== "object") return;
      for (const [key, child] of Object.entries(value)) {
        expect(forbidden.has(key.toLowerCase())).toBe(false);
        inspect(child);
      }
    };
    for (const stage of ["Hatchling", "Young"] as const) {
      for (const view of PRESENTATION_VIEWS) inspect(protoVisualRigForView(view, visualProfileForStage(stage)));
    }
  });

  it("rejects a runtime view outside the frozen contract", () => {
    expect(() => protoVisualRigForView("overhead" as never, profile)).toThrow("Unsupported Proto view");
  });
});
