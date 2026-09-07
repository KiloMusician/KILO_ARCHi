import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";

export const EPISODE_TRACE_FORMAT = "archi-episode-trace";
export const EPISODE_TRACE_SCHEMA_VERSION = 1;
export const REQUIRED_EPISODE_ACTIONS = Object.freeze([
  "bootstrap",
  "greet-committed",
  "field-opened",
  "proposal-formed",
  "choice-committed",
  "reload-verified",
]);

export const EPISODE_TRACE_BOUNDARY = Object.freeze({
  authority: "developer-evidence-only",
  recorderWritesJourney: false,
  browserImportable: false,
  playerVisible: false,
  storage: "ignored-node-output",
  automaticPromotion: false,
});

const SHA256_PATTERN = /^sha256:[a-f0-9]{64}$/;
const MAX_STEPS = 32;

function isPlainObject(value) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function canonicalValue(value, seen = new Set()) {
  if (value === null || typeof value === "string" || typeof value === "boolean") return JSON.stringify(value);
  if (typeof value === "number" && Number.isFinite(value)) return Object.is(value, -0) ? "0" : JSON.stringify(value);
  if (Array.isArray(value)) {
    if (seen.has(value)) throw new TypeError("Episode trace values must not contain cycles");
    seen.add(value);
    const result = `[${value.map((entry) => canonicalValue(entry, seen)).join(",")}]`;
    seen.delete(value);
    return result;
  }
  if (isPlainObject(value)) {
    if (seen.has(value)) throw new TypeError("Episode trace values must not contain cycles");
    seen.add(value);
    const result = `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalValue(value[key], seen)}`)
      .join(",")}}`;
    seen.delete(value);
    return result;
  }
  throw new TypeError(`Episode trace contains a non-JSON value (${typeof value})`);
}

export function canonicalEpisodeJson(value) {
  return canonicalValue(value);
}

export function episodeSha256(value) {
  return `sha256:${createHash("sha256").update(canonicalEpisodeJson(value)).digest("hex")}`;
}

function bytesSha256(value) {
  return `sha256:${createHash("sha256").update(value).digest("hex")}`;
}

function cloneJson(value) {
  return JSON.parse(canonicalEpisodeJson(value));
}

function deepFreeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const child of Object.values(value)) deepFreeze(child);
  }
  return value;
}

function boundedString(value, label, maximumLength = 160) {
  if (typeof value !== "string" || value.length === 0 || value.length > maximumLength) {
    throw new TypeError(`${label} must be a non-empty string no longer than ${maximumLength} characters`);
  }
  return value;
}

function nullableString(value, label, maximumLength = 160) {
  if (value === null || value === undefined) return null;
  return boundedString(value, label, maximumLength);
}

function finiteNumber(value, label) {
  if (typeof value !== "number" || !Number.isFinite(value)) throw new TypeError(`${label} must be a finite number`);
  return value;
}

function nonNegativeInteger(value, label) {
  if (!Number.isSafeInteger(value) || value < 0) throw new TypeError(`${label} must be a non-negative safe integer`);
  return value;
}

function isoTimestamp(value, label) {
  const timestamp = boundedString(value, label, 40);
  if (!Number.isFinite(Date.parse(timestamp))) throw new TypeError(`${label} must be an ISO-compatible timestamp`);
  return timestamp;
}

function stringArray(value, label, maximumEntries = 12) {
  if (!Array.isArray(value) || value.length > maximumEntries) {
    throw new TypeError(`${label} must be an array with at most ${maximumEntries} entries`);
  }
  return value.map((entry, index) => nullableString(entry, `${label}[${index}]`, 100));
}

function requireExactKeys(value, expectedKeys, label) {
  if (!isPlainObject(value)) throw new TypeError(`${label} must be an object`);
  const actual = Object.keys(value).sort();
  const expected = [...expectedKeys].sort();
  if (canonicalEpisodeJson(actual) !== canonicalEpisodeJson(expected)) {
    throw new Error(`${label} must contain exactly: ${expected.join(", ")}`);
  }
}

function requireExactNormalized(value, normalized, label) {
  if (canonicalEpisodeJson(value) !== canonicalEpisodeJson(normalized)) {
    throw new Error(`${label} contains fields or values outside its allowlist`);
  }
}

function projectHead(head) {
  if (head === null || head === undefined) return null;
  if (!isPlainObject(head)) throw new TypeError("observation.journey.ledger.head must be an object or null");
  return {
    sequence: nonNegativeInteger(head.sequence, "observation.journey.ledger.head.sequence"),
    eventId: boundedString(head.eventId, "observation.journey.ledger.head.eventId", 160),
    kind: boundedString(head.kind, "observation.journey.ledger.head.kind", 60),
  };
}

export function projectEpisodeObservation(observation) {
  if (!isPlainObject(observation) || !isPlainObject(observation.journey)) {
    throw new TypeError("Episode observations must contain a Journey projection object");
  }
  const source = observation.journey;
  const ledger = isPlainObject(source.ledger) ? source.ledger : {};
  const care = isPlainObject(source.care) ? source.care : {};
  const core = isPlainObject(source.core) ? source.core : {};
  const session = observation.session;
  const guard = isPlainObject(observation.inputGuard) ? observation.inputGuard : {};

  return deepFreeze({
    mode: boundedString(observation.mode, "observation.mode", 40),
    journey: {
      revision: boundedString(source.revision, "observation.journey.revision", 160),
      completedPlays: nonNegativeInteger(source.completedPlays, "observation.journey.completedPlays"),
      stage: boundedString(source.stage, "observation.journey.stage", 60),
      bond: finiteNumber(source.bond, "observation.journey.bond"),
      expression: boundedString(source.expression, "observation.journey.expression", 80),
      keptTraceCount: nonNegativeInteger(source.keptTraceCount, "observation.journey.keptTraceCount"),
      ledger: {
        eventCount: nonNegativeInteger(ledger.eventCount, "observation.journey.ledger.eventCount"),
        head: projectHead(ledger.head),
      },
      care: {
        energy: finiteNumber(care.energy, "observation.journey.care.energy"),
        calm: finiteNumber(care.calm, "observation.journey.care.calm"),
        curiosity: finiteNumber(care.curiosity, "observation.journey.care.curiosity"),
        mood: boundedString(care.mood, "observation.journey.care.mood", 80),
        keptTraceCount: nonNegativeInteger(care.keptTraceCount, "observation.journey.care.keptTraceCount"),
        lastAction: nullableString(care.lastAction, "observation.journey.care.lastAction", 40),
      },
      core: {
        identity: boundedString(core.identity, "observation.journey.core.identity", 80),
        authority: boundedString(core.authority, "observation.journey.core.authority", 80),
      },
    },
    session:
      session === null || session === undefined
        ? null
        : {
            id: boundedString(session.id, "observation.session.id", 160),
            baseRevision: boundedString(session.baseRevision, "observation.session.baseRevision", 160),
            fieldName: boundedString(session.fieldName, "observation.session.fieldName", 120),
            collected: stringArray(session.collected, "observation.session.collected"),
            proposals: stringArray(session.proposals, "observation.session.proposals"),
          },
    inputGuard: {
      blocked: guard.blocked === true,
      reason: nullableString(guard.reason, "observation.inputGuard.reason", 100),
    },
  });
}

function normalizeArtifactReceipt(receipt, label) {
  if (!isPlainObject(receipt)) throw new TypeError(`${label} must be an artifact receipt object`);
  const relativePath = boundedString(receipt.path, `${label}.path`, 500).split(path.sep).join("/");
  if (path.isAbsolute(relativePath) || relativePath.split("/").includes("..")) {
    throw new TypeError(`${label}.path must remain below the artifact root`);
  }
  const sha256 = boundedString(receipt.sha256, `${label}.sha256`, 71);
  if (!SHA256_PATTERN.test(sha256)) throw new TypeError(`${label}.sha256 must be a prefixed SHA-256 digest`);
  return {
    path: relativePath,
    bytes: nonNegativeInteger(receipt.bytes, `${label}.bytes`),
    sha256,
    mediaType: boundedString(receipt.mediaType ?? "application/octet-stream", `${label}.mediaType`, 100),
  };
}

export function episodeArtifactReceipt(filePath, { root = process.cwd(), mediaType = "application/octet-stream" } = {}) {
  const absoluteRoot = path.resolve(root);
  const absolutePath = path.resolve(filePath);
  const relativePath = path.relative(absoluteRoot, absolutePath);
  if (relativePath === "" || relativePath === ".." || relativePath.startsWith(`..${path.sep}`) || path.isAbsolute(relativePath)) {
    throw new TypeError("Episode artifacts must be files strictly below the artifact root");
  }
  const bytes = fs.readFileSync(absolutePath);
  return deepFreeze({
    path: relativePath.split(path.sep).join("/"),
    bytes: bytes.length,
    sha256: bytesSha256(bytes),
    mediaType: boundedString(mediaType, "artifact mediaType", 100),
  });
}

function verifyArtifactReceipt(receipt, artifactRoot, label) {
  const normalized = normalizeArtifactReceipt(receipt, label);
  if (!artifactRoot) return normalized;
  const absoluteRoot = path.resolve(artifactRoot);
  const absolutePath = path.resolve(absoluteRoot, normalized.path);
  const relativePath = path.relative(absoluteRoot, absolutePath);
  if (relativePath === "" || relativePath === ".." || relativePath.startsWith(`..${path.sep}`) || path.isAbsolute(relativePath)) {
    throw new TypeError(`${label}.path escapes the artifact root`);
  }
  const bytes = fs.readFileSync(absolutePath);
  if (bytes.length !== normalized.bytes || bytesSha256(bytes) !== normalized.sha256) {
    throw new Error(`${label} no longer matches its recorded bytes and SHA-256 digest`);
  }
  return normalized;
}

function normalizeChecks(checks, label) {
  if (!Array.isArray(checks) || checks.length === 0 || checks.length > 20) {
    throw new TypeError(`${label} must contain between 1 and 20 deterministic checks`);
  }
  return checks.map((check, index) => {
    if (!isPlainObject(check)) throw new TypeError(`${label}[${index}] must be an object`);
    return {
      name: boundedString(check.name, `${label}[${index}].name`, 100),
      passed: check.passed === true,
    };
  });
}

function tracePayload(trace) {
  const payload = cloneJson(trace);
  delete payload.traceSha256;
  return payload;
}

function validateTraceShape(trace, { artifactRoot = null } = {}) {
  if (!isPlainObject(trace)) throw new TypeError("Episode trace must be an object");
  requireExactKeys(
    trace,
    ["format", "schemaVersion", "run", "build", "boundary", "fixture", "steps", "assessment", "failure", "traceSha256"],
    "Episode trace",
  );
  if (trace.format !== EPISODE_TRACE_FORMAT || trace.schemaVersion !== EPISODE_TRACE_SCHEMA_VERSION) {
    throw new Error("Episode trace format or schema version is unsupported");
  }
  if (canonicalEpisodeJson(trace.boundary) !== canonicalEpisodeJson(EPISODE_TRACE_BOUNDARY)) {
    throw new Error("Episode trace boundary declarations are not exact");
  }
  if (!isPlainObject(trace.run) || !["RUNNING", "PASS", "FAIL"].includes(trace.run.result)) {
    throw new Error("Episode trace run state is invalid");
  }
  requireExactKeys(trace.run, ["id", "kind", "result", "startedAt", "completedAt"], "trace.run");
  boundedString(trace.run.id, "trace.run.id", 160);
  if (trace.run.kind !== "synthetic-browser-acceptance") throw new Error("Episode trace run kind is invalid");
  const parsedStart = Date.parse(isoTimestamp(trace.run.startedAt, "trace.run.startedAt"));
  if (trace.run.result === "RUNNING") {
    if (trace.run.completedAt !== null || trace.traceSha256 !== null || trace.assessment?.machine !== "RUNNING") {
      throw new Error("A running Episode trace must remain unsealed");
    }
  } else {
    const parsedCompletion = Date.parse(isoTimestamp(trace.run.completedAt, "trace.run.completedAt"));
    if (parsedCompletion < parsedStart) throw new Error("Episode trace completion cannot precede its start");
    if (!SHA256_PATTERN.test(trace.traceSha256 ?? "") || trace.assessment?.machine !== trace.run.result) {
      throw new Error("A terminal Episode trace must contain its matching assessment and digest");
    }
    if (episodeSha256(tracePayload(trace)) !== trace.traceSha256) throw new Error("Episode trace digest mismatch");
  }
  requireExactKeys(trace.assessment, ["machine", "human"], "trace.assessment");
  if (trace.assessment?.human !== "not-recorded") throw new Error("Episode trace cannot claim a human assessment");
  requireExactKeys(trace.build, ["packageVersion", "mode", "assets", "surfaceSha256"], "trace.build");
  boundedString(trace.build.packageVersion, "trace.build.packageVersion", 40);
  boundedString(trace.build.mode, "trace.build.mode", 80);
  if (!Array.isArray(trace.build.assets) || trace.build.assets.length === 0) {
    throw new Error("Episode trace build assets must contain at least one exact receipt");
  }
  trace.build.assets.forEach((receipt, index) => {
    const normalized = verifyArtifactReceipt(receipt, artifactRoot, `trace.build.assets[${index}]`);
    requireExactNormalized(receipt, normalized, `trace.build.assets[${index}]`);
  });
  if (!SHA256_PATTERN.test(trace.build?.surfaceSha256 ?? "")) throw new Error("Episode trace build surface digest is invalid");
  if (episodeSha256(trace.build.assets) !== trace.build.surfaceSha256) {
    throw new Error("Episode trace build surface digest does not bind its asset receipts");
  }
  const buildPaths = trace.build.assets.map((receipt) => receipt.path);
  if (new Set(buildPaths).size !== buildPaths.length || canonicalEpisodeJson(buildPaths) !== canonicalEpisodeJson([...buildPaths].sort())) {
    throw new Error("Episode trace build asset paths must be unique and sorted");
  }
  requireExactKeys(trace.fixture, ["status", "name", "sha256"], "trace.fixture");
  boundedString(trace.fixture.name, "trace.fixture.name", 120);
  if (trace.fixture?.status !== "synthetic" || !SHA256_PATTERN.test(trace.fixture?.sha256 ?? "")) {
    throw new Error("Episode trace fixture must be synthetic and hashed");
  }
  if (!Array.isArray(trace.steps) || trace.steps.length > MAX_STEPS) throw new Error("Episode trace steps are invalid");
  trace.steps.forEach((step, index) => {
    requireExactKeys(
      step,
      ["sequence", "action", "before", "after", "beforeSha256", "afterSha256", "checks", "artifacts"],
      `trace.steps[${index}]`,
    );
    if (step.sequence !== index + 1) throw new Error("Episode trace step sequence must be contiguous");
    if (step.action !== REQUIRED_EPISODE_ACTIONS[index]) throw new Error("Episode trace action order is invalid");
    requireExactNormalized(step.before, projectEpisodeObservation(step.before), `trace.steps[${index}].before`);
    requireExactNormalized(step.after, projectEpisodeObservation(step.after), `trace.steps[${index}].after`);
    if (episodeSha256(step.before) !== step.beforeSha256 || episodeSha256(step.after) !== step.afterSha256) {
      throw new Error(`Episode trace step ${step.sequence} observation digest mismatch`);
    }
    if (index > 0 && step.beforeSha256 !== trace.steps[index - 1].afterSha256) {
      throw new Error(`Episode trace step ${step.sequence} does not continue from the preceding checkpoint`);
    }
    requireExactNormalized(step.checks, normalizeChecks(step.checks, `trace.steps[${index}].checks`), `trace.steps[${index}].checks`);
    if (!Array.isArray(step.artifacts)) throw new Error(`Episode trace step ${step.sequence} artifacts must be an array`);
    step.artifacts.forEach((receipt, artifactIndex) => {
      const normalized = verifyArtifactReceipt(receipt, artifactRoot, `trace.steps[${index}].artifacts[${artifactIndex}]`);
      requireExactNormalized(receipt, normalized, `trace.steps[${index}].artifacts[${artifactIndex}]`);
    });
  });
  if (trace.run.result === "PASS") {
    if (trace.steps.length !== REQUIRED_EPISODE_ACTIONS.length) throw new Error("PASS requires every Episode checkpoint");
    if (trace.steps.some((step) => step.checks.some((check) => check.passed !== true))) {
      throw new Error("PASS requires every deterministic check to pass");
    }
    if (trace.failure !== null) throw new Error("PASS must not include failure information");
  }
  if (trace.run.result === "RUNNING" && trace.failure !== null) throw new Error("RUNNING must not include failure information");
  if (trace.run.result === "FAIL") {
    requireExactKeys(trace.failure, ["message"], "trace.failure");
    boundedString(trace.failure.message, "trace.failure.message", 500);
  }
  return true;
}

export function validateEpisodeTrace(trace, options = {}) {
  return validateTraceShape(trace, options);
}

export function createEpisodeTraceRecorder({
  runId,
  startedAt,
  packageVersion,
  buildMode,
  buildAssets = [],
  surfaceSha256,
  fixtureName,
  fixtureSha256,
  artifactRoot = null,
} = {}) {
  if (!Array.isArray(buildAssets) || buildAssets.length === 0) {
    throw new TypeError("Episode traces require at least one exact build asset receipt");
  }
  const normalizedAssets = buildAssets.map((receipt, index) => normalizeArtifactReceipt(receipt, `buildAssets[${index}]`));
  const trace = {
    format: EPISODE_TRACE_FORMAT,
    schemaVersion: EPISODE_TRACE_SCHEMA_VERSION,
    run: {
      id: boundedString(runId, "runId", 160),
      kind: "synthetic-browser-acceptance",
      result: "RUNNING",
      startedAt: isoTimestamp(startedAt, "startedAt"),
      completedAt: null,
    },
    build: {
      packageVersion: boundedString(packageVersion, "packageVersion", 40),
      mode: boundedString(buildMode, "buildMode", 80),
      assets: normalizedAssets,
      surfaceSha256: SHA256_PATTERN.test(surfaceSha256 ?? "")
        ? surfaceSha256
        : episodeSha256(normalizedAssets),
    },
    boundary: cloneJson(EPISODE_TRACE_BOUNDARY),
    fixture: {
      status: "synthetic",
      name: boundedString(fixtureName, "fixtureName", 120),
      sha256: SHA256_PATTERN.test(fixtureSha256 ?? "")
        ? fixtureSha256
        : (() => {
            throw new TypeError("fixtureSha256 must be a prefixed SHA-256 digest");
          })(),
    },
    steps: [],
    assessment: { machine: "RUNNING", human: "not-recorded" },
    failure: null,
    traceSha256: null,
  };
  let finalized = false;

  function snapshot() {
    return deepFreeze(cloneJson(trace));
  }

  function recordStep({ action, before, after, checks, artifacts = [] } = {}) {
    if (finalized) throw new Error("A terminal Episode trace cannot accept more steps");
    if (trace.steps.length >= MAX_STEPS) throw new Error(`Episode trace exceeds its ${MAX_STEPS}-step bound`);
    const expectedAction = REQUIRED_EPISODE_ACTIONS[trace.steps.length];
    if (action !== expectedAction) throw new Error(`Expected Episode action ${expectedAction}, received ${action}`);
    const beforeProjection = projectEpisodeObservation(before);
    const afterProjection = projectEpisodeObservation(after);
    trace.steps.push({
      sequence: trace.steps.length + 1,
      action,
      before: cloneJson(beforeProjection),
      after: cloneJson(afterProjection),
      beforeSha256: episodeSha256(beforeProjection),
      afterSha256: episodeSha256(afterProjection),
      checks: normalizeChecks(checks, `step ${trace.steps.length + 1} checks`),
      artifacts: artifacts.map((receipt, index) => normalizeArtifactReceipt(receipt, `step artifact ${index}`)),
    });
    return snapshot();
  }

  function finalize(result, completedAt, failure) {
    if (finalized) throw new Error("Episode trace has already been finalized");
    if (!["PASS", "FAIL"].includes(result)) throw new Error("Episode trace terminal result is invalid");
    const candidate = cloneJson(trace);
    candidate.run.result = result;
    candidate.run.completedAt = isoTimestamp(completedAt, "completedAt");
    candidate.assessment.machine = result;
    candidate.failure = failure;
    candidate.traceSha256 = episodeSha256(tracePayload(candidate));
    validateTraceShape(candidate, { artifactRoot });
    Object.assign(trace, candidate);
    finalized = true;
    return snapshot();
  }

  return Object.freeze({
    recordStep,
    snapshot,
    finalizePass({ completedAt } = {}) {
      return finalize("PASS", completedAt, null);
    },
    finalizeFail({ completedAt, message } = {}) {
      return finalize("FAIL", completedAt, {
        message: boundedString(message, "failure message", 500),
      });
    },
    get finalized() {
      return finalized;
    },
  });
}

export function writeEpisodeTrace(filePath, trace, { artifactRoot = null, outputRoot } = {}) {
  validateTraceShape(trace, { artifactRoot });
  if (typeof outputRoot !== "string" || outputRoot.length === 0) {
    throw new TypeError("Episode trace writes require an explicit output root");
  }
  const absoluteOutputRoot = path.resolve(outputRoot);
  const absoluteFilePath = path.resolve(filePath);
  const targetRelative = path.relative(absoluteOutputRoot, absoluteFilePath);
  if (
    targetRelative === "" ||
    targetRelative === ".." ||
    targetRelative.startsWith(`..${path.sep}`) ||
    path.isAbsolute(targetRelative)
  ) {
    throw new TypeError("Episode trace file must remain strictly below its output root");
  }
  fs.mkdirSync(absoluteOutputRoot, { recursive: true, mode: 0o700 });
  const realOutputRoot = fs.realpathSync(absoluteOutputRoot);
  const parent = path.dirname(absoluteFilePath);
  fs.mkdirSync(parent, { recursive: true, mode: 0o700 });
  const realParent = fs.realpathSync(parent);
  const realParentRelative = path.relative(realOutputRoot, realParent);
  if (
    realParentRelative === ".." ||
    realParentRelative.startsWith(`..${path.sep}`) ||
    path.isAbsolute(realParentRelative)
  ) {
    throw new Error("Episode trace parent must be a real directory below its output root");
  }
  const serialized = `${JSON.stringify(trace, null, 2)}\n`;
  let temporaryPath = null;
  let descriptor = null;
  try {
    for (let attempt = 0; attempt < 100; attempt += 1) {
      const candidate = path.join(parent, `.${path.basename(absoluteFilePath)}.${process.pid}.${attempt}.tmp`);
      try {
        descriptor = fs.openSync(candidate, "wx", 0o600);
        temporaryPath = candidate;
        break;
      } catch (error) {
        if (error?.code !== "EEXIST") throw error;
      }
    }
    if (descriptor === null || temporaryPath === null) throw new Error("Unable to allocate an Episode trace temporary file");
    fs.writeFileSync(descriptor, serialized, { encoding: "utf8" });
    fs.fsyncSync(descriptor);
    fs.closeSync(descriptor);
    descriptor = null;
    fs.renameSync(temporaryPath, absoluteFilePath);
    temporaryPath = null;
  } finally {
    if (descriptor !== null) fs.closeSync(descriptor);
    if (temporaryPath !== null) {
      try {
        fs.unlinkSync(temporaryPath);
      } catch (error) {
        if (error?.code !== "ENOENT") throw error;
      }
    }
  }
}
