const CACHE_PREFIX = "archi-shell-";
const CACHE_NAME = __ARCHI_CACHE_NAME__;
const PRECACHE_URLS = Object.freeze(__ARCHI_PRECACHE_URLS__);
const PRECACHE_SET = new Set(PRECACHE_URLS);
const SHELL_FALLBACK = __ARCHI_SHELL_FALLBACK__;

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(PRECACHE_URLS)));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((names) =>
        Promise.all(
          names
            .filter((name) => name.startsWith(CACHE_PREFIX) && name !== CACHE_NAME)
            .map((name) => caches.delete(name)),
        ),
      ),
  );
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === "navigate") {
    if (url.pathname !== "/" && url.pathname !== SHELL_FALLBACK) return;
    event.respondWith(
      fetch(request).catch(async () => {
        const cache = await caches.open(CACHE_NAME);
        return (await cache.match(SHELL_FALLBACK)) ?? Response.error();
      }),
    );
    return;
  }

  if (url.search !== "") return;
  if (!PRECACHE_SET.has(url.pathname)) return;
  event.respondWith(
    caches.open(CACHE_NAME).then(async (cache) => (await cache.match(url.pathname)) ?? fetch(request)),
  );
});
