# 🛍️ LOJINHA NUPIEEPRO — Contexto Completo
> Para usar no Antigravity IDE. Última auditoria: Abril/2026.
> Estado atual: **modo manutenção ativo**, arquivos sem alteração desde a auditoria.

---

## 1. O que é isso

Loja oficial do NUPIEEPRO (Núcleo Piauiense de Estudantes de Engenharia de Produção — UFPI).
- **Frontend:** `index.html` hospedado no GitHub Pages
- **Admin:** `admin.html` (repositório privado separado)
- **Backend:** Google Apps Script + Google Sheets
- **Design:** roxo `#0f0732`, laranja `#f85900`, fonte Plus Jakarta Sans

---

## 2. Arquivos do projeto

| Arquivo | Descrição | Trocar? |
|---------|-----------|---------|
| `index.html` | Vitrine pública — ~1079 linhas | ✅ Principal alvo de correções |
| `admin.html` | Painel admin — ~1755 linhas | ✅ Principal alvo de correções |
| `sw.js` | Service Worker da loja (cache v4) | ✅ Bumpar versão ao publicar |
| `admin-sw.js` | Service Worker do admin (v1) | ✅ Corrigir estratégia de cache |
| `manifest.json` | PWA manifest da loja | ⚠️ Corrigir `maskable` |
| `admin-manifest.json` | PWA manifest do admin | ⚠️ Corrigir `maskable` |
| `_headers.txt` | Cabeçalhos de segurança | ❌ Não funciona no GitHub Pages |
| `robots.txt` | Controle de crawlers | ⚠️ Adicionar mais bots de IA |
| `SECURITY.md` | Contato de segurança | OK |
| `README.md` | Documentação pública | OK |

---

## 3. Variáveis e constantes importantes

```js
// index.html
const API_URL = 'https://script.google.com/macros/s/AKfycbw4.../exec';
const _w = atob('NTU4Njk5OTk3NjIyNg==');    // WhatsApp destino (hardcoded — BUG B2)
const _pixKey = 'financeironupieepro@gmail.com'; // Chave PIX (hardcoded — BUG B2)

// Produtos hardcoded (fallback se API falhar):
// IDs: 1=Camisa Preta, 2=Camisa Branca, 3=Camisa Azul,
//      4=Ecobag, 5=Bloco de Notas, 6=Chaveiro, 7=Botton

// Cupons hardcoded (BUG B3 — nunca atualiza da API):
const cupons = { 'CALOUROEP10': { tipo:'percentual', valor:10, produtos_ids:[4,5,6], ... } };

// admin.html
const API_URL  = 'https://script.google.com/macros/s/AKfycbw4.../exec';
const LOJA_URL = 'https://nupieepro.github.io/Lojinha-Nupieepro/';
const IMGBB_KEY = '7dd10f3e634617cf6231fa3b4a3a728e'; // exposto publicamente — BUG S2
```

---

## 4. Fluxo atual (com bugs)

```
Cliente abre loja
  → renderVitrine() com produtos hardcoded   ← aparece rápido
  → carregarAPI() [BUG B1: sequencial ~9s]
      → buscarAPI('config')    await ~3s
      → buscarAPI('produtos')  await +3s
      → buscarAPI('cupons')    await +3s
      → aplica, mas NÃO atualiza _pixKey nem _w [BUG B2]
      → NÃO carrega cupons reais [BUG B3]

Cliente finaliza pedido (PIX)
  → carrinho = [] limpo ANTES do fetch [BUG B4]
  → fetch API com itens: []              ← API recebe carrinho vazio
  → salvarHist() salva itens vazios      [BUG B19]
  → WhatsApp abre com mensagem correta   ← OK (snapshot do texto)
  → comprovante PIX não vai junto        [BUG B10]

Admin abre painel
  → window.load faz fetch pra validar sessão [BUG B5: 3-6s tela branca]
  → mostra painel
  → admin salva produto/config
  → SW da loja serve versão cacheada    [BUG B17: cliente vê versão antiga]
```

---

## 5. Bugs — Lista Completa e Correções

### 🔴 CRÍTICOS (corrigir primeiro)

---

#### B1 — API sequencial → atraso de ~9s
**Arquivo:** `index.html` → função `carregarAPI()`

