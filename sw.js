/* ============================================================
   SERVICE WORKER — NUPIEEPRO STORE
   Versão: 1.0.0
   Responsável: cache offline, atualização silenciosa
   ============================================================ */

const CACHE_NAME = 'nupieepro-v1';
const CACHE_OFFLINE = 'nupieepro-offline-v1';

/* Arquivos que ficam em cache sempre */
const ARQUIVOS_ESSENCIAIS = [
  '/',
  '/index.html',
  '/manifest.json',
  'https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap',
  'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css'
];

/* ── INSTALAÇÃO ── */
self.addEventListener('install', (evento) => {
  evento.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(ARQUIVOS_ESSENCIAIS);
    })
  );
  /* Ativa imediatamente sem esperar fechar outras abas */
  self.skipWaiting();
});

/* ── ATIVAÇÃO ── */
self.addEventListener('activate', (evento) => {
  evento.waitUntil(
    caches.keys().then((nomes) => {
      return Promise.all(
        nomes
          .filter((nome) => nome !== CACHE_NAME && nome !== CACHE_OFFLINE)
          .map((nome) => caches.delete(nome))
      );
    })
  );
  /* Assume controle de todas as abas abertas imediatamente */
  self.clients.claim();
});

/* ── INTERCEPTAÇÃO DE REQUISIÇÕES ── */
self.addEventListener('fetch', (evento) => {
  const url = new URL(evento.request.url);

  /* Ignora requisições ao Apps Script (sempre online) */
  if (url.hostname.includes('script.google.com')) return;

  /* Ignora requisições POST */
  if (evento.request.method !== 'GET') return;

  evento.respondWith(
    caches.match(evento.request).then((respostaCache) => {
      if (respostaCache) {
        /* Encontrou no cache — devolve e atualiza em background */
        atualizarEmBackground(evento.request);
        return respostaCache;
      }

      /* Não encontrou no cache — busca na rede */
      return fetch(evento.request)
        .then((respostaRede) => {
          /* Salva no cache se for uma resposta válida */
          if (respostaRede && respostaRede.status === 200) {
            const respostaClone = respostaRede.clone();
            caches.open(CACHE_NAME).then((cache) => {
              cache.put(evento.request, respostaClone);
            });
          }
          return respostaRede;
        })
        .catch(() => {
          /* Sem rede — mostra página offline */
          return caches.match('/index.html').then((paginaOffline) => {
            if (paginaOffline) return paginaOffline;
            /* Fallback mínimo se nem o index estiver em cache */
            return new Response(
              `<!DOCTYPE html>
              <html lang="pt-BR">
              <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>Nupieepro — Sem conexão</title>
                <style>
                  body { font-family: sans-serif; background: #0f0732; color: #fff;
                    display: flex; flex-direction: column; align-items: center;
                    justify-content: center; height: 100vh; margin: 0; text-align: center; padding: 20px; }
                  h1 { color: #f85900; font-size: 1.4rem; margin-bottom: 10px; }
                  p { opacity: 0.8; font-size: 0.9rem; line-height: 1.5; }
                  button { margin-top: 20px; padding: 12px 30px; background: #f85900;
                    color: #fff; border: none; border-radius: 30px; font-size: 1rem;
                    font-weight: 700; cursor: pointer; }
                </style>
              </head>
              <body>
                <h1>Você está offline 📡</h1>
                <p>Verifique sua conexão e tente novamente.<br>A Lojinha Nupieepro está te esperando! 🧡</p>
                <button onclick="location.reload()">Tentar novamente</button>
              </body>
              </html>`,
              { headers: { 'Content-Type': 'text/html; charset=utf-8' } }
            );
          });
        });
    })
  );
});

/* ── ATUALIZAÇÃO SILENCIOSA EM BACKGROUND ── */
function atualizarEmBackground(requisicao) {
  fetch(requisicao).then((respostaRede) => {
    if (respostaRede && respostaRede.status === 200) {
      caches.open(CACHE_NAME).then((cache) => {
        cache.put(requisicao, respostaRede);
      });
    }
  }).catch(() => {});
}

/* ── NOTIFICAÇÕES PUSH (base pra fase futura) ── */
self.addEventListener('push', (evento) => {
  if (!evento.data) return;

  const dados = evento.data.json();
  const opcoes = {
    body: dados.body || 'Nova novidade na Lojinha Nupieepro!',
    icon: 'https://i.ibb.co/7hcph2F/download.jpg',
    badge: 'https://i.ibb.co/7hcph2F/download.jpg',
    vibrate: [200, 100, 200],
    data: { url: dados.url || '/' },
    actions: [
      { action: 'ver', title: 'Ver agora 🛍️' },
      { action: 'fechar', title: 'Fechar' }
    ]
  };

  evento.waitUntil(
    self.registration.showNotification(dados.title || 'Nupieepro Store 🧡', opcoes)
  );
});

/* ── CLIQUE NA NOTIFICAÇÃO ── */
self.addEventListener('notificationclick', (evento) => {
  evento.notification.close();

  if (evento.action === 'fechar') return;

  const urlDestino = evento.notification.data?.url || '/';
  evento.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientesAbertos) => {
      for (const cliente of clientesAbertos) {
        if (cliente.url === urlDestino && 'focus' in cliente) {
          return cliente.focus();
        }
      }
      if (clients.openWindow) return clients.openWindow(urlDestino);
    })
  );
});
