import { copyFile, mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { fileURLToPath, pathToFileURL } from "node:url";
import path from "node:path";
import {
  PWA_STATIC_ASSETS,
  comparePrecacheUrls,
  digestShellAssets,
  generateServiceWorker,
  pngDimensions,
  validatePwaManifest,
  validateViteOutputPaths,
} from "./pwa-contract.mjs";

const projectRoot = fileURLToPath(new URL("../", import.meta.url));

async function filesBelow(directory) {
  const files = [];
  async function visit(current) {
    for (const entry of await readdir(current, { withFileTypes: true })) {
      const absolute = path.join(current, entry.name);
      if (entry.isDirectory()) await visit(absolute);
      else files.push(absolute);
    }
  }
  await visit(directory);
  return files;
}

export async function buildPwa(root = projectRoot) {
  const distRoot = path.join(root, "dist");
  const packageJson = JSON.parse(await readFile(path.join(root, "package.json"), "utf8"));
  const manifest = validatePwaManifest(JSON.parse(await readFile(path.join(root, "pwa/manifest.webmanifest"), "utf8")));

  const initialDistFiles = await filesBelow(distRoot);
  const builtIndex = await readFile(path.join(distRoot, "index.html"), "utf8");
  validateViteOutputPaths(
    builtIndex,
    initialDistFiles.map((absolute) => path.relative(distRoot, absolute).split(path.sep).join("/")),
  );

  for (const asset of PWA_STATIC_ASSETS) {
    const destination = path.join(distRoot, asset.output);
    await mkdir(path.dirname(destination), { recursive: true });
    await copyFile(path.join(root, asset.source), destination);
  }

  for (const icon of manifest.icons) {
    const expected = Number(icon.sizes.split("x", 1)[0]);
    const dimensions = pngDimensions(await readFile(path.join(distRoot, icon.src.slice(1))));
    if (dimensions.width !== expected || dimensions.height !== expected) {
      throw new Error(`PWA icon ${icon.src} must be ${expected}x${expected}`);
    }
  }

  const shellFiles = (await filesBelow(distRoot))
    .filter((absolute) => path.basename(absolute) !== "service-worker.js")
    .map((absolute) => [
      `/${path.relative(distRoot, absolute).split(path.sep).join("/")}`,
      absolute,
    ])
    .sort(([left], [right]) => comparePrecacheUrls(left, right));
  const shellEntries = await Promise.all(shellFiles.map(async ([url, absolute]) => [url, await readFile(absolute)]));
  const contentDigest = digestShellAssets(shellEntries);
  const template = await readFile(path.join(root, "pwa/service-worker.template.js"), "utf8");
  const serviceWorker = generateServiceWorker(template, {
    version: packageJson.version,
    precacheUrls: shellEntries.map(([url]) => url),
    contentDigest,
  });
  await writeFile(path.join(distRoot, "service-worker.js"), `${serviceWorker.trimEnd()}\n`, "utf8");

  return {
    cacheName: `archi-shell-v${packageJson.version}-${contentDigest.slice(0, 12)}`,
    precacheUrls: shellEntries.map(([url]) => url),
  };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const result = await buildPwa();
  process.stdout.write(`PWA BUILD PASS: ${result.precacheUrls.length} same-origin shell assets in ${result.cacheName}.\n`);
}