```js
// ❌ ATUAL — sequencial
async function carregarAPI() {
    const c = await buscarAPI('config');
    const d = await buscarAPI('produtos');
    const c = await buscarAPI('cupons');
}

// ✅ CORRETO — paralelo
async function carregarAPI() {
    const [resConfig, resProdutos, resCupons] = await Promise.allSettled([
        buscarAPI('config'),
        buscarAPI('produtos'),
        buscarAPI('cupons')
    ]);

    if (resConfig.status === 'fulfilled') {
        const c = resConfig.value;
        if (c.manutencao === 'true' || c.manutencao === true) {
            document.getElementById('tela-manutencao').classList.add('ativa');
            return;
        }
        if (c.mensagem_boas_vindas) {
            const el = document.querySelector('.welcome-msg');
            if (el) el.textContent = '👋 ' + c.mensagem_boas_vindas;
        }
        if (c.pausar_checkout === 'true') window._checkoutPausado = true;
        // Aplica PIX e WhatsApp dinâmicos (correção B2)
        if (c.chave_pix)      window._pixKeyDynamic  = c.chave_pix;
        if (c.whatsapp)       window._wDynamic        = c.whatsapp;
        if (c.nome_recebedor) window._pixRecebedor    = c.nome_recebedor;
    }

    if (resProdutos.status === 'fulfilled') {
        const d = resProdutos.value;
        if (Array.isArray(d) && d.length > 0) {
            produtos.length = 0;
            produtos.push(...d.map(normalizarProduto));
            renderVitrine();
        }
    }

    if (resCupons.status === 'fulfilled') {
        const data = resCupons.value;
        // Aplica cupons reais da API (correção B3)
        if (Array.isArray(data.cupons)) {
            cupons = {};
            data.cupons.forEach(c => {
                if (c.ativo === true || c.ativo === 'true' || c.ativo === 'TRUE') {
                    cupons[c.codigo] = c;
                }
            });
        }
        if (data.tem_cupom_ativo || Object.keys(cupons).length > 0) {
            document.getElementById('card-cupom').style.display = 'block';
        }
    }
}
```

**Ganho: de ~9s para ~3s.**

---

#### B2 — PIX e WhatsApp hardcoded (admin não consegue mudar)
**Arquivo:** `index.html`

```js
// ❌ ATUAL — hardcoded, ignora o que admin configurou
const _pixKey = (()=>{ const p=['financeiro','nupieepro','@gmail.com']; return p[0]+p[1]+p[2]; })();
const _w = atob('NTU4Njk5OTk3NjIyNg==');

// ✅ ADICIONAR — funções que preferem o valor do admin
function getPixKey()    { return window._pixKeyDynamic  || _pixKey; }
function getWhatsApp()  { return window._wDynamic       || _w; }
function getRecebedor() { return window._pixRecebedor   || 'NUPIEEPRO'; }
```

Substituir todas as referências diretas a `_pixKey`, `_w` e `'NUPIEEPRO'` pelas funções acima.

---

#### B3 — Cupons hardcoded (nunca chegam os do admin)
**Arquivo:** `index.html`

```js
// ❌ ATUAL — const, nunca atualiza
const cupons = { 'CALOUROEP10': { ... } };

// ✅ CORRETO — let, começa vazio, preenchido pela API
let cupons = {};
```

A atualização real acontece dentro do `carregarAPI()` corrigido (ver B1 acima).
**Atenção:** o Apps Script precisa retornar `{ tem_cupom_ativo: bool, cupons: [...] }` na action `cupons`.

---

#### B4 — Carrinho vazio na API (limpa antes de enviar)
**Arquivo:** `index.html` → `enviarPedidoZap()`

```js
// ❌ ATUAL — limpa antes de usar
carrinho = []; cupomApl = null;
fetch(API_URL, { body: JSON.stringify({ itens: carrinho }) }); // sempre []

// ✅ CORRETO — salva snapshot primeiro
const itensFinal    = [...carrinho];
const subtotalFinal = calcSub();
const descontoFinal = calcDesc();
const totalFinal    = calcTotal();
const cupomFinal    = cupomApl ? cupomApl.cod : '';

// abre WhatsApp aqui (código existente)

// só depois limpa
carrinho = []; cupomApl = null; window._comprovante = null;
salvarCarrinho(); atualizarBarra();

// registra com snapshot correto
fetch(API_URL, { method:'POST', body: JSON.stringify({
    action: 'registrar_pedido',
    numero: num, nome, whatsapp: zap, email, entrega,
    endereco: end, pagamento: pgto, observacao: obs,
    itens: itensFinal,        // ← snapshot
    subtotal: subtotalFinal,
    desconto: descontoFinal,
    cupom: cupomFinal,
    total: totalFinal
}) }).catch(()=>{});
```

