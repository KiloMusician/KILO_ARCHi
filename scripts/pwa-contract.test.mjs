import assert from "node:assert/strict";
import { lstat, readFile, readdir } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  PWA_STATIC_ASSETS,
  comparePrecacheUrls,
  digestShellAssets,
  expectedViteOutputPaths,
  generateServiceWorker,
  pngDimensions,
  pngHasTransparency,
  validatePwaManifest,
  validatePwaTemplate,
  validateViteOutputPaths,
} from "./pwa-contract.mjs";

const projectRoot = fileURLToPath(new URL("../", import.meta.url));

async function sourceTree() {
  const root = path.join(projectRoot, "pwa");
  const files = [];
  async function visit(current) {
    for (const entry of await readdir(current, { withFileTypes: true })) {
      const absolute = path.join(current, entry.name);
      assert.equal(entry.isSymbolicLink(), false, `${path.relative(projectRoot, absolute)} must not be a symlink`);
      if (entry.isDirectory()) await visit(absolute);
      else files.push(path.relative(projectRoot, absolute).split(path.sep).join("/"));
    }
  }
  await visit(root);
  return files.sort();
}

test("accepts the exact bounded ARCHi manifest", async () => {
  const manifest = JSON.parse(await readFile(path.join(projectRoot, "pwa/manifest.webmanifest"), "utf8"));
  assert.equal(validatePwaManifest(manifest), manifest);
  assert.equal(Object.hasOwn(manifest, "share_target"), false);
  assert.equal(Object.hasOwn(manifest, "protocol_handlers"), false);
  assert.equal(Object.hasOwn(manifest, "file_handlers"), false);
  assert.equal(Object.hasOwn(manifest, "shortcuts"), false);
});

test("keeps the PWA source tree exact, local, and link-free", async () => {
  assert.deepEqual(await sourceTree(), [
    "pwa/archi-core-icon.svg",
    "pwa/icons/archi-180.png",
    "pwa/icons/archi-192.png",
    "pwa/icons/archi-32.png",
    "pwa/icons/archi-512.png",
    "pwa/icons/archi-maskable-192.png",
    "pwa/icons/archi-maskable-512.png",
    "pwa/manifest.webmanifest",
    "pwa/service-worker.template.js",
  ]);
  for (const asset of PWA_STATIC_ASSETS) {
    assert.equal((await lstat(path.join(projectRoot, asset.source))).isFile(), true);
    assert.equal(asset.output.includes(".."), false);
  }
});

test("ships correctly sized Core Pearl PNG icons", async () => {
  const expectedSizes = new Map([
    ["pwa/icons/archi-32.png", 32],
    ["pwa/icons/archi-180.png", 180],
    ["pwa/icons/archi-192.png", 192],
    ["pwa/icons/archi-512.png", 512],
    ["pwa/icons/archi-maskable-192.png", 192],
    ["pwa/icons/archi-maskable-512.png", 512],
  ]);
  for (const [relative, size] of expectedSizes) {
    assert.deepEqual(pngDimensions(await readFile(path.join(projectRoot, relative))), { width: size, height: size });
  }
});

test("ships full-bleed opaque install mask and Apple icons", async () => {
  for (const relative of [
    "pwa/icons/archi-180.png",
    "pwa/icons/archi-maskable-192.png",
    "pwa/icons/archi-maskable-512.png",
  ]) {
    assert.equal(pngHasTransparency(await readFile(path.join(projectRoot, relative))), false, `${relative} must be opaque`);
  }
});

test("accepts only the exact Vite outputs referenced by the built index", () => {
  const builtIndex = `<!doctype html><script type="module" crossorigin src="/assets/index-a1.js"></script><link rel="stylesheet" crossorigin href="/assets/index-b2.css">`;
  const exact = ["assets/index-b2.css", "index.html", "assets/index-a1.js"];
  assert.deepEqual(expectedViteOutputPaths(builtIndex), [...exact].sort());
  assert.deepEqual(validateViteOutputPaths(builtIndex, exact), [...exact].sort());
  assert.throws(
    () => validateViteOutputPaths(builtIndex, [...exact, "assets/unexpected.json"]),
    /Vite output surface differs/,
  );
  assert.throws(
    () => validateViteOutputPaths(builtIndex, [...exact, "assets/index-a1.js.map"]),
    /Vite output surface differs/,
  );
  assert.throws(
    () => expectedViteOutputPaths(builtIndex.replace('type="module"', 'type="application/json"')),
    /JavaScript asset must be loaded by a script element/,
  );
});

test("generates one digest-bound, exact-precache service worker", async () => {
  const template = await readFile(path.join(projectRoot, "pwa/service-worker.template.js"), "utf8");
  validatePwaTemplate(template);
  const entries = [
    ["/assets/index-a.js", Buffer.from("javascript")],
    ["/assets/index-b.css", Buffer.from("stylesheet")],
    ["/index.html", Buffer.from("document")],
    ["/pwa/icons/archi-192.png", Buffer.from("icon")],
    ["/pwa/manifest.webmanifest", Buffer.from("manifest")],
  ];
  const digest = digestShellAssets(entries);
  const worker = generateServiceWorker(template, {
    version: "0.6.0",
    precacheUrls: entries.map(([url]) => url),
    contentDigest: digest,
  });
  assert.match(worker, new RegExp(`archi-shell-v0\\.6\\.0-${digest.slice(0, 12)}`));
  assert.equal(worker.includes("__ARCHI_"), false);
  assert.equal(worker.includes("skipWaiting"), false);
  assert.equal(worker.includes("clients.claim"), false);
});

test("rotates the shell digest when one asset byte changes", () => {
  const baseline = digestShellAssets([["/index.html", Buffer.from("one")]]);
  const changed = digestShellAssets([["/index.html", Buffer.from("two")]]);
  assert.notEqual(changed, baseline);
});

test("uses stable code-point order for mixed-case hashed asset names", () => {
  const urls = ["/assets/index-Dgc.css", "/assets/index-DPB.js", "/index.html"];
  const sorted = [...urls].sort(comparePrecacheUrls);
  assert.deepEqual(sorted, ["/assets/index-DPB.js", "/assets/index-Dgc.css", "/index.html"]);
  assert.equal(comparePrecacheUrls("/assets/index-DPB.js", "/assets/index-Dgc.css"), -1);
});

test("rejects unsafe, duplicated, and unsorted precache surfaces", async () => {
  const template = await readFile(path.join(projectRoot, "pwa/service-worker.template.js"), "utf8");
  const options = { version: "0.6.0", contentDigest: "a".repeat(64) };
  assert.throws(
    () => generateServiceWorker(template, { ...options, precacheUrls: ["/index.html", "/../Journey.json"] }),
    /outside the exact app-shell surface/,
  );
  assert.throws(
    () => generateServiceWorker(template, { ...options, precacheUrls: ["/index.html", "/index.html"] }),
    /unique/,
  );
  assert.throws(
    () => generateServiceWorker(template, { ...options, precacheUrls: ["/pwa/manifest.webmanifest", "/index.html"] }),
    /sorted/,
  );
});

test("rejects Journey, background, messaging, and forced-activation capability in the worker", async () => {
  const template = await readFile(path.join(projectRoot, "pwa/service-worker.template.js"), "utf8");
  for (const forbidden of [
    'localStorage.getItem("archi.journey.v3")',
    'self.addEventListener("sync", () => {})',
    'self.addEventListener("message", () => {})',
    "self.skipWaiting()",
    "self.clients.claim()",
  ]) {
    assert.throws(() => validatePwaTemplate(`${template}\n${forbidden}\n`), /PWA contract/);
  }
});
