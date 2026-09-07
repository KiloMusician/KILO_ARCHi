import type { PresentationView } from "./presentation-control";
import type { GrowthVisualProfile } from "./visual-growth";

export const PROTO_VISUAL_RIG_VERSION = "proto-visual-rig-v1" as const;

export type ProtoRigSide = "left" | "right";
export type ProtoRigAppendageKind = "ear" | "arm" | "foot";
export type ProtoRigAppendageId = `${ProtoRigAppendageKind}-${ProtoRigSide}`;
export type ProtoRigLayerId = ProtoRigAppendageId | "body" | "head" | "face" | "dorsal-seam" | "core";

export interface ProtoRigAppendage {
  readonly id: ProtoRigAppendageId;
  readonly kind: ProtoRigAppendageKind;
  readonly side: ProtoRigSide;
  readonly x: number;
  readonly y: number;
  readonly scaleX: number;
  readonly scaleY: number;
  readonly rotation: number;
  readonly opacity: number;
  readonly visible: boolean;
  readonly depth: number;
}

export interface ProtoRigVolume {
  readonly x: number;
  readonly y: number;
  readonly radiusX: number;
  readonly radiusY: number;
  readonly rotation: number;
  readonly depth: number;
}

export interface ProtoRigEye {
  readonly side: ProtoRigSide;
  readonly x: number;
  readonly y: number;
  readonly scaleX: number;
  readonly opacity: number;
  readonly visible: boolean;
}

export interface ProtoRigFace {
  readonly kind: "full" | "turned" | "profile" | "none";
  readonly visible: boolean;
  readonly centerX: number;
  readonly mouthX: number;
  readonly depth: number;
  readonly eyes: readonly [ProtoRigEye, ProtoRigEye];
}

export interface ProtoRigCore {
  readonly visual: GrowthVisualProfile["corePearl"];
  readonly shellTransmission: number;
  readonly occludedByShell: boolean;
  readonly depth: number;
}

export interface ProtoVisualRig {
  readonly schemaVersion: typeof PROTO_VISUAL_RIG_VERSION;
  readonly view: PresentationView;
  readonly silhouette: "bilateral-open" | "turned-volume" | "profile-occluded" | "face-free-back";
  readonly nearSide: ProtoRigSide | null;
  readonly farSide: ProtoRigSide | null;
  readonly body: ProtoRigVolume;
  readonly head: ProtoRigVolume;
  readonly appendages: readonly ProtoRigAppendage[];
  readonly face: ProtoRigFace;
  readonly core: ProtoRigCore;
  readonly dorsalSeam: {
    readonly visible: boolean;
    readonly opacity: number;
    readonly depth: number;
  };
  readonly occlusion: {
    readonly hiddenAppendages: readonly ProtoRigAppendageId[];
    readonly translucentAppendages: readonly ProtoRigAppendageId[];
  };
  readonly depthOrder: readonly ProtoRigLayerId[];
}

interface AppendagePose {
  readonly xFactor: number;
  readonly xOffset: number;
  readonly yOffset: number;
  readonly scaleX: number;
  readonly scaleY: number;
  readonly rotationOffset: number;
  readonly opacity: number;
  readonly visible: boolean;
  readonly depth: number;
}

interface ViewPreset {
  readonly silhouette: ProtoVisualRig["silhouette"];
  readonly nearSide: ProtoRigSide | null;
  readonly farSide: ProtoRigSide | null;
  readonly head: readonly [xOffset: number, yOffset: number, width: number, height: number, rotation: number];
  readonly body: readonly [xOffset: number, yOffset: number, width: number, height: number, rotation: number];
  readonly appendages: Readonly<Record<ProtoRigAppendageId, AppendagePose>>;
  readonly face: {
    readonly kind: ProtoRigFace["kind"];
    readonly centerX: number;
    readonly eyeXFactors: readonly [left: number, right: number];
    readonly eyeXOffsets: readonly [left: number, right: number];
    readonly eyeScaleX: readonly [left: number, right: number];
    readonly eyeOpacity: readonly [left: number, right: number];
    readonly eyeVisible: readonly [left: boolean, right: boolean];
  };
  readonly coreOpacity: number;
  readonly coreOccluded: boolean;
  readonly dorsalSeam: boolean;
}

const pose = (
  xFactor: number,
  xOffset: number,
  yOffset: number,
  scaleX: number,
  scaleY: number,
  rotationOffset: number,
  opacity: number,
  visible: boolean,
  depth: number,
): AppendagePose =>
  Object.freeze({ xFactor, xOffset, yOffset, scaleX, scaleY, rotationOffset, opacity, visible, depth });