---

#### B11 — QR PIX usa chave hardcoded mesmo com config do admin
**Arquivo:** `index.html` → `gerarQRPix()`

```js
// ❌ ATUAL
const payload = gerarPayloadPix(_pixKey, 'NUPIEEPRO', tot);

// ✅ CORRETO
const payload = gerarPayloadPix(getPixKey(), getRecebedor(), tot);
const kvEl = document.getElementById('pix-chave-val');
if (kvEl) kvEl.textContent = getPixKey();
```

---

#### B17 — SW cacheia a loja, cliente vê versão antiga após publicação
**Arquivo:** `admin.html` — adicionar após `salvarProduto(true)` e `salvarConfig(true)` com sucesso:

```js
async function invalidarCacheLoja() {
    try {
        if ('caches' in window) {
            const keys = await caches.keys();
            await Promise.all(
                keys.filter(k => k.includes('nupieepro')).map(k => caches.delete(k))
            );
        }
        if ('serviceWorker' in navigator) {
            const regs = await navigator.serviceWorker.getRegistrations();
            await Promise.all(regs.map(r => r.update()));
        }
    } catch(e) {}
}
```

**Arquivo:** `sw.js` — bumpar versão a cada publicação:
```js
// Muda de v4 para v5 (ou v6, v7... incrementa sempre)
const CACHE = 'nupieepro-v5';
```

---

#### B19 — `salvarHist()` salva array vazio
**Arquivo:** `index.html`

```js
// ❌ ATUAL — usa referência ao array global (que já foi esvaziado)
function salvarHist(num, data, total) {
    h.unshift({ num, data, total, itens: carrinho.map(...) }); // carrinho já é []
}

// ✅ CORRETO — recebe snapshot como parâmetro
function salvarHist(num, data, total, itens) {
    const h = JSON.parse(localStorage.getItem('nupieepro_hist') || '[]');
    h.unshift({ num, data, total, itens });
    localStorage.setItem('nupieepro_hist', JSON.stringify(h.slice(0, 30)));
}

// Chamada (em enviarPedidoZap, após montar snapshot):
salvarHist(num, now, totalFinal, itensFinal.map(i => i.qtd + 'x ' + i.nome));
```

---

### 🟠 ALTOS (corrigir na sequência)

---

#### B5 — Admin: tela branca de 3–6s ao abrir (re-valida sessão na API)
**Arquivo:** `admin.html` → `window.addEventListener('load', ...)`

```js
// ✅ CORRETO — mostra painel imediatamente, valida em background
window.addEventListener('load', async () => {
    const saved = localStorage.getItem('nupi_admin_key');
    if (!saved) return;
    try {
        const k = atob(saved);
        // Mostra imediatamente
        chaveAdmin = k;
        document.getElementById('tela-login').style.display = 'none';
        document.getElementById('app').style.display = 'block';
        iniciarAdmin();

        // Valida em background
        const res = await Promise.race([
            fetch(API_URL, { method:'POST', body: JSON.stringify({ action:'admin_login', chave:k }) }),
            new Promise((_,r) => setTimeout(()=>r(new Error('timeout')), 5000))
        ]);
        const data = await res.json();
        if (!data.ok) sair();
    } catch(e) {
        // API offline — mantém sessão, não força logout
    }
});
```

---

#### B6 — `_headers.txt` não funciona no GitHub Pages
**Arquivo:** `_headers.txt` — pode deletar, não tem efeito nenhum.

**Solução imediata:** adicionar no `<head>` de `index.html` e `admin.html`:
```html
<meta http-equiv="X-Content-Type-Options" content="nosniff">
<meta http-equiv="Referrer-Policy" content="strict-origin-when-cross-origin">
<meta http-equiv="Permissions-Policy" content="camera=(), microphone=(), geolocation=()">
```
X-Frame-Options e CSP real só funcionam com headers HTTP — precisaria migrar pra Netlify ou Cloudflare Pages.

---

#### B8 — SW Admin: cacheia admin.html, admin vê painel antigo
**Arquivo:** `admin-sw.js` — mudar estratégia para network-first no HTML:

