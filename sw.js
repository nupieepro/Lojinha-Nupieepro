/* ============================================================
   SERVICE WORKER — NUPIEEPRO STORE v5
   Caminhos relativos — funciona em qualquer subpasta
   ============================================================ */

const CACHE = 'nupieepro-v15';

const CACHEAR = [
    'https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap',
    './fontawesome-subset.css',
    './fonts/fa-solid-subset.woff2',
    './fonts/fa-brands-subset.woff2',
    './loja_icon_marca.png',
    './loja_icon_emblema.png',
    './loja_icon_pwa.png',
    './qrcode.min.js',
    './icons/loja-icon-180.png',
    './icons/loja-icon-152.png',
    './icons/loja-icon-192.png',
];

self.addEventListener('install', e => {
    /* skipWaiting — ativa imediatamente sem esperar abas antigas fecharem */
    self.skipWaiting();
    e.waitUntil(
        caches.open(CACHE).then(c => c.addAll(CACHEAR)).catch(() => {})
    );
});

self.addEventListener('activate', e => {
    e.waitUntil(
        caches.keys()
            .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
            .then(() => self.clients.claim())
    );
});

self.addEventListener('fetch', e => {
    const url = e.request.url;

    if (e.request.method !== 'GET') return;
    if (url.startsWith('chrome-extension')) return;

    /* Nunca cacheia: API Supabase, analytics */
    if (
        url.includes('supabase.co') ||
        url.includes('google-analytics') ||
        url.includes('googletagmanager')
    ) return;

    /* Fontes do Google — cache-first (raramente mudam) */
    if (url.includes('fonts.g')) {
        e.respondWith(
            caches.match(e.request).then(c => c || fetch(e.request).then(res => {
                const clone = res.clone();
                caches.open(CACHE).then(cache => cache.put(e.request, clone));
                return res;
            }))
        );
        return;
    }

    /* A PÁGINA em si: busca ignorando o cache HTTP do navegador.
       O GitHub Pages manda Cache-Control: max-age=600, então um "rede primeiro"
       comum ainda podia devolver um HTML de até 10 min atrás — quem já tinha o
       site aberto/instalado ficava vendo a versão velha mesmo online. */
    if (e.request.destination === 'document') {
        e.respondWith(
            fetch(e.request.url, { cache: 'no-store' })
                .then(res => {
                    /* resposta redirecionada não pode ser devolvida a uma navegação */
                    if (!res || !res.ok || res.redirected) throw new Error('recorrer ao fetch normal');
                    const clone = res.clone();
                    caches.open(CACHE).then(c => c.put(e.request, clone));
                    return res;
                })
                .catch(() => fetch(e.request).catch(() => caches.match(e.request)))
        );
        return;
    }

    /* Demais arquivos — rede primeiro, cache como fallback offline */
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
