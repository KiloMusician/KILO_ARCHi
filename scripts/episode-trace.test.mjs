import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  EPISODE_TRACE_BOUNDARY,
  REQUIRED_EPISODE_ACTIONS,
  canonicalEpisodeJson,
  createEpisodeTraceRecorder,
  episodeArtifactReceipt,
  episodeSha256,
  projectEpisodeObservation,
  validateEpisodeTrace,
  writeEpisodeTrace,
} from "./episode-trace.mjs";

function observation(overrides = {}) {
  return {
    mode: "habitat",
    journey: {
      revision: "rev-0",
      completedPlays: 0,
      stage: "Hatchling",
      bond: 1,
      expression: "scout",
      keptTraceCount: 0,
      ledger: { eventCount: 0, head: null, rawEvents: [{ secret: true }] },
      care: { energy: 80, calm: 75, curiosity: 50, mood: "Balanced", keptTraceCount: 0, lastAction: null },
      core: { identity: "ARCHi", authority: "propose-only" },
      storage: "local-browser",
      seed: "must-not-leak",
    },
    session: null,
    inputGuard: { blocked: false, reason: null },
    userText: "must-not-leak",
    localStorageBytes: "must-not-leak",
    ...overrides,
  };
}

function recorder(root, fixtureSha256 = episodeSha256({ fixture: "synthetic" })) {
  const absoluteRoot = path.resolve(root);
  const buildPath =
    absoluteRoot === process.cwd()
      ? path.join(absoluteRoot, "package.json")
      : path.join(absoluteRoot, "build", "surface.js");
  if (absoluteRoot !== process.cwd()) {
    fs.mkdirSync(path.dirname(buildPath), { recursive: true });
    if (!fs.existsSync(buildPath)) fs.writeFileSync(buildPath, "export const syntheticBuild = true;\n");
  }
  const buildAssets = [episodeArtifactReceipt(buildPath, { root: absoluteRoot, mediaType: "text/javascript" })];
  return createEpisodeTraceRecorder({
    runId: "test-run",
    startedAt: "2026-08-31T12:00:00.000Z",
    packageVersion: "0.6.1",
    buildMode: "test",
    buildAssets,
    surfaceSha256: episodeSha256(buildAssets),
    fixtureName: "synthetic-test",
    fixtureSha256,
    artifactRoot: root,
  });
}

function complete(recorderInstance, states = {}) {
  let before = states.before ?? observation();
  for (const [index, action] of REQUIRED_EPISODE_ACTIONS.entries()) {
    const after = states[index] ?? observation({ mode: index >= 2 && index <= 3 ? "field" : index >= 4 ? "reflection" : "habitat" });
    recorderInstance.recordStep({
      action,
      before,
      after,
      checks: [{ name: `${action}-check`, passed: true }],
    });
    before = after;
  }
}

test("canonical Episode hashes are stable across object key order", () => {
  assert.equal(canonicalEpisodeJson({ z: 1, a: { y: 2, x: 3 } }), canonicalEpisodeJson({ a: { x: 3, y: 2 }, z: 1 }));
  assert.equal(episodeSha256({ z: 1, a: 2 }), episodeSha256({ a: 2, z: 1 }));
  assert.notEqual(episodeSha256({ a: 2 }), episodeSha256({ a: 3 }));
});

test("observation projection is immutable, non-mutating, and drops sensitive extras", () => {
  const source = observation();
  const bytes = JSON.stringify(source);
  const projected = projectEpisodeObservation(source);
  assert.equal(JSON.stringify(source), bytes);
  assert.equal(projected.journey.ledger.rawEvents, undefined);
  assert.equal(projected.journey.seed, undefined);
  assert.equal(projected.userText, undefined);
  assert.equal(projected.localStorageBytes, undefined);
  assert.equal(Object.isFrozen(projected), true);
  assert.equal(Object.isFrozen(projected.journey.care), true);
});

test("fixed boundary cannot be overridden and terminal traces finalize once", () => {
  const buildAssets = [episodeArtifactReceipt(path.resolve("package.json"), { root: process.cwd(), mediaType: "application/json" })];
  const instance = createEpisodeTraceRecorder({
    runId: "boundary-test",
    startedAt: "2026-08-31T12:00:00.000Z",
    packageVersion: "0.6.1",
    buildMode: "test",
    buildAssets,
    surfaceSha256: episodeSha256(buildAssets),
    fixtureName: "synthetic-test",
    fixtureSha256: episodeSha256({ fixture: true }),
    boundary: { recorderWritesJourney: true },
  });
  assert.deepEqual(instance.snapshot().boundary, EPISODE_TRACE_BOUNDARY);
  complete(instance);
  instance.finalizePass({ completedAt: "2026-08-31T12:01:00.000Z" });
  assert.throws(() => instance.finalizeFail({ completedAt: "2026-08-31T12:02:00.000Z", message: "late" }), /already/);
  assert.throws(
    () => instance.recordStep({ action: "bootstrap", before: observation(), after: observation(), checks: [{ name: "late", passed: true }] }),
    /terminal/,
  );
});

