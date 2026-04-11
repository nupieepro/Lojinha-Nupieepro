# ⚡ ANTIGRAVITY — Auditoria Completa: Lojinha NUPIEEPRO
> Versão: Abril 2026 · Autor: Claude (Anthropic) · Solicitado por: JR (José Rayan)

---

## TL;DR — Os problemas que te ferram hoje

| # | Problema | Impacto | Onde | Prioridade |
|---|----------|---------|------|------------|
| B1 | Admin salva, loja não atualiza por 5–10s (API sequencial) | 🔴 CRÍTICO | `index.html` → `carregarAPI()` | Urgente |
| B2 | PIX hardcoded no JS — admin não consegue mudar chave/WhatsApp | 🔴 CRÍTICO | `index.html` | Urgente |
| B3 | Cupons do admin não chegam na vitrine (hardcoded no HTML) | 🔴 CRÍTICO | `index.html` | Urgente |
| B4 | Carrinho vazio ao registrar pedido na API (limpa antes do POST) | 🔴 CRÍTICO | `index.html` → `enviarPedidoZap()` | Urgente |
| B5 | Admin: sessão sempre re-valida na API mesmo com sessão salva | 🟠 ALTO | `admin.html` → `window.load` | Alto |
| B6 | Admin: `_headers` não funciona no GitHub Pages (arquivo inútil) | 🟠 ALTO | `_headers.txt` | Alto |
| B7 | Admin: polling verifica novos pedidos a cada 60s mas não notifica corretamente | 🟡 MÉDIO | `admin.html` | Médio |
| B8 | SW Admin cacheando `/admin.html` sem versão — admin vê versão antiga | 🟠 ALTO | `admin-sw.js` | Alto |
| B9 | Comprovante PIX: aceita só imagem, não PDF | 🟡 MÉDIO | `index.html` | Médio |
| B10 | PIX não envia comprovante pelo WhatsApp, só texto | 🟠 ALTO | `index.html` | Alto |
| B11 | Admin salva config mas loja usa `_pixKey` hardcoded no JS | 🔴 CRÍTICO | `index.html` | Urgente |
| B12 | Admin: toggle manutenção/pausar usa POST individual — race condition possível | 🟡 MÉDIO | `admin.html` | Médio |
| B13 | `robots.txt` bloqueia GPTBot mas aceita todos os outros crawlers de IA | 🟢 BAIXO | `robots.txt` | Baixo |
| B14 | manifest.json usa `image/jpeg` mas anuncia `purpose: maskable` — ícone quebra em alguns Android | 🟡 MÉDIO | `manifest.json` | Médio |
| B15 | Admin: `carregarConfig()` chamada em toda troca de aba mas não tem debounce | 🟡 MÉDIO | `admin.html` | Médio |
| B16 | Número do pedido gerado só no frontend — dois usuários simultâneos geram o mesmo número | 🟠 ALTO | `index.html` | Alto |
| B17 | Admin não reflete mudanças de produto imediatamente na vitrine (sem invalidação de cache SW) | 🔴 CRÍTICO | `sw.js` + `admin.html` | Urgente |
| B18 | PIX QR gerado sem aguardar config do admin — sempre usa chave hardcoded | 🔴 CRÍTICO | `index.html` | Urgente |
| B19 | `salvarHist()` salva `carrinho` depois de já ter sido esvaziado | 🔴 CRÍTICO | `index.html` | Urgente |
| B20 | Admin: preview iframe carrega a loja real, não o rascunho | 🟡 MÉDIO | `admin.html` | Médio |

---

## BLOCO 1 — Bugs Críticos (Corrija Primeiro)

### B1 · Atraso de 5–10s: API chamada de forma sequencial

**Onde:** `index.html` → função `carregarAPI()`

**O problema:**
```js
// ATUAL — RUIM: config → produtos → cupons em série = ~9s
const c = await buscarAPI('config');      // espera 3s
const d = await buscarAPI('produtos');    // espera + 3s
const c = await buscarAPI('cupons');      // espera + 3s
```
Três chamadas await sequenciais. Cada Apps Script leva ~3s frio. Total: 9s bloqueando a UI.

