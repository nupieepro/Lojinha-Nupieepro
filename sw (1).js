/* ============================================================
   SERVICE WORKER — NUPIEEPRO STORE v4
   Caminhos relativos — funciona em qualquer subpasta
   ============================================================ */

const CACHE = 'nupieepro-v4';

const CACHEAR = [
    'https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap',
    'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css',
];

self.addEventListener('install', e => {
    e.waitUntil(
        caches.open(CACHE).then(c => c.addAll(CACHEAR)).catch(() => {})
    );
    self.skipWaiting();
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

    /* Nunca cacheia: API, ImgBB, QR code, analytics */
    if (
        url.includes('script.google.com') ||
        url.includes('ibb.co') ||
        url.includes('imgbb.com') ||
        url.includes('api.qrserver.com') ||
        url.includes('google-analytics') ||
        url.includes('googletagmanager')
    ) return;

    /* Fontes e FontAwesome — cache */
    if (url.includes('fonts.g') || url.includes('cdnjs.cloudflare.com')) {
        e.respondWith(
            caches.match(e.request).then(c => c || fetch(e.request).then(res => {
                const clone = res.clone();
                caches.open(CACHE).then(cache => cache.put(e.request, clone));
                return res;
            }))
        );
        return;
    }

    /* HTML — rede primeiro, cache como fallback offline */
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
