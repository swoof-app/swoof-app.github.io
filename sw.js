// Swoof – service worker : permet l'installation et l'utilisation hors connexion
const CACHE = 'swouf-v13';
const FILES = ['./', './index.html', './manifest.json', './icon-192.png', './icon-512.png', './apple-touch-icon.png', './favicon.png', './ebook-voyage.webp', './q1.webp', './q10.webp', './q101.webp', './q103.webp', './q106.webp', './q107.webp', './q108.webp', './q11.webp', './q110.webp', './q111.webp', './q112.webp', './q114.webp', './q115.webp', './q116.webp', './q117.webp', './q119.webp', './q120.webp', './q121.webp', './q122.webp', './q123.webp', './q124.webp', './q125.webp', './q126.webp', './q127.webp', './q128.webp', './q13.webp', './q14.webp', './q15.webp', './q16.webp', './q17.webp', './q2.webp', './q20.webp', './q22.webp', './q23.webp', './q24.webp', './q25.webp', './q26.webp', './q29.webp', './q30.webp', './q31.webp', './q32.webp', './q33.webp', './q38.webp', './q4.webp', './q40.webp', './q5.webp', './q6.webp', './q7.webp', './q9.webp'];
self.addEventListener('install', e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(FILES))); self.skipWaiting(); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))); self.clients.claim(); });
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const u = new URL(e.request.url);
  // images : d'abord celles déjà enregistrées dans le téléphone (instantané), sinon internet
  if (u.origin === location.origin && /\.(webp|png|jpg|jpeg|svg)$/i.test(u.pathname)) {
    e.respondWith(caches.match(e.request).then(r => r || fetch(e.request).then(res => { if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)).catch(()=>{}); } return res; })));
    return;
  }
  e.respondWith(
    fetch(e.request).then(res => { const copy = res.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)).catch(()=>{}); return res; })
      .catch(() => caches.match(e.request).then(r => r || caches.match('./index.html')))
  );
});

// notifications (rappels Swouf)
self.addEventListener('push', e => {
  let d = {}; try { d = e.data ? e.data.json() : {}; } catch (_) { d = { body: e.data && e.data.text() }; }
  e.waitUntil(self.registration.showNotification(d.title || 'Swouf 🐾', { body: d.body || '', icon: './icon-192.png', badge: './icon-192.png', data: { url: d.url || './' } }));
});
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = new URL((e.notification.data && e.notification.data.url) || './', self.registration.scope).href;
  e.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => { for (const c of list) { if (c.url.startsWith(self.registration.scope) && 'focus' in c) return c.focus(); } return clients.openWindow(url); }));
});