**A correção:**
```js
// BOM: paraleliza tudo com Promise.allSettled
async function carregarAPI() {
    const [resConfig, resProdutos, resCupons] = await Promise.allSettled([
        buscarAPI('config'),
        buscarAPI('produtos'),
        buscarAPI('cupons')
    ]);

    // config
    if (resConfig.status === 'fulfilled') {
        const c = resConfig.value;
        if (c.manutencao === 'true') { /* mostra manutenção */ return; }
        // aplica welcome msg etc.
    }

    // produtos
    if (resProdutos.status === 'fulfilled') {
        const d = resProdutos.value;
        if (Array.isArray(d) && d.length > 0) {
            produtos.length = 0;
            produtos.push(...d.map(normalizarProduto));
            renderVitrine();
        }
    }

    // cupons
    if (resCupons.status === 'fulfilled') {
        const c = resCupons.value;
        if (c.tem_cupom_ativo) {
            document.getElementById('card-cupom').style.display = 'block';
        }
    }
}
```
**Ganho esperado: de ~9s para ~3s (o tempo do mais lento).**

---

### B2 · PIX hardcoded — admin não consegue mudar chave nem WhatsApp

**Onde:** `index.html`

```js
// ATUAL — hardcoded no HTML, inacessível pelo admin:
const _pixKey = (()=>{ const p=['financeiro','nupieepro','@gmail.com']; return p[0]+p[1]+p[2]; })();
const _w = atob('NTU4Njk5OTk3NjIyNg==');
```

O admin tem campos "Chave PIX" e "WhatsApp destino" na aba Config, mas eles nunca chegam até a vitrine porque o `carregarAPI()` busca config mas **nunca aplica** `c.chave_pix` nem `c.whatsapp` nas variáveis globais.

**A correção — no `carregarAPI()`, após receber config:**
```js
if (resConfig.status === 'fulfilled') {
    const c = resConfig.value;
    // APLICA as variáveis dinâmicas vindas do admin
    if (c.chave_pix)   window._pixKeyDynamic = c.chave_pix;
    if (c.whatsapp)    window._wDynamic       = c.whatsapp;
    if (c.nome_recebedor) window._pixRecebedor = c.nome_recebedor;
}
```

E nas funções que usam essas variáveis:
```js
// Sempre preferir a versão do admin se existir:
function getPixKey()    { return window._pixKeyDynamic || _pixKey; }
function getWhatsApp()  { return window._wDynamic      || _w; }
function getRecebedor() { return window._pixRecebedor  || 'NUPIEEPRO'; }
```

---

### B3 · Cupons hardcoded na vitrine — admin cria cupons que nunca chegam ao cliente

**Onde:** `index.html` — variável `cupons` no topo do script

```js
// ATUAL — hardcoded, nunca atualizado pela API:
const cupons = {
    'CALOUROEP10': { tipo:'percentual', valor:10, produtos_ids:[4,5,6], ... }
};
```

O admin pode criar cupons pelo painel, eles vão para o Sheets, mas a vitrine **sempre usa o objeto hardcoded**. O `carregarAPI('cupons')` só verifica `tem_cupom_ativo`, nunca carrega os dados reais.

**A correção:**
```js
// Muda de const para let
let cupons = {}; // começa vazio

// No carregarAPI(), após receber cupons:
if (resCupons.status === 'fulfilled') {
    const data = resCupons.value;
    if (Array.isArray(data.cupons)) {
        cupons = {}; // limpa hardcoded
        data.cupons.forEach(c => {
            if (c.ativo === true || c.ativo === 'true') {
                cupons[c.codigo] = c;
            }
        });
    }
    if (data.tem_cupom_ativo || Object.keys(cupons).length > 0) {
        document.getElementById('card-cupom').style.display = 'block';
    }
}
```

**Atenção:** o Apps Script precisa retornar `{ tem_cupom_ativo: bool, cupons: [...] }` na action `cupons`.

---

### B4 · Carrinho vazio ao registrar pedido na API

**Onde:** `index.html` → `enviarPedidoZap()`

```js
// ATUAL — BUG: esvazia o carrinho ANTES de mandá-lo para a API:
carrinho = []; cupomApl = null; window._comprovante = null; salvarCarrinho(); atualizarBarra();
fetch(API_URL, { method:'POST', body: JSON.stringify({
    ...
    itens: carrinho, // ← SEMPRE VAZIO! carrinho já foi limpo acima
    ...
}) }).catch(()=>{});
```