const FRONT_APPENDAGES = Object.freeze({
  "ear-left": pose(1, 0, 0, 1, 1, 0, 1, true, 10),
  "ear-right": pose(1, 0, 0, 1, 1, 0, 1, true, 10),
  "arm-left": pose(1, 0, 0, 1, 1, 0, 1, true, 30),
  "arm-right": pose(1, 0, 0, 1, 1, 0, 1, true, 30),
  "foot-left": pose(1, 0, 0, 1, 1, 0, 1, true, 48),
  "foot-right": pose(1, 0, 0, 1, 1, 0, 1, true, 48),
}) satisfies Readonly<Record<ProtoRigAppendageId, AppendagePose>>;

const TURNED_APPENDAGES = Object.freeze({
  "ear-left": pose(0.72, 7, 4, 0.76, 0.9, -0.1, 0.5, true, 8),
  "ear-right": pose(0.96, 2, -1, 1.02, 1, 0.035, 1, true, 12),
  "arm-left": pose(0.6, 6, 3, 0.7, 0.86, -0.08, 0.42, true, 20),
  "arm-right": pose(0.96, 3, 0, 1, 1, 0.04, 1, true, 52),
  "foot-left": pose(0.58, 5, 1, 0.72, 0.88, -0.08, 0.5, true, 28),
  "foot-right": pose(0.88, 2, 0, 1, 1, 0.02, 1, true, 48),
}) satisfies Readonly<Record<ProtoRigAppendageId, AppendagePose>>;

const SIDE_APPENDAGES = Object.freeze({
  "ear-left": pose(0.2, 7, 6, 0.5, 0.82, -0.16, 0.26, true, 7),
  "ear-right": pose(0.72, 1, 0, 0.92, 1, 0.08, 1, true, 12),
  "arm-left": pose(0.1, 4, 4, 0.55, 0.8, -0.12, 0, false, 18),
  "arm-right": pose(0.72, 4, 0, 0.92, 1, 0.09, 1, true, 52),
  "foot-left": pose(0.16, 3, 2, 0.58, 0.82, -0.08, 0, false, 26),
  "foot-right": pose(0.48, 3, 0, 0.9, 1, 0.04, 1, true, 48),
}) satisfies Readonly<Record<ProtoRigAppendageId, AppendagePose>>;

const BACK_APPENDAGES = Object.freeze({
  "ear-left": pose(1, 0, 0, 1, 1, 0.035, 0.92, true, 10),
  "ear-right": pose(1, 0, 0, 1, 1, -0.035, 0.92, true, 10),
  "arm-left": pose(0.94, 1, 1, 0.92, 0.96, 0.03, 0.78, true, 24),
  "arm-right": pose(0.94, -1, 1, 0.92, 0.96, -0.03, 0.78, true, 24),
  "foot-left": pose(0.94, 0, 0, 0.96, 1, 0.03, 0.9, true, 48),
  "foot-right": pose(0.94, 0, 0, 0.96, 1, -0.03, 0.9, true, 48),
}) satisfies Readonly<Record<ProtoRigAppendageId, AppendagePose>>;

