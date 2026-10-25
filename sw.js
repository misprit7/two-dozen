// Offline support: precaches the whole build on install and serves it cache-first.
// tool/build_web.sh fills in the version and file list; a new version replaces
// the old cache and takes effect on the next launch.
const CACHE = 'two-dozen-78422d2e9810';
// Flutter's loader picks the smaller Chromium CanvasKit build when these APIs exist;
// only cache the variant this browser will use.
const chromium = typeof Intl.v8BreakIterator !== 'undefined' && typeof ImageDecoder !== 'undefined';
const ASSETS = ["./", "assets/AssetManifest.bin", "assets/AssetManifest.bin.json", "assets/assets/fonts/Roboto-Bold.ttf", "assets/assets/fonts/Roboto-Medium.ttf", "assets/assets/fonts/Roboto-Regular.ttf", "assets/FontManifest.json", "assets/fonts/MaterialIcons-Regular.otf", "assets/NOTICES", "assets/packages/cupertino_icons/assets/CupertinoIcons.ttf", "assets/shaders/ink_sparkle.frag", "assets/shaders/stretch_effect.frag", "canvaskit/canvaskit.js", "canvaskit/canvaskit.wasm", "canvaskit/chromium/canvaskit.js", "canvaskit/chromium/canvaskit.wasm", "favicon.png", "flutter_bootstrap.js", "flutter.js", "icons/apple-touch-icon.png", "icons/Icon-192.png", "icons/Icon-512.png", "icons/Icon-maskable-192.png", "icons/Icon-maskable-512.png", "index.html", "main.dart.js", "manifest.json", "pool_worker.js", "version.json"].filter((a) => !a.startsWith(chromium ? 'canvaskit/canvaskit.' : 'canvaskit/chromium/'));

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE)
      .then((cache) => cache.addAll(ASSETS.map((a) => new Request(a, { cache: 'reload' }))))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k.startsWith('two-dozen-') && k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET' || new URL(request.url).origin !== self.location.origin) return;
  if (request.mode === 'navigate') {
    event.respondWith(caches.match('index.html').then((r) => r || fetch(request)));
    return;
  }
  event.respondWith(
    caches.match(request, { ignoreSearch: true }).then((cached) => {
      if (cached) return cached;
      return fetch(request).then((response) => {
        if (response.ok) {
          const copy = response.clone();
          caches.open(CACHE).then((cache) => cache.put(request, copy));
        }
        return response;
      });
    }),
  );
});