**A correção:**
```js
// Salva snapshot ANTES de limpar:
const itensFinal    = [...carrinho];
const subtotalFinal = calcSub();
const descontoFinal = calcDesc();
const totalFinal    = calcTotal();
const cupomFinal    = cupomApl ? cupomApl.cod : '';

// Abre WhatsApp primeiro
// ...

// Depois limpa o estado local
carrinho = []; cupomApl = null; window._comprovante = null;
salvarCarrinho(); atualizarBarra();

// Registra na API com os dados corretos
fetch(API_URL, { method:'POST', body: JSON.stringify({
    action:'registrar_pedido',
    numero: num,
    nome, whatsapp: zap, email, entrega, endereco: end,
    pagamento: pgto, observacao: obs,
    itens: itensFinal,       // ← snapshot antes de limpar
    subtotal: subtotalFinal,
    desconto: descontoFinal,
    cupom: cupomFinal,
    total: totalFinal
}) }).catch(()=>{});
```

---

### B11 · Loja usa chave PIX hardcoded mesmo quando admin configurou outra

**Onde:** `index.html` → `gerarQRPix()`

```js
// ATUAL — ignora totalmente o que o admin configurou:
const payload = gerarPayloadPix(_pixKey, 'NUPIEEPRO', tot);
```

**A correção (combinando com B2):**
```js
function gerarQRPix() {
    const tot   = calcTotal();
    const chave = getPixKey();       // usa função que prefere config do admin
    const nome  = getRecebedor();    // idem
    // ...
    const payload = gerarPayloadPix(chave, nome, tot);
    const kvEl = document.getElementById('pix-chave-val');
    if (kvEl) kvEl.textContent = chave;
    // ...
}
```

---

### B17 · Admin salva produto mas SW mantém a vitrine cacheada — cliente vê versão antiga

**Onde:** `sw.js` + `admin.html`

O SW cacheia o HTML da loja. Quando o admin publica alterações, o cliente não vê a mudança até o SW atualizar (próximo acesso). Em alguns casos, nunca atualiza porque o SW serve do cache.

**A correção no `admin.html` — após salvar produto/config com sucesso:**
```js
// Força invalidação do cache da loja
async function invalidarCacheLoja() {
    if ('caches' in window) {
        const keys = await caches.keys();
        await Promise.all(keys.filter(k => k.includes('nupieepro')).map(k => caches.delete(k)));
    }
    // Força SW a atualizar na próxima abertura da loja
    if ('serviceWorker' in navigator) {
        const regs = await navigator.serviceWorker.getRegistrations();
        await Promise.all(regs.map(r => r.update()));
    }
}

// Chama após salvarProduto(true) ou salvarConfig(true):
await invalidarCacheLoja();
toast('🚀 Publicado! Cache da loja invalidado.');
```

**E no `sw.js`, bumpa a versão para v5 ao publicar qualquer mudança:**
```js
// Muda a string do CACHE para forçar invalidação
const CACHE = 'nupieepro-v5'; // incrementa cada vez que publicar
```

Melhor ainda: **gerar a versão do cache dinamicamente** com um timestamp na publicação.

---

### B19 · `salvarHist()` salva array vazio no histórico do cliente

**Onde:** `index.html` → `enviarPedidoZap()`

```js
// ATUAL — salvarHist é chamado antes de limpar, MAS passa `carrinho`
// que depois é limpo na mesma linha em que salvarHist é declarado abaixo.
// O problema é que salvarHist usa `carrinho` por referência:
function salvarHist(num, data, total) {
    const h = JSON.parse(localStorage.getItem('nupieepro_hist') || '[]');
    h.unshift({ num, data, total, itens: carrinho.map(i => i.qtd+'x '+i.nome) }); // ← referência ao array global
    localStorage.setItem('nupieepro_hist', JSON.stringify(h.slice(0, 30)));
}
```

Na linha de `enviarPedidoZap()`, `salvarHist` é chamado, depois `carrinho=[]` é executado. Se o código for reorganizado sem cuidado (ex: ao corrigir B4), o snapshot do carrinho deve ser passado explicitamente.

**A correção:**
```js
// salvarHist recebe o snapshot como parâmetro:
function salvarHist(num, data, total, itens) {
    const h = JSON.parse(localStorage.getItem('nupieepro_hist') || '[]');
    h.unshift({ num, data, total, itens });
    localStorage.setItem('nupieepro_hist', JSON.stringify(h.slice(0, 30)));
}

// Chamada com snapshot:
salvarHist(num, now, totalFinal, itensFinal.map(i => i.qtd+'x '+i.nome));
```

---

## BLOCO 2 — Bugs Altos (Corrija na Sequência)

### B5 · Admin: sessão sempre re-valida na API ao abrir (tela branca por 3–6s)

**Onde:** `admin.html` → `window.addEventListener('load', ...)`

O `window.load` faz um fetch completo para validar a sessão salva, o que causa 3–6s de tela de login antes de mostrar o painel.

