/* ============================================================
   SERVICE WORKER — NUPIEEPRO ADMIN
   Versão: 3.0.0 — Auto-update ativo
   ============================================================ */

const CACHE = 'nupi-admin-v10';

const ESSENCIAIS = [
  './admin.html',
  './admin-manifest.json',
  './icons/admin-icon-180.png',
  './icons/admin-icon-192.png',
  './design-tokens.css',
  './fontawesome-subset.css',
  './fonts/fa-solid-subset.woff2',
  './fonts/fa-brands-subset.woff2',
  './fonts/adumu-regular-subset.woff2',
  './fonts/leaguespartan-bold-subset.woff2',
  './vendor/supabase-js-2.112.2.min.js'
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
    url.includes('google-analytics') ||
    url.includes('googletagmanager')
  ) return;

  /* admin.html: busca ignorando o cache HTTP do navegador. O GitHub Pages manda
     Cache-Control: max-age=600 — sem "no-store" aqui, o próprio painel admin podia
     continuar rodando uma versão de até 10min atrás depois de um deploy novo,
     mesmo já com clients.claim() ativo (mesmo bug que existia em sw.js pra loja). */
  if (e.request.destination === 'document') {
    e.respondWith(
      fetch(e.request, { cache: 'no-store' })
        .then(res => {
          if (!res || !res.ok || res.redirected) throw new Error('recorrer ao fetch normal');
          const clone = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, clone));
          return res;
        })
        .catch(() => fetch(e.request).catch(() => caches.match(e.request)))
    );
    return;
  }

  /* Demais arquivos — rede primeiro, cache só se offline */
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