```js
self.addEventListener('fetch', e => {
    if (e.request.url.includes('script.google.com')) return;
    if (e.request.method !== 'GET') return;

    // HTML do admin: sempre busca da rede
    if (e.request.mode === 'navigate' || e.request.url.includes('admin.html')) {
        e.respondWith(
            fetch(e.request)
                .then(res => {
                    if (res && res.status === 200) {
                        const clone = res.clone();
                        caches.open(CACHE).then(c => c.put(e.request, clone));
                    }
                    return res;
                })
                .catch(() => caches.match(e.request)) // offline fallback
        );
        return;
    }

    // Assets (fontes, FA): cache-first
    e.respondWith(
        caches.match(e.request).then(cached => {
            const network = fetch(e.request).then(res => {
                if (res && res.status === 200) {
                    const clone = res.clone();
                    caches.open(CACHE).then(c => c.put(e.request, clone));
                }
                return res;
            }).catch(() => cached);
            return cached || network;
        })
    );
});
```

---

#### B10 — Comprovante PIX não vai pelo WhatsApp
**Arquivo:** `index.html` → `enviarPedidoZap()`

WhatsApp Web não aceita anexo via `wa.me`. A solução é instrução clara:

```js
// Substituir:
if(pgto==='PIX') msg+=`PIX enviado! Aguardando confirmacao do financeiro.`;

// Por:
if (pgto === 'PIX') {
    msg += `\n*COMPROVANTE PIX:*\n`;
    msg += `Após enviar esta mensagem, mande o print/foto do comprovante no WhatsApp. 📎\n`;
    msg += `Chave PIX: ${getPixKey()}\n`;
}
```

E na tela de sucesso, mensagem condicional:
```js
document.getElementById('sucesso-msg').textContent = pgto === 'PIX'
    ? '✅ Pedido enviado! Agora mande o comprovante do PIX na conversa do WhatsApp que abriu. 📎'
    : msgs[Math.floor(Math.random() * msgs.length)];
```

---

#### B16 — Número do pedido gerado no frontend (colisão entre usuários)
**Arquivo:** `index.html` → `gerarNum()`

```js
// ✅ CORRETO — timestamp + random elimina colisão
function gerarNum() {
    const now  = new Date();
    const yyyy = now.getFullYear();
    const ts   = now.getTime().toString().slice(-5);
    const rand = Math.floor(Math.random() * 99).toString().padStart(2, '0');
    return `${yyyy}-${ts}${rand}`;
}
```

---

### 🟡 MÉDIOS

---

#### B7 — Polling notifica pedidos antigos como novos na primeira verificação
**Arquivo:** `admin.html` → `verificarNovoPedido()`

```js
let _primeiraVerificacao = true;

async function verificarNovoPedido() {
    try {
        const dados = await api({ action: 'admin_get_pedidos', status: 'novo' });
        const qtd   = dados.length;
        if (!_primeiraVerificacao && qtd > qtdPedidosAnterior) {
            const ultimo = dados[0];
            document.getElementById('notif-msg').textContent = `#${ultimo.numero} — ${ultimo.nome}`;
            document.getElementById('notif-pedido').classList.add('ativo');
            try { new Audio('data:audio/wav;base64,...').play(); } catch(e) {}
            setTimeout(() => fecharNotif(), 8000);
        }
        _primeiraVerificacao = false;
        qtdPedidosAnterior   = qtd;
    } catch(e) {}
}
```

---

#### B9 — Comprovante: aceita só imagem, não PDF
**Arquivo:** `index.html` — input de comprovante

```html
<!-- ❌ ATUAL -->
<input type="file" id="comprovante-input" accept="image/*" ...>

<!-- ✅ CORRETO -->
<input type="file" id="comprovante-input" accept="image/*,application/pdf" ...>
```

E no JS `previewComprovante()`, adicionar tratamento para PDF:
```js
if (file.type === 'application/pdf') {
    document.getElementById('comprovante-preview').innerHTML = `
        <div style="text-align:center;padding:12px">
            <i class="fa-solid fa-file-pdf" style="font-size:2rem;color:#e74c3c"></i>
            <div style="font-size:0.75rem;color:var(--verde-zap);font-weight:700;margin-top:4px">
                ✅ PDF: ${file.name}
            </div>
            <button onclick="removerComprovante()" style="font-size:0.72rem;color:var(--vermelho-del);background:none;border:none;cursor:pointer;margin-top:4px">Trocar</button>
        </div>`;
    document.getElementById('comprovante-preview').style.display = 'block';
    document.getElementById('comprovante-label').style.display = 'none';
    window._comprovante = { tipo: 'pdf', nome: file.name };
    return;
}
```

---

#### B12 — Toggle config: race condition se clicar rápido
**Arquivo:** `admin.html` → `salvarConfigToggle()`

```js
const _configToggleTimers = {};