**A correção — login imediato com validação assíncrona:**
```js
window.addEventListener('load', async () => {
    const saved = localStorage.getItem('nupi_admin_key');
    if (!saved) return;

    try {
        const k = atob(saved);
        // MOSTRA O PAINEL IMEDIATAMENTE com a sessão salva
        chaveAdmin = k;
        document.getElementById('tela-login').style.display = 'none';
        document.getElementById('app').style.display = 'block';
        iniciarAdmin();

        // Valida em background — se inválido, faz logout silencioso
        const res = await Promise.race([
            fetch(API_URL, { method:'POST', body: JSON.stringify({ action:'admin_login', chave:k }) }),
            new Promise((_,r) => setTimeout(()=>r(new Error('timeout')), 5000))
        ]);
        const data = await res.json();
        if (!data.ok) sair(); // sessão expirou
    } catch(e) {
        // Se API offline, mantém sessão (melhor UX)
        // Já está mostrando o painel, não faz nada
    }
});
```

---

### B8 · SW Admin cacheia sem versão — admin fica vendo painel antigo

**Onde:** `admin-sw.js`

O cache `nupi-admin-v1` nunca muda. Se você publicar uma nova versão do `admin.html`, o SW serve a versão antiga.

**A correção:**
```js
// admin-sw.js — estratégia: network-first para admin.html
self.addEventListener('fetch', e => {
    if (e.request.url.includes('script.google.com')) return;
    if (e.request.method !== 'GET') return;

    // Para o HTML do admin: SEMPRE busca da rede, cache apenas como fallback offline
    if (e.request.url.includes('admin.html') || e.request.mode === 'navigate') {
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
        return;
    }

    // Para assets (fontes, FA): cache-first
    e.respondWith(
        caches.match(e.request).then(cached => {
            const network = fetch(e.request).then(res => {
                if (res && res.status === 200) {
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

### B10 · Comprovante PIX não vai pelo WhatsApp — cliente manda texto "PIX enviado" e o admin não vê nada

**Onde:** `index.html` → `enviarPedidoZap()`

```js
// ATUAL — a mensagem tem apenas texto sobre PIX:
if(pgto==='PIX') msg+=`PIX enviado! Aguardando confirmacao do financeiro.`;
```

O comprovante é exibido na tela mas **nunca enviado para o WhatsApp**. O admin não consegue confirmar.

**O problema real:** WhatsApp Web não aceita anexo de imagem via URL `wa.me`. A única solução viável sem backend é:
1. Abrir o WhatsApp com a mensagem de texto
2. Instruir o cliente a enviar o comprovante como imagem na conversa
3. Ou: enviar o comprovante para o email do financeiro via `mailto:`

**A correção — instrução clara na mensagem:**
```js
if (pgto === 'PIX') {
    msg += `\n*COMPROVANTE PIX:*\n`;
    msg += `Após enviar esta mensagem, por favor envie o print/foto do comprovante no WhatsApp.\n`;
    msg += `Chave PIX: ${getPixKey()}\n`;
}
```

**E na tela de sucesso, adiciona instrução visual:**
```js
document.getElementById('sucesso-msg').textContent =
    pgto === 'PIX'
        ? 'Pedido enviado! Agora envie o comprovante do PIX na conversa do WhatsApp que abriu. 📎'
        : msgs[Math.floor(Math.random() * msgs.length)];
