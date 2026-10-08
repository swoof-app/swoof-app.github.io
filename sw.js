// Swoof – service worker : permet l'installation et l'utilisation hors connexion
const CACHE = 'swoof-v4';
const FILES = ['./', './index.html', './manifest.json', './icon-192.png', './icon-512.png', './apple-touch-icon.png', './favicon.png', './img/q1.webp', './img/q2.webp', './img/q4.webp', './img/q5.webp', './img/q6.webp', './img/q7.webp', './img/q9.webp', './img/q10.webp', './img/q11.webp', './img/q13.webp', './img/q14.webp', './img/q15.webp', './img/q16.webp', './img/q17.webp', './img/q20.webp', './img/q22.webp', './img/q23.webp', './img/q24.webp', './img/q25.webp', './img/q26.webp', './img/q29.webp', './img/q30.webp', './img/q31.webp', './img/q32.webp', './img/q33.webp', './img/q38.webp', './img/q40.webp', './img/q101.webp', './img/q103.webp', './img/q106.webp', './img/q107.webp', './img/q108.webp', './img/q110.webp', './img/q111.webp', './img/q112.webp', './img/q114.webp', './img/q115.webp', './img/q116.webp', './img/q117.webp', './img/q119.webp', './img/q120.webp', './img/q121.webp', './img/q122.webp', './img/q123.webp', './img/q124.webp', './img/q125.webp', './img/q126.webp', './img/q127.webp', './img/q128.webp'];
self.addEventListener('install', e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(FILES))); self.skipWaiting(); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))); self.clients.claim(); });
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  e.respondWith(
    fetch(e.request).then(res => { const copy = res.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)).catch(()=>{}); return res; })
      .catch(() => caches.match(e.request).then(r => r || caches.match('./index.html')))
  );
});