test("steps are contiguous and PASS requires every checkpoint and passing check", () => {
  const instance = recorder(process.cwd());
  assert.throws(
    () => instance.recordStep({ action: "field-opened", before: observation(), after: observation(), checks: [{ name: "order", passed: true }] }),
    /Expected Episode action bootstrap/,
  );
  instance.recordStep({
    action: "bootstrap",
    before: observation(),
    after: observation(),
    checks: [{ name: "bootstrap-check", passed: true }],
  });
  assert.throws(() => instance.finalizePass({ completedAt: "2026-08-31T12:01:00.000Z" }), /every Episode checkpoint/);

  const failedCheck = recorder(process.cwd());
  let before = observation();
  for (const [index, action] of REQUIRED_EPISODE_ACTIONS.entries()) {
    const after = observation();
    failedCheck.recordStep({
      action,
      before,
      after,
      checks: [{ name: `${action}-check`, passed: index !== 2 }],
    });
    before = after;
  }
  assert.throws(() => failedCheck.finalizePass({ completedAt: "2026-08-31T12:01:00.000Z" }), /every deterministic check/);
  assert.equal(failedCheck.snapshot().run.result, "RUNNING", "A rejected terminalization must not mutate recorder state");
});

test("trace validation rejects fields outside every allowlist even when their local hash is recomputed", () => {
  const instance = recorder(process.cwd());
  instance.recordStep({
    action: "bootstrap",
    before: observation(),
    after: observation(),
    checks: [{ name: "migration", passed: true }],
  });
  const tampered = structuredClone(instance.snapshot());
  tampered.steps[0].before.userText = "must-not-enter-evidence";
  tampered.steps[0].beforeSha256 = episodeSha256(tampered.steps[0].before);
  assert.throws(() => validateEpisodeTrace(tampered), /outside its allowlist/);

  const extraEnvelope = { ...instance.snapshot(), authorityGrant: true };
  assert.throws(() => validateEpisodeTrace(extraEnvelope), /must contain exactly/);

  const wrongSurface = structuredClone(instance.snapshot());
  wrongSurface.build.surfaceSha256 = episodeSha256({ unrelated: true });
  assert.throws(() => validateEpisodeTrace(wrongSurface), /does not bind its asset receipts/);
});

test("checkpoint observations form one continuous projected trajectory", () => {
  const instance = recorder(process.cwd());
  complete(instance);
  const tampered = structuredClone(instance.snapshot());
  tampered.steps[1].before.journey.bond = 2;
  tampered.steps[1].beforeSha256 = episodeSha256(tampered.steps[1].before);
  assert.throws(() => validateEpisodeTrace(tampered), /does not continue/);
});

test("terminal validation rejects an empty build surface even with recomputed digests", () => {
  const instance = recorder(process.cwd());
  complete(instance);
  const tampered = structuredClone(instance.finalizePass({ completedAt: "2026-08-31T12:01:00.000Z" }));
  tampered.build.assets = [];
  tampered.build.surfaceSha256 = episodeSha256([]);
  const payload = structuredClone(tampered);
  delete payload.traceSha256;
  tampered.traceSha256 = episodeSha256(payload);
  assert.throws(() => validateEpisodeTrace(tampered), /at least one exact receipt/);
});

test("FAIL retains bounded partial evidence", () => {
  const instance = recorder(process.cwd());
  instance.recordStep({
    action: "bootstrap",
    before: observation(),
    after: observation(),
    checks: [{ name: "migration", passed: true }],
  });
  const trace = instance.finalizeFail({ completedAt: "2026-08-31T12:01:00.000Z", message: "synthetic failure" });
  assert.equal(trace.run.result, "FAIL");
  assert.equal(trace.steps.length, 1);
  assert.equal(trace.failure.message, "synthetic failure");
  assert.equal(validateEpisodeTrace(trace), true);
});

test("artifact receipt validation rejects changed files", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "archi-episode-"));
  try {
    const artifactPath = path.join(root, "screens", "frame.png");
    fs.mkdirSync(path.dirname(artifactPath), { recursive: true });
    fs.writeFileSync(artifactPath, Buffer.from("first"));
    const receipt = episodeArtifactReceipt(artifactPath, { root, mediaType: "image/png" });
    const instance = recorder(root);
    let before = observation();
    for (const [index, action] of REQUIRED_EPISODE_ACTIONS.entries()) {
      const after = observation();
      instance.recordStep({
        action,
        before,
        after,
        checks: [{ name: `${action}-check`, passed: true }],
        artifacts: index === 0 ? [receipt] : [],
      });
      before = after;
    }
    fs.writeFileSync(artifactPath, Buffer.from("changed"));
    assert.throws(() => instance.finalizePass({ completedAt: "2026-08-31T12:01:00.000Z" }), /no longer matches/);
    assert.equal(instance.snapshot().run.result, "RUNNING", "Artifact drift must not leave a false terminal state");
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("a complete trace writes below ignored output and never enters dist", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "archi-episode-write-"));
  try {
    const instance = recorder(root);
    complete(instance);
    const trace = instance.finalizePass({ completedAt: "2026-08-31T12:01:00.000Z" });
    const tracePath = path.join(root, "output", "episode-traces", "test-run", "trace.json");
    const outputRoot = path.join(root, "output", "episode-traces");
    writeEpisodeTrace(tracePath, trace, { artifactRoot: root, outputRoot });
    assert.equal(JSON.parse(fs.readFileSync(tracePath, "utf8")).traceSha256, trace.traceSha256);
    assert.equal(fs.existsSync(path.join(root, "dist", "episode-traces")), false);
    assert.throws(
      () => writeEpisodeTrace(path.join(root, "outside.json"), trace, { artifactRoot: root, outputRoot }),
      /strictly below/,
    );
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