```

**Alternativa melhor (se tiver backend):** receber o comprovante via Apps Script e armazenar no Sheets.

---

### B16 · Número do pedido gerado no frontend — colisão com dois usuários simultâneos

**Onde:** `index.html` → `gerarNum()`

```js
// ATUAL — sequência no localStorage do cliente:
function gerarNum() {
    const a = new Date().getFullYear();
    const k = 'nupieepro_seq_' + a;
    const s = parseInt(localStorage.getItem(k) || '0') + 1;
    localStorage.setItem(k, s.toString());
    return a + '-' + s.toString().padStart(3, '0');
}
```

Se dois clientes comprarem ao mesmo tempo, ambos geram `2026-001`. O admin não tem como distinguir.

**A correção — usar timestamp como fallback seguro:**
```js
function gerarNum() {
    const now  = new Date();
    const yyyy = now.getFullYear();
    const ts   = now.getTime().toString().slice(-6); // 6 dígitos do timestamp
    const rand = Math.floor(Math.random() * 99).toString().padStart(2, '0');
    return `${yyyy}-${ts}${rand}`; // ex: 2026-123456AB
}
```

**Solução ideal:** gerar o número no Apps Script e retornar na resposta do `registrar_pedido`. Mas isso exige aguardar a resposta da API antes de abrir o WhatsApp — aumenta o risco de popup blocker. Timestamp com rand é o melhor tradeoff.

---

### B6 · `_headers` não funciona no GitHub Pages — segurança ignorada

**Onde:** `_headers.txt`

GitHub Pages **não suporta** o arquivo `_headers` do Netlify. Nenhum dos cabeçalhos de segurança está sendo aplicado:
- `X-Frame-Options: DENY`
- `X-Content-Type-Options: nosniff`
- `Referrer-Policy`
- etc.

**As opções:**
1. **Mover para Netlify/Cloudflare Pages** — suportam `_headers` nativamente (recomendado)
2. **Aplicar via meta tags no HTML** — parcial, não cobre todos:
```html
<!-- Adicionar no <head> de index.html e admin.html -->
<meta http-equiv="X-Content-Type-Options" content="nosniff">
<meta http-equiv="Referrer-Policy" content="strict-origin-when-cross-origin">
<meta http-equiv="Permissions-Policy" content="camera=(), microphone=(), geolocation=()">
<!-- X-Frame-Options e CSP NÃO funcionam como meta no caso geral -->
```
3. **Usar Cloudflare como proxy** — aplica headers via Page Rules/Transform Rules (solução mais poderosa sem mudar host)

**Recomendação:** Mover o deploy para **Cloudflare Pages** (grátis, suporta `_headers`, tem CDN global, HTTPS automático).

---

## BLOCO 3 — Bugs Médios

### B7 · Polling de novos pedidos: notifica mesmo sem pedidos novos reais

**Onde:** `admin.html` → `verificarNovoPedido()`

```js
// ATUAL — notifica se qtd atual > qtdAnterior
// Problema: na primeira verificação, qtdPedidosAnterior = 0
// Se tiver 3 pedidos antigos "novo", vai notificar de todos na primeira checagem
if (qtd > qtdPedidosAnterior && qtdPedidosAnterior >= 0) { /* notifica */ }
```

Na primeira execução do polling (60s após login), `qtdPedidosAnterior = 0`. Se tiver 5 pedidos novos pendentes de ontem, vai notificar como se fossem novos agora.

**A correção:**
```js
let _primeiraVerificacao = true;

async function verificarNovoPedido() {
    try {
        const dados = await api({ action: 'admin_get_pedidos', status: 'novo' });
        const qtd   = dados.length;

        if (!_primeiraVerificacao && qtd > qtdPedidosAnterior) {
            // é realmente um pedido novo
            const ultimo = dados[0];
            document.getElementById('notif-msg').textContent = `#${ultimo.numero} — ${ultimo.nome}`;
            document.getElementById('notif-pedido').classList.add('ativo');
            // toca som
            setTimeout(() => fecharNotif(), 8000);
        }

        _primeiraVerificacao    = false;
        qtdPedidosAnterior      = qtd;
    } catch(e) {}
}
```

---

### B9 · Comprovante: aceita só `image/*`, não PDF

**Onde:** `index.html` — input de comprovante

```html
<!-- ATUAL -->
<input type="file" id="comprovante-input" accept="image/*" ...>
```

Muitos bancos geram comprovante em PDF. O cliente não consegue anexar.

**A correção:**
```html
<input type="file" id="comprovante-input" accept="image/*,application/pdf" ...>
```

E no JS, verificar o tipo:
```js
function previewComprovante(input) {
    if (!input.files || !input.files[0]) return;
    const file = input.files[0];

    if (file.type === 'application/pdf') {
        // Para PDF, só mostra ícone (não preview de imagem)
        document.getElementById('comprovante-img').src = '';
        document.getElementById('comprovante-preview').innerHTML = `
            <div style="text-align:center;padding:12px">
                <i class="fa-solid fa-file-pdf" style="font-size:2rem;color:var(--vermelho-del)"></i>
                <div style="font-size:0.75rem;color:var(--verde-zap);font-weight:700;margin-top:4px">✅ PDF anexado: ${file.name}</div>
            </div>
        `;
        document.getElementById('comprovante-preview').style.display = 'block';
        document.getElementById('comprovante-label').style.display = 'none';
        window._comprovante = { tipo: 'pdf', nome: file.name }; // flag para validação
        return;
    }

    // imagem: comportamento atual
    const reader = new FileReader();
    reader.onload = e => { /* ... */ };
    reader.readAsDataURL(file);
}
```

---

### B12 · Admin: cada toggle salva config individualmente — race condition

**Onde:** `admin.html` → `salvarConfigToggle()`

Se o usuário ativar "Manutenção" e logo depois "Pausar checkout" rapidamente, os dois POSTs podem sobrescrever um ao outro no Sheets dependendo da implementação do Apps Script.

**A correção — debounce nos toggles:**
```js
let _configToggleTimer = {};