async function salvarConfigToggle(chave, valor) {
    clearTimeout(_configToggleTimers[chave]);
    _configToggleTimers[chave] = setTimeout(async () => {
        try {
            await api({ action: 'admin_salvar_config', config: { [chave]: valor.toString() } });
        } catch(e) { toast('Erro ao salvar configuração', true); }
    }, 400);
}
```

---

#### B14 — Manifest: ícones `maskable` com JPEG quebram em Android
**Arquivo:** `manifest.json` e `admin-manifest.json`

```json
// ❌ ATUAL — maskable com JPEG sem safe zone adequada
{ "purpose": "any maskable" }

// ✅ CORRETO — remove maskable até ter PNG adequado
{ "purpose": "any" }
```

---

#### B15 — `carregarConfig()` chamada toda vez que abre a aba
**Arquivo:** `admin.html`

```js
let _configTTL = 0;

async function carregarConfig(forcar = false) {
    const agora = Date.now();
    if (!forcar && configCache && Object.keys(configCache).length && (agora - _configTTL) < 30000) {
        preencherFormConfig(configCache);
        return;
    }
    try {
        configCache = await api({ action: 'admin_get_config' });
        _configTTL  = agora;
        preencherFormConfig(configCache);
    } catch(e) { toast('Erro ao carregar config', true); }
}

// Extrair o preenchimento do formulário para função separada:
function preencherFormConfig(c) {
    document.getElementById('cfg-nome-loja').value        = c.nome_loja            || '';
    document.getElementById('cfg-boas-vindas').value      = c.mensagem_boas_vindas || '';
    document.getElementById('cfg-chave-pix').value        = c.chave_pix            || '';
    // ... resto dos campos
}
```

---

#### UX — Debounce na busca (dispara renderVitrine() a cada tecla)
**Arquivo:** `index.html`

```js
// ❌ ATUAL
document.getElementById('campo-busca').addEventListener('input', function() {
    busca = this.value.trim().toLowerCase();
    renderVitrine();
});

// ✅ CORRETO
let _buscaTimer;
document.getElementById('campo-busca').addEventListener('input', function() {
    clearTimeout(_buscaTimer);
    busca = this.value.trim().toLowerCase();
    _buscaTimer = setTimeout(() => renderVitrine(), 150);
});
```

---

#### UX — Loading state nos botões de salvar do admin
**Arquivo:** `admin.html` → `salvarProduto()` e `salvarConfig()`

```js
async function salvarProduto(publicar) {
    const btn = publicar
        ? document.querySelector('[onclick="salvarProduto(true)"]')
        : document.querySelector('[onclick="salvarProduto(false)"]');
    if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Salvando...'; }
    try {
        // código existente
    } finally {
        if (btn) {
            btn.disabled = false;
            btn.innerHTML = publicar
                ? '<i class="fa-solid fa-rocket"></i> Publicar'
                : '<i class="fa-solid fa-floppy-disk"></i> Salvar rascunho';
        }
    }
}
```

---

### 🟢 BAIXO

---

#### B13 — robots.txt incompleto (só bloqueia GPTBot e ChatGPT-User)
**Arquivo:** `robots.txt` — substituir por:

```
User-agent: *
Allow: /
Disallow: /admin
Disallow: /admin.html

User-agent: GPTBot
Disallow: /

User-agent: ChatGPT-User
Disallow: /

User-agent: Claude-Web
Disallow: /

User-agent: anthropic-ai
Disallow: /

User-agent: CCBot
Disallow: /

User-agent: Google-Extended
Disallow: /

User-agent: Bytespider
Disallow: /

User-agent: PerplexityBot
Disallow: /

User-agent: cohere-ai
Disallow: /
```

---

## 6. Segurança

| ID | Problema | Ação |
|----|----------|------|
| S1 | Rate limit em memória (reset ao recarregar) | Mover para localStorage |
| S2 | Chave ImgBB exposta no `admin.html` público | Proxear upload pelo Apps Script |
| S3 | Sem CSP real (GitHub Pages não suporta headers) | Migrar pra Cloudflare Pages |

---

## 7. Estratégia de Performance (ir além dos 3s)

### Opção A — Cache localStorage (recomendada, implementar agora)
```
1ª visita: ~3s (paralelo)
2ª visita em diante: ~0s (renderiza do cache, atualiza em background)
```

```js
// No início de carregarAPI(), antes dos fetches:
const cached = localStorage.getItem('nupi_api_cache');
if (cached) {
    try {
        const { produtos: p, config: c, ts } = JSON.parse(cached);
        if (Date.now() - ts < 5 * 60 * 1000) { // válido por 5 min
            if (c) aplicarConfig(c);
            if (p?.length) {
                produtos.length = 0;
                produtos.push(...p.map(normalizarProduto));
                renderVitrine();
            }
        }
    } catch(e) {}
}