const VIEW_PRESETS: Readonly<Record<PresentationView, ViewPreset>> = Object.freeze({
  front: Object.freeze({
    silhouette: "bilateral-open",
    nearSide: null,
    farSide: null,
    head: [0, 0, 1, 1, 0] as const,
    body: [0, 0, 1, 1, 0] as const,
    appendages: FRONT_APPENDAGES,
    face: Object.freeze({
      kind: "full",
      centerX: 0,
      eyeXFactors: [1, 1] as const,
      eyeXOffsets: [0, 0] as const,
      eyeScaleX: [1, 1] as const,
      eyeOpacity: [1, 1] as const,
      eyeVisible: [true, true] as const,
    }),
    coreOpacity: 1,
    coreOccluded: false,
    dorsalSeam: false,
  }),
  "three-quarter": Object.freeze({
    silhouette: "turned-volume",
    nearSide: "right",
    farSide: "left",
    head: [4, 0, 0.94, 1, -0.018] as const,
    body: [1, 0, 0.9, 1, -0.012] as const,
    appendages: TURNED_APPENDAGES,
    face: Object.freeze({
      kind: "turned",
      centerX: 7,
      eyeXFactors: [0.72, 0.9] as const,
      eyeXOffsets: [6, 6] as const,
      eyeScaleX: [0.76, 1] as const,
      eyeOpacity: [0.58, 1] as const,
      eyeVisible: [true, true] as const,
    }),
    coreOpacity: 0.94,
    coreOccluded: false,
    dorsalSeam: false,
  }),
  side: Object.freeze({
    silhouette: "profile-occluded",
    nearSide: "right",
    farSide: "left",
    head: [7, 0, 0.76, 1, -0.025] as const,
    body: [1, 0, 0.68, 1, -0.016] as const,
    appendages: SIDE_APPENDAGES,
    face: Object.freeze({
      kind: "profile",
      centerX: 15,
      eyeXFactors: [0, 0.44] as const,
      eyeXOffsets: [0, 14] as const,
      eyeScaleX: [0, 0.86] as const,
      eyeOpacity: [0, 1] as const,
      eyeVisible: [false, true] as const,
    }),
    coreOpacity: 0.78,
    coreOccluded: true,
    dorsalSeam: false,
  }),
  back: Object.freeze({
    silhouette: "face-free-back",
    nearSide: null,
    farSide: null,
    head: [0, 0, 0.98, 1, 0] as const,
    body: [0, 0, 1, 1, 0] as const,
    appendages: BACK_APPENDAGES,
    face: Object.freeze({
      kind: "none",
      centerX: 0,
      eyeXFactors: [0, 0] as const,
      eyeXOffsets: [0, 0] as const,
      eyeScaleX: [0, 0] as const,
      eyeOpacity: [0, 0] as const,
      eyeVisible: [false, false] as const,
    }),
    coreOpacity: 0.18,
    coreOccluded: true,
    dorsalSeam: true,
  }),
});

export const PROTO_RIG_APPENDAGE_IDS = Object.freeze([
  "ear-left",
  "ear-right",
  "arm-left",
  "arm-right",
  "foot-left",
  "foot-right",
] as const satisfies readonly ProtoRigAppendageId[]);

export const PROTO_RIG_LAYER_IDS = Object.freeze([
  ...PROTO_RIG_APPENDAGE_IDS,
  "body",
  "head",
  "face",
  "dorsal-seam",
  "core",
] as const satisfies readonly ProtoRigLayerId[]);

const LAYER_RANK = new Map<ProtoRigLayerId, number>(
  PROTO_RIG_LAYER_IDS.map((id, index) => [id, index]),
);
const RIG_CACHE = new WeakMap<GrowthVisualProfile, Map<PresentationView, ProtoVisualRig>>();

function sideForId(id: ProtoRigAppendageId): ProtoRigSide {
  return id.endsWith("-left") ? "left" : "right";
}

function kindForId(id: ProtoRigAppendageId): ProtoRigAppendageKind {
  return id.split("-")[0] as ProtoRigAppendageKind;
}

function baseAppendagePosition(
  kind: ProtoRigAppendageKind,
  side: ProtoRigSide,
  profile: GrowthVisualProfile,
): { x: number; y: number; rotation: number } {
  const sign = side === "left" ? -1 : 1;
  switch (kind) {
    case "ear":
      return {
        x: sign * profile.geometry.earAnchorX,
        y: profile.geometry.earAnchorY,
        rotation: sign * profile.geometry.earRotation,
      };
    case "arm":
      return {
        x: sign * profile.geometry.armX,
        y: profile.geometry.armY,
        rotation: sign * profile.geometry.armRotation,
      };
    case "foot":
      return {
        x: sign * profile.geometry.footX,
        y: profile.geometry.footY,
        rotation: sign * 0.12,
      };
  }
}

function freezeAppendage(
  id: ProtoRigAppendageId,
  profile: GrowthVisualProfile,
  preset: ViewPreset,
): ProtoRigAppendage {
  const kind = kindForId(id);
  const side = sideForId(id);
  const base = baseAppendagePosition(kind, side, profile);
  const configured = preset.appendages[id];
  return Object.freeze({
    id,
    kind,
    side,
    x: base.x * configured.xFactor + configured.xOffset,
    y: base.y + configured.yOffset,
    scaleX: configured.scaleX,
    scaleY: configured.scaleY,
    rotation: base.rotation + configured.rotationOffset,
    opacity: configured.opacity,
    visible: configured.visible,
    depth: configured.depth,
  });
}