function salvarConfigToggle(chave, valor) {
    clearTimeout(_configToggleTimer[chave]);
    _configToggleTimer[chave] = setTimeout(async () => {
        try {
            await api({ action: 'admin_salvar_config', config: { [chave]: valor.toString() } });
        } catch(e) { toast('Erro ao salvar configuração', true); }
    }, 400); // aguarda 400ms para agrupar mudanças
}
```

---

### B15 · Admin: `carregarConfig()` chamada em toda troca de aba sem cache

**Onde:** `admin.html` → `abrirAba()`

```js
case 'config': carregarConfig(); break; // chamada toda vez que abre a aba
```

Se o usuário clicar 10x na aba Config, faz 10 chamadas à API. Cada uma leva ~3s.

**A correção — cache local com TTL:**
```js
let _configTTL = 0;

async function carregarConfig(forcar = false) {
    const agora = Date.now();
    if (!forcar && configCache && (agora - _configTTL) < 30000) {
        // menos de 30s desde o último carregamento, usa cache
        preencherFormConfig(configCache);
        return;
    }
    try {
        configCache = await api({ action: 'admin_get_config' });
        _configTTL  = agora;
        preencherFormConfig(configCache);
    } catch(e) { toast('Erro ao carregar config', true); }
}
```

---

### B14 · Manifest: ícones `image/jpeg` declarados como `maskable` — quebra em Android

**Onde:** `manifest.json` e `admin-manifest.json`

```json
{
    "src": "https://i.ibb.co/7hcph2F/download.jpg",
    "purpose": "any maskable"
}
```

Ícones `maskable` devem ter fundo que preencha até as bordas (safe zone de 80%). Um JPEG de logo sem fundo adequado vai ficar distorcido/cortado no Android. Além disso, `image/jpeg` declarado para arquivo `.jpg` está correto, mas não é o ideal para PWA — PNG com transparência é o padrão.

**A correção idealmente:** criar um PNG 512×512 com fundo roxo (`#0f0732`) e logo centralizada ocupando ~60% da área. Mas enquanto não tiver o PNG:

```json
{
    "src": "https://i.ibb.co/7hcph2F/download.jpg",
    "sizes": "512x512",
    "type": "image/jpeg",
    "purpose": "any"
}
```
Remove o `maskable` até ter o ícone adequado.

---

### B20 · Preview no admin carrega a loja ao vivo, não reflete o rascunho

**Onde:** `admin.html` → `carregarPreview()`

```js
function carregarPreview() {
    document.getElementById('preview-iframe').src = LOJA_URL; // loja ao vivo
}
```

Se o admin salvou um rascunho (não publicou), o preview mostra a loja anterior. Não tem como verificar o rascunho antes de publicar.

**A solução mais simples:** mostrar aviso claro:
```js
function carregarPreview() {
    const iframe = document.getElementById('preview-iframe');
    iframe.src = LOJA_URL + '?preview=true&t=' + Date.now(); // força recarregamento
    // Mostra aviso
    const aviso = document.getElementById('preview-aviso') || (() => {
        const el = document.createElement('div');
        el.id = 'preview-aviso';
        el.style.cssText = 'background:#fff8e1;border-radius:10px;padding:10px;font-size:0.78rem;color:#f57f17;margin-bottom:10px;font-weight:600';
        el.innerHTML = '⚠️ O preview mostra a loja <strong>publicada</strong>. Rascunhos não aparecem aqui.';
        document.getElementById('aba-preview').prepend(el);
        return el;
    })();
}
```

---

### B13 · robots.txt bloqueia só GPTBot e ChatGPT-User — outros crawlers de IA passam livre

**Onde:** `robots.txt`

**Lista completa de bots de IA que deveriam ser bloqueados:**
```
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

User-agent: FacebookBot
Disallow: /

User-agent: Bytespider
Disallow: /

User-agent: PerplexityBot
Disallow: /

User-agent: cohere-ai
Disallow: /
```

---

## BLOCO 4 — Análise de Segurança

### S1 · Rate limiting no frontend é facilmente bypassável

**Onde:** `index.html` → `rlOk()`

