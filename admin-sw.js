/* ============================================================
   SERVICE WORKER — NUPIEEPRO ADMIN
   Versão: 3.0.0 — Auto-update ativo
   ============================================================ */

const CACHE = 'nupi-admin-v3';

const ESSENCIAIS = [
  '/Lojinha-Nupieepro/admin.html',
  '/Lojinha-Nupieepro/admin-manifest.json',
  'https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap',
  'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css'
];

self.addEventListener('install', e => {
  /* skipWaiting imediato — novo SW toma controle sem esperar aba fechar */
  self.skipWaiting();
  e.waitUntil(
    caches.open(CACHE)
      .then(c => c.addAll(ESSENCIAIS))
      .catch(() => {}) /* não falha o install se algum recurso sumir */
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(k => k !== CACHE).map(k => caches.delete(k))
      ))
      .then(() => self.clients.claim()) /* assume controle imediato de todas as abas */
  );
});

self.addEventListener('fetch', e => {
  const url = e.request.url;

  if (e.request.method !== 'GET') return;
  if (url.startsWith('chrome-extension')) return;

  /* Supabase e APIs externas: NUNCA cacheia */
  if (
    url.includes('supabase.co') ||
    url.includes('script.google.com') ||
    url.includes('imgbb.com') ||
    url.includes('imgur.com') ||
    url.includes('google-analytics') ||
    url.includes('googletagmanager')
  ) return;

  /* Fontes e FontAwesome — cache-first (raramente mudam) */
  if (url.includes('fonts.g') || url.includes('cdnjs.cloudflare.com')) {
    e.respondWith(
      caches.match(e.request).then(cached => cached || fetch(e.request).then(res => {
        if (res && res.status === 200) {
          const clone = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, clone));
        }
        return res;
      }))
    );
    return;
  }

  /* admin.html e demais — rede primeiro, cache só se offline */
  e.respondWith(
    fetch(e.request)
      .then(res => {
        if (res && res.status === 200) {
          const clone = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, clone));
        }
        return res;
      })
      .catch(() => caches.match(e.request))
  );
});