// No final de carregarAPI(), após receber dados novos:
localStorage.setItem('nupi_api_cache', JSON.stringify({
    produtos: dadosNovos,
    config: configNova,
    ts: Date.now()
}));
```

### Opção B — Apps Script retorna tudo em 1 request ('action=tudo')
Em vez de 3 requests paralelos, 1 só:
```js
const res = await buscarAPI('tudo');
// res = { config: {...}, produtos: [...], cupons: {...} }
```
No Apps Script, adicionar case `'tudo'` que monta e retorna tudo de uma vez.
Elimina 2/3 do overhead de HTTP.

### Opção C — Keep-alive (cron-job.org a cada 4 min)
Mantém o container do Apps Script quente. Cold start de ~3s vira ~300ms.
URL: `https://cron-job.org` → chama `API_URL?action=ping` a cada 4 minutos. Grátis.

**Combinando A + B + C: percepção de 0s para recorrente, ~300ms para novo.**

---

## 8. Ordem de Execução das Correções

### Sessão 1 — Elimina atrasos e bugs críticos
- [ ] B1 — Paralelizar `carregarAPI()` com `Promise.allSettled`
- [ ] B4 + B19 — Snapshot do carrinho antes de limpar
- [ ] B2 + B11 — Funções `getPixKey()`, `getWhatsApp()`, `getRecebedor()`
- [ ] B3 — `let cupons = {}` + popular da API
- [ ] B5 — Login admin: mostrar painel imediatamente

### Sessão 2 — Confiabilidade do admin
- [ ] B8 — SW Admin: network-first para admin.html
- [ ] B17 — `invalidarCacheLoja()` após publicar + bumpar `sw.js` para v5
- [ ] B12 — Debounce em `salvarConfigToggle`
- [ ] B15 — Cache local para `carregarConfig` (TTL 30s)
- [ ] UX — Loading state nos botões de salvar

### Sessão 3 — Bugfixes médios + UX
- [ ] B9 — Aceitar PDF no comprovante
- [ ] B10 — Instrução clara sobre comprovante PIX
- [ ] B7 — Corrigir polling de novos pedidos
- [ ] B16 — Número do pedido com timestamp
- [ ] UX — Debounce na busca (150ms)

### Sessão 4 — Performance + Segurança
- [ ] Implementar cache localStorage (Opção A)
- [ ] Implementar `action=tudo` no Apps Script (Opção B)
- [ ] Configurar keep-alive no cron-job.org (Opção C)
- [ ] B13 — Atualizar robots.txt
- [ ] B14 — Remover `maskable` dos manifests
- [ ] B6 — Avaliar migração para Cloudflare Pages
- [ ] S1 — Rate limit no localStorage
- [ ] S2 — Proxy ImgBB pelo Apps Script

---

## 9. Checklist de Verificação Pós-Correção

```
[ ] Loja carrega em menos de 3s na primeira visita?
[ ] Loja carrega em menos de 1s na segunda visita (com cache)?
[ ] Admin salva produto → loja mostra em menos de 5s após reload?
[ ] Admin muda chave PIX → QR gerado com a nova chave?
[ ] Admin muda WhatsApp → pedido vai para o número correto?
[ ] Admin cria cupom → aparece na vitrine?
[ ] Pedido enviado → itens corretos no Apps Script (não array vazio)?
[ ] Histórico do cliente tem itens corretos?
[ ] Admin abre painel → aparece em menos de 1s?
[ ] Admin ativa manutenção → loja fecha imediatamente após reload?
[ ] Comprovante PDF é aceito?
[ ] Dois pedidos simultâneos geram números diferentes?
[ ] SW do admin atualiza ao publicar nova versão?
```

---

*Auditoria: Abril/2026 · 20 bugs + 5 UX + 4 segurança = 29 itens*
*🔴 Crítico: 6 · 🟠 Alto: 5 · 🟡 Médio: 7 · 🟢 Baixo: 2*