```js
const _rl = { t:0, n:0 };
function rlOk() {
    // Limite de 3 pedidos em 30s — salvo apenas em memória
    // Basta recarregar a página para resetar
}
```

O rate limit fica apenas em memória JS — recarregar a página reseta. Alguém pode spammar a API do WhatsApp e o Apps Script.

**A correção — adicionar rate limit no localStorage:**
```js
function rlOk() {
    const JANELA = 60000; // 1 minuto
    const LIMITE = 3;
    const agora  = Date.now();
    let rlData   = JSON.parse(localStorage.getItem('nupieepro_rl') || '{"t":0,"n":0}');

    if (agora - rlData.t > JANELA) {
        rlData = { t: agora, n: 0 };
    }

    if (rlData.n >= LIMITE) {
        toast(`Aguarde antes de enviar outro pedido. (${Math.ceil((JANELA - (agora - rlData.t)) / 1000)}s)`, 1);
        return false;
    }

    rlData.n++;
    localStorage.setItem('nupieepro_rl', JSON.stringify(rlData));
    return true;
}
```

### S2 · Chave ImgBB exposta no admin

**Onde:** `admin.html`

```js
const IMGBB_KEY = '7dd10f3e634617cf6231fa3b4a3a728e';
```

Essa chave está visível no código-fonte do `admin.html` — que é um repositório **público** no GitHub Pages. Qualquer pessoa pode usar sua cota da ImgBB.

**A correção:** mover o upload de imagem para o Apps Script como proxy. O Script recebe a imagem em base64, faz o upload para a ImgBB internamente com a chave protegida no servidor, e retorna só a URL.

### S3 · Honeypot não cobre o admin

O `admin.html` não tem honeypot para formulários de pedido. O `index.html` tem, mas só no campo de nome (não cobre o formulário completo).

### S4 · CSP ausente no HTML

O `_headers` não funciona no GitHub Pages (B6). Sem CSP, XSS é possível se alguém conseguir injetar conteúdo (via nome de produto malicioso do Sheets, por exemplo). A função `san()` mitiga mas não elimina o risco.

---

## BLOCO 5 — Melhorias de UX (Não são bugs, mas ferram a experiência)

### UX1 · Usuário não sabe que o comprovante PIX não vai pelo WhatsApp

A instrução "Anexe o comprovante do PIX" dá a entender que ele vai junto com o pedido. Mas ele não vai. O usuário pode achar que enviou e o admin nunca recebe.

**A correção:** mudar o texto:
```
📎 Após enviar o pedido, mande o comprovante como imagem na conversa do WhatsApp que vai abrir.
```

### UX2 · Splash screen dura 900ms mesmo com produtos já no localStorage

Se o usuário já visitou antes e tem dados em cache, ele aguarda 900ms na tela roxa sem motivo.

```js
// Reduzir para 300ms quando há cache local:
const temCache = localStorage.getItem('nupieepro_carrinho') !== null;
setTimeout(() => { /* esconde splash */ }, temCache ? 300 : 900);
```

### UX3 · Admin não mostra feedback enquanto salva produto (sem loading state)

O botão "Publicar" fica sem indicação visual enquanto o Apps Script processa (~3s). Usuário pode clicar várias vezes.

```js
async function salvarProduto(publicar) {
    const btn = event.currentTarget; // botão clicado
    btn.disabled = true;
    btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Salvando...';
    try {
        // ...código existente...
    } finally {
        btn.disabled = false;
        btn.innerHTML = publicar
            ? '<i class="fa-solid fa-rocket"></i> Publicar'
            : '<i class="fa-solid fa-floppy-disk"></i> Salvar rascunho';
    }
}
```

### UX4 · "Meus Pedidos" mostra histórico local, não dados reais da API

Um usuário que limpou o localStorage perde todo o histórico. O histórico deveria ser buscado da API com o WhatsApp como chave.

### UX5 · Busca não tem debounce — dispara renderVitrine() a cada tecla

```js
// ATUAL:
input.addEventListener('input', function() {
    busca = this.value.trim().toLowerCase();
    renderVitrine(); // chamada em cada tecla
});

// MELHOR:
let _buscaTimer;
input.addEventListener('input', function() {
    clearTimeout(_buscaTimer);
    busca = this.value.trim().toLowerCase();
    _buscaTimer = setTimeout(() => renderVitrine(), 150); // debounce 150ms
});
```

---

## BLOCO 6 — O arquivo `_headers` / Questão de Deploy

O arquivo se chama `_headers.txt` — mas mesmo se fosse `_headers` (sem `.txt`), não funcionaria no GitHub Pages. Para ter headers de segurança reais, as opções são:

