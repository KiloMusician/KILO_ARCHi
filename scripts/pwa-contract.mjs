import { createHash } from "node:crypto";

export const PWA_CACHE_PREFIX = "archi-shell-";
export const PWA_SHELL_FALLBACK = "/index.html";

export const PWA_STATIC_ASSETS = Object.freeze([
  Object.freeze({ source: "pwa/manifest.webmanifest", output: "pwa/manifest.webmanifest" }),
  Object.freeze({ source: "pwa/icons/archi-32.png", output: "pwa/icons/archi-32.png" }),
  Object.freeze({ source: "pwa/icons/archi-180.png", output: "pwa/icons/archi-180.png" }),
  Object.freeze({ source: "pwa/icons/archi-192.png", output: "pwa/icons/archi-192.png" }),
  Object.freeze({ source: "pwa/icons/archi-512.png", output: "pwa/icons/archi-512.png" }),
  Object.freeze({ source: "pwa/icons/archi-maskable-192.png", output: "pwa/icons/archi-maskable-192.png" }),
  Object.freeze({ source: "pwa/icons/archi-maskable-512.png", output: "pwa/icons/archi-maskable-512.png" }),
]);

const EXPECTED_MANIFEST = Object.freeze({
  id: "/",
  name: "ARCHi · One light, shaped by you",
  short_name: "ARCHi",
  description: "A local digital companion shaped through care and play.",
  lang: "en-US",
  start_url: "/",
  scope: "/",
  display: "standalone",
  background_color: "#02080a",
  theme_color: "#061114",
  categories: ["games", "lifestyle"],
  prefer_related_applications: false,
  icons: [
    { src: "/pwa/icons/archi-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
    { src: "/pwa/icons/archi-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
    { src: "/pwa/icons/archi-maskable-192.png", sizes: "192x192", type: "image/png", purpose: "maskable" },
    { src: "/pwa/icons/archi-maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
  ],
});

function fail(message) {
  throw new Error(`PWA contract: ${message}`);
}

export function validatePwaManifest(manifest) {
  if (JSON.stringify(manifest) !== JSON.stringify(EXPECTED_MANIFEST)) {
    fail("manifest must match the bounded local ARCHi install contract");
  }
  for (const icon of manifest.icons) {
    if (!icon.src.startsWith("/pwa/icons/") || icon.src.includes("..")) fail(`unsafe icon path ${icon.src}`);
  }
  return manifest;
}

export function pngDimensions(bytes) {
  const signature = "89504e470d0a1a0a";
  if (bytes.length < 24 || bytes.subarray(0, 8).toString("hex") !== signature) fail("icon is not a PNG");
  if (bytes.subarray(12, 16).toString("ascii") !== "IHDR") fail("icon has no leading IHDR chunk");
  return { width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
}

export function pngHasTransparency(bytes) {
  pngDimensions(bytes);
  const colorType = bytes.readUInt8(25);
  if (colorType === 4 || colorType === 6) return true;
  let offset = 8;
  while (offset + 12 <= bytes.length) {
    const length = bytes.readUInt32BE(offset);
    const type = bytes.subarray(offset + 4, offset + 8).toString("ascii");
    if (type === "tRNS") return true;
    offset += 12 + length;
  }
  return false;
}

export function expectedViteOutputPaths(indexHtml) {
  const references = [...indexHtml.matchAll(/(?:src|href)=["'](\/assets\/[A-Za-z0-9._-]+)["']/g)].map(
    ([, url]) => url,
  );
  const allAssetMarkers = indexHtml.match(/\/assets\//g) ?? [];
  if (references.length !== 2 || allAssetMarkers.length !== references.length) {
    fail("built index must reference exactly one script and one stylesheet asset");
  }
  const script = references.filter((url) => url.endsWith(".js"));
  const stylesheet = references.filter((url) => url.endsWith(".css"));
  if (script.length !== 1 || stylesheet.length !== 1) {
    fail("built index must reference one .js module and one .css stylesheet");
  }
  const scriptTag = indexHtml.match(
    new RegExp(`<script\\b[^>]*\\bsrc=["']${script[0].replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}["'][^>]*>`, "i"),
  )?.[0];
  if (!scriptTag || !/\btype=["']module["']/i.test(scriptTag)) {
    fail("built JavaScript asset must be loaded by a script element");
  }
  const stylesheetTag = indexHtml.match(
    new RegExp(`<link\\b[^>]*\\bhref=["']${stylesheet[0].replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}["'][^>]*>`, "i"),
  )?.[0];
  if (!stylesheetTag || !/\brel=["']stylesheet["']/i.test(stylesheetTag)) {
    fail("built stylesheet asset must be loaded by a link element");
  }
  return ["index.html", script[0].slice(1), stylesheet[0].slice(1)].sort();
}

export function validateViteOutputPaths(indexHtml, actualRelativePaths) {
  const expected = expectedViteOutputPaths(indexHtml);
  const actual = [...actualRelativePaths].sort();
  if (new Set(actual).size !== actual.length) fail("Vite output paths must be unique");
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    fail(`Vite output surface differs from the index references: expected ${expected.join(", ")}; received ${actual.join(", ")}`);
  }
  return expected;
}

export function validatePwaTemplate(template) {
  for (const marker of ["__ARCHI_CACHE_NAME__", "__ARCHI_PRECACHE_URLS__", "__ARCHI_SHELL_FALLBACK__"]) {
    if (template.split(marker).length !== 2) fail(`service-worker template must contain ${marker} exactly once`);
  }
  for (const eventName of ["install", "activate", "fetch"]) {
    if (!template.includes(`self.addEventListener(\"${eventName}\"`)) fail(`service worker must handle ${eventName}`);
  }
  if (!template.includes('url.origin !== self.location.origin')) fail("service worker must reject cross-origin requests");
  if (!template.includes('request.method !== "GET"')) fail("service worker must ignore non-GET requests");
  if (!template.includes('url.pathname !== "/" && url.pathname !== SHELL_FALLBACK')) {
    fail("offline navigation fallback must be limited to the app root");
  }
  if (!template.includes('url.search !== ""')) fail("service worker must reject query variants of static assets");
  if (!template.includes('name.startsWith(CACHE_PREFIX)')) fail("cache cleanup must stay inside the ARCHi prefix");
  if (/\b(?:indexedDB|localStorage|sessionStorage|BroadcastChannel|Notification|PushManager)\b|addEventListener\s*\(\s*["'](?:push|sync|periodicsync|message)["']|skipWaiting\s*\(|clients\s*\.\s*claim\s*\(/.test(template)) {
    fail("service worker may cache the app shell only; data, messaging, push, sync, and forced activation are forbidden");
  }
  return template;
}

function validatePrecacheUrl(url) {
  if (!/^\/(?:index\.html|assets\/[A-Za-z0-9._-]+|pwa\/manifest\.webmanifest|pwa\/icons\/[A-Za-z0-9._-]+)$/.test(url)) {
    fail(`precache path is outside the exact app-shell surface: ${url}`);
  }
}

export function comparePrecacheUrls(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

export function generateServiceWorker(template, { version, precacheUrls, contentDigest }) {
  validatePwaTemplate(template);
  if (!/^\d+\.\d+\.\d+$/.test(version)) fail(`invalid package version ${version}`);
  if (!/^[a-f0-9]{64}$/.test(contentDigest)) fail("content digest must be lowercase SHA-256");
  for (const url of precacheUrls) validatePrecacheUrl(url);
  const normalizedUrls = [...precacheUrls].sort(comparePrecacheUrls);
  if (new Set(normalizedUrls).size !== normalizedUrls.length) fail("precache paths must be unique");
  if (JSON.stringify(normalizedUrls) !== JSON.stringify(precacheUrls)) fail("precache paths must be sorted");
  if (!normalizedUrls.includes(PWA_SHELL_FALLBACK)) fail("precache must contain the navigation fallback");
  const cacheName = `${PWA_CACHE_PREFIX}v${version}-${contentDigest.slice(0, 12)}`;
  return template
    .replace("__ARCHI_CACHE_NAME__", JSON.stringify(cacheName))
    .replace("__ARCHI_PRECACHE_URLS__", JSON.stringify(normalizedUrls))
    .replace("__ARCHI_SHELL_FALLBACK__", JSON.stringify(PWA_SHELL_FALLBACK));
}

export function digestShellAssets(entries) {
  const hash = createHash("sha256");
  for (const [url, bytes] of [...entries].sort(([left], [right]) => comparePrecacheUrls(left, right))) {
    validatePrecacheUrl(url);
    hash.update(url);
    hash.update("\0");
    hash.update(bytes);
    hash.update("\0");
  }
  return hash.digest("hex");
}