function freezeEye(
  side: ProtoRigSide,
  index: 0 | 1,
  profile: GrowthVisualProfile,
  preset: ViewPreset,
): ProtoRigEye {
  const sign = side === "left" ? -1 : 1;
  return Object.freeze({
    side,
    x:
      sign * profile.geometry.eyeX * preset.face.eyeXFactors[index] +
      preset.face.eyeXOffsets[index],
    y: profile.geometry.headY - 3,
    scaleX: preset.face.eyeScaleX[index],
    opacity: preset.face.eyeOpacity[index],
    visible: preset.face.eyeVisible[index],
  });
}

export function protoVisualRigForView(
  view: PresentationView,
  profile: GrowthVisualProfile,
): ProtoVisualRig {
  const preset = VIEW_PRESETS[view];
  if (!preset) throw new Error(`Unsupported Proto view: ${String(view)}`);
  const cached = RIG_CACHE.get(profile)?.get(view);
  if (cached) return cached;

  const appendages = Object.freeze(PROTO_RIG_APPENDAGE_IDS.map((id) => freezeAppendage(id, profile, preset)));
  const hidden = Object.freeze(appendages.filter((item) => !item.visible).map((item) => item.id));
  const translucent = Object.freeze(
    appendages.filter((item) => item.visible && item.opacity < 1).map((item) => item.id),
  );
  const body = Object.freeze({
    x: preset.body[0],
    y: profile.geometry.bodyY + preset.body[1],
    radiusX: profile.geometry.bodyRadiusX * preset.body[2],
    radiusY: profile.geometry.bodyRadiusY * preset.body[3],
    rotation: preset.body[4],
    depth: 40,
  });
  const head = Object.freeze({
    x: preset.head[0],
    y: profile.geometry.headY + preset.head[1],
    radiusX: profile.geometry.headRadiusX * preset.head[2],
    radiusY: profile.geometry.headRadiusY * preset.head[3],
    rotation: preset.head[4],
    depth: 60,
  });
  const face = Object.freeze({
    kind: preset.face.kind,
    visible: preset.face.kind !== "none",
    centerX: preset.face.centerX,
    mouthX: preset.face.centerX,
    depth: 70,
    eyes: Object.freeze([
      freezeEye("left", 0, profile, preset),
      freezeEye("right", 1, profile, preset),
    ]) as readonly [ProtoRigEye, ProtoRigEye],
  });
  const dorsalSeam = Object.freeze({ visible: preset.dorsalSeam, opacity: preset.dorsalSeam ? 0.62 : 0, depth: 68 });
  const core = Object.freeze({
    visual: profile.corePearl,
    shellTransmission: preset.coreOpacity,
    occludedByShell: preset.coreOccluded,
    depth: 72,
  });
  const visibleLayers = [
    ...appendages.filter((item) => item.visible).map((item) => ({ id: item.id as ProtoRigLayerId, depth: item.depth })),
    { id: "body" as const, depth: body.depth },
    { id: "head" as const, depth: head.depth },
    ...(face.visible ? [{ id: "face" as const, depth: face.depth }] : []),
    ...(dorsalSeam.visible ? [{ id: "dorsal-seam" as const, depth: dorsalSeam.depth }] : []),
    { id: "core" as const, depth: core.depth },
  ].sort(
    (left, right) =>
      left.depth - right.depth || (LAYER_RANK.get(left.id) ?? 0) - (LAYER_RANK.get(right.id) ?? 0),
  );

  const rig = Object.freeze({
    schemaVersion: PROTO_VISUAL_RIG_VERSION,
    view,
    silhouette: preset.silhouette,
    nearSide: preset.nearSide,
    farSide: preset.farSide,
    body,
    head,
    appendages,
    face,
    core,
    dorsalSeam,
    occlusion: Object.freeze({ hiddenAppendages: hidden, translucentAppendages: translucent }),
    depthOrder: Object.freeze(visibleLayers.map((layer) => layer.id)),
  });
  const profileCache = RIG_CACHE.get(profile) ?? new Map<PresentationView, ProtoVisualRig>();
  profileCache.set(view, rig);
  if (!RIG_CACHE.has(profile)) RIG_CACHE.set(profile, profileCache);
  return rig;
}

export function protoRigAppendage(
  rig: ProtoVisualRig,
  kind: ProtoRigAppendageKind,
  side: ProtoRigSide,
): ProtoRigAppendage {
  const match = rig.appendages.find((item) => item.kind === kind && item.side === side);
  if (!match) throw new Error(`Missing ${kind}-${side} in ${rig.schemaVersion}`);
  return match;
}