| Plataforma | Headers | Custo | Dificuldade |
|------------|---------|-------|-------------|
| **GitHub Pages** | ❌ Não suporta | Grátis | — |
| **Netlify** | ✅ `_headers` funciona | Grátis | Fácil |
| **Cloudflare Pages** | ✅ `_headers` funciona | Grátis | Fácil |
| **Vercel** | ✅ `vercel.json` | Grátis | Fácil |

**Recomendação:** migrar para **Cloudflare Pages**. É grátis, tem CDN global (carregamento mais rápido em Teresina), suporta `_headers`, e você mantém o domínio `nupieepro.github.io` com redirect ou usa um domínio custom.

---

## BLOCO 7 — Ordem de Execução das Correções

### Sessão 1 — Elimina os atrasos e bugs críticos (3–4h)
1. ✅ Parallelizar `carregarAPI()` com `Promise.allSettled` (B1)
2. ✅ Corrigir snapshot do carrinho antes de limpar (B4 + B19)
3. ✅ Criar `getPixKey()`, `getWhatsApp()`, `getRecebedor()` dinâmicos (B2 + B11)
4. ✅ Carregar cupons reais da API e limpar hardcoded (B3)
5. ✅ Login do admin: mostrar painel imediatamente, validar em background (B5)

### Sessão 2 — Confiabilidade do admin (2–3h)
6. ✅ SW Admin: network-first para admin.html (B8)
7. ✅ Invalidar cache após publicar (B17)
8. ✅ Debounce em salvarConfigToggle (B12)
9. ✅ Cache local para carregarConfig com TTL 30s (B15)
10. ✅ Loading state nos botões de salvar (UX3)

### Sessão 3 — Bugfixes médios + UX (2h)
11. ✅ Aceitar PDF no comprovante (B9)
12. ✅ Instrução clara sobre comprovante PIX no WhatsApp (B10 + UX1)
13. ✅ Corrigir polling de novos pedidos (B7)
14. ✅ Número do pedido com timestamp (B16)
15. ✅ Debounce na busca (UX5)
16. ✅ Splash screen reduzida com cache (UX2)

### Sessão 4 — Segurança + Deploy (1–2h)
17. ✅ Rate limit no localStorage (S1)
18. ✅ Remover `maskable` dos ícones até ter PNG adequado (B14)
19. ✅ Atualizar robots.txt com todos os bots de IA (B13)
20. ✅ Avaliar migração para Cloudflare Pages (B6)
21. ✅ Proxy do ImgBB pelo Apps Script (S2) — mais trabalhoso, para depois

---

## BLOCO 8 — Checklist de Verificação Pós-Correção

```
[ ] Abre a loja — produtos aparecem em menos de 3s?
[ ] Admin salva produto → loja mostra o produto em menos de 5s após reload?
[ ] Admin muda chave PIX → QR gerado com a nova chave?
[ ] Admin muda WhatsApp → pedido vai para o número novo?
[ ] Admin cria cupom → aparece na vitrine sem hardcode?
[ ] Envia pedido → histórico local tem os itens corretos?
[ ] Envia pedido → API recebe os itens (não array vazio)?
[ ] Admin abre painel → aparece em menos de 1s (sem tela de login)?
[ ] Admin ativa manutenção → loja fecha imediatamente após reload?
[ ] Comprovante PDF é aceito no upload?
[ ] Dois usuários simultâneos geram números de pedido diferentes?
[ ] SW do admin atualiza ao publicar nova versão?
```

---

## BLOCO 9 — Resumo do que criar para o Antigravity

Se for criar um sistema "Antigravity" para centralizar melhorias futuras, a estrutura sugerida é:

```
ANTIGRAVITY/
├── ANTIGRAVITY.md          ← este arquivo (auditoria master)
├── FIXES/
│   ├── F1_parallel_api.md  ← implementação da paralelização
│   ├── F2_dynamic_pix.md   ← PIX dinâmico do admin
│   ├── F3_cupons_api.md    ← cupons da API
│   └── ...
├── SESSIONS/
│   ├── SESSION_1.md        ← o que foi feito em cada sessão
│   └── ...
└── CHECKLIST.md            ← checklist de verificação
```

---

*Auditoria gerada em Abril/2026. Total de issues encontradas: 20 bugs + 5 UX + 4 segurança = 29 itens.*
*Prioridades: 🔴 CRÍTICO (6) · 🟠 ALTO (5) · 🟡 MÉDIO (7) · 🟢 BAIXO (2)*
