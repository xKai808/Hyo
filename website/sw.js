// hyo hq — service worker
// Strategy: network-first for HTML/JSON (always fresh data), cache-first for assets

const CACHE = 'hq-v4';  // bumped: ant credit bars + real platform cost data
const PRECACHE = [
  '/hq.html',
  '/manifest.json',
  '/icon-192.png',
  '/icon-512.png',
  '/icon-180.png',
];

// Install: pre-cache shell
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(PRECACHE)).then(() => self.skipWaiting())
  );
});

// Activate: delete old caches
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

// Fetch: network-first for HTML/JSON, cache-first for everything else
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);

  // Skip cross-origin (Google Fonts, etc.)
  if (url.origin !== self.location.origin) return;

  // Network-first for HTML pages (with OR without extension — handles clean URLs like /hq)
  const isDataOrPage = url.pathname.endsWith('.html') ||
                       url.pathname.endsWith('.json') ||
                       !url.pathname.includes('.');  // clean URLs: /hq, /research, etc.

  if (isDataOrPage) {
    // Network-first: always try to get fresh data; fall back to cache if offline
    e.respondWith(
      fetch(e.request)
        .then(res => {
          const clone = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, clone));
          return res;
        })
        .catch(() => caches.match(e.request))
    );
  } else {
    // Cache-first: fonts, icons, scripts load instantly from cache
    e.respondWith(
      caches.match(e.request).then(cached => {
        if (cached) return cached;
        return fetch(e.request).then(res => {
          const clone = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, clone));
          return res;
        });
      })
    );
  }
});
