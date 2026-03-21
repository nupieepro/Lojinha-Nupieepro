/* ============================================================
   SERVICE WORKER — NUPIEEPRO STORE
   Versão: 3.0.0
   Estratégia: Network First — sempre busca versão mais nova
   ============================================================ */

const CACHE = 'nupieepro-v3';

const CACHEAR = [
    'https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap',
    'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css',
];

/* ── INSTALA ── */
self.addEventListener('install', e => {
    e.waitUntil(
        caches.open(CACHE).then(c => c.addAll(CACHEAR)).catch(() => {})
    );
    self.skipWaiting();
});

/* ── ATIVA — apaga TODOS os caches antigos ── */
self.addEventListener('activate', e => {
    e.waitUntil(
        caches.keys()
            .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
            .then(() => self.clients.claim())
    );
});

/* ── FETCH ── */
self.addEventListener('fetch', e => {
    const url = e.request.url;

    if (e.request.method !== 'GET') return;
    if (url.startsWith('chrome-extension')) return;

    /* Nunca intercepta: API, ImgBB, QR code */
    if (
        url.includes('script.google.com') ||
        url.includes('ibb.co') ||
        url.includes('api.qrserver.com') ||
        url.includes('imgbb.com')
    ) return;

    /* Fontes e FontAwesome — cache */
    if (url.includes('fonts.g') || url.includes('cdnjs.cloudflare.com')) {
        e.respondWith(
            caches.match(e.request).then(c => c || fetch(e.request))
        );
        return;
    }

    /* index.html — sempre rede, cache só pra offline */
    e.respondWith(
        fetch(e.request, { cache: 'no-store' })
            .then(res => {
                const clone = res.clone();
                caches.open(CACHE).then(c => c.put(e.request, clone));
                return res;
            })
            .catch(() => caches.match(e.request))
    );
});
