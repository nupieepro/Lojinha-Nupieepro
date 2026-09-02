# NUPIEEPRO STORE 🛍️

Loja oficial do **Núcleo Piauiense de Estudantes de Engenharia de Produção — NUPIEEPRO**, da Universidade Federal do Piauí (UFPI).

Site: [nupieepro.github.io/Lojinha-Nupieepro](https://nupieepro.github.io/Lojinha-Nupieepro/) · Instagram: [@nupieepro](https://www.instagram.com/nupieepro)

---

## Sobre o NUPIEEPRO

Fundado em 2015, o NUPIEEPRO dedica-se à realização de eventos, treinamentos e projetos com o objetivo de promover experiências na área de Engenharia de Produção, ampliando as oportunidades e o reconhecimento do campo no Estado do Piauí.

🏆 Duas vezes Núcleo Mais Inovador do Brasil (ABEPRO Jovem) · 🥇 Maior Núcleo do Brasil

---

## Arquitetura

Aplicação estática de dois arquivos, sem build step, servida direto pelo GitHub Pages:

| Arquivo | O que é |
|---|---|
| `index.html` | Loja — vitrine, carrinho, checkout, PIX, histórico de pedidos do cliente |
| `admin.html` | Painel administrativo — pedidos, produtos, cupons, configurações, dashboard |

Cada um é um HTML único com `<style>` e `<script>` inline (sem framework, sem bundler). Todo estado de UI vive em variáveis JS no próprio arquivo; persistência de verdade é 100% no Supabase.

**Backend:** [Supabase](https://supabase.com) (projeto `scacjsosvlllapbgetos`) — Postgres + PostgREST (API REST automática) + Auth + Storage + Realtime + Edge Functions. Toda regra de negócio que não pode ser confiada ao navegador (preço, estoque, desconto de cupom, quem é admin) vive em funções `SECURITY DEFINER` no Postgres, chamadas via RPC — o client nunca insere/atualiza tabela sensível diretamente.

**Autenticação:**
- **Loja:** anônima — qualquer visitante navega e compra, usando a `anon key` pública do Supabase.
- **Admin:** Supabase Auth real (e-mail/senha, JWT com expiração). Autorização checada em `public.admin_users` via `is_admin()`, não pela posse de uma chave.

### Estrutura de pastas

```
index.html, admin.html        — as duas aplicações
design-tokens.css             — tokens de cor/sombra/transição compartilhados entre os dois
fontawesome-subset.css        — ícones self-hosted (subset, sem CDN)
fonts/                        — Adumu (títulos) e League Spartan (corpo), self-hosted, subsetadas
icons/                        — ícones PWA em todos os tamanhos declarados nos manifests
manifest.json, admin-manifest.json  — manifests PWA (loja e admin são instaláveis separadamente)
sw.js, admin-sw.js            — service workers (cache offline, atualização automática)
vendor/                       — bibliotecas de terceiro vendorizadas (supabase-js), sem CDN
qrcode.min.js                 — geração de QR Pix 100% local
supabase/
  migrations/                 — schema e funções do banco, em ordem de aplicação (ver README ali dentro)
  functions/upload-imagem/    — Edge Function: upload de foto de produto autenticado
_headers.txt                  — headers de segurança HTTP (ver observação abaixo — hoje NÃO tem efeito)
404.html, robots.txt, sitemap.xml — SEO e página de erro (GitHub Pages serve 404.html nativamente)
```

## Rodando localmente

Sem build. Basta servir os arquivos estáticos:

```bash
python3 -m http.server 8000
# ou: npx serve .
```

Abra `http://localhost:8000/index.html` (loja) ou `/admin.html` (painel). Como é o mesmo Supabase de produção sendo consultado, cuidado ao testar fluxos que escrevem dado real (checkout, salvar produto) — prefira testar contra dados descartáveis e limpar depois.

## Hospedagem e deploy

GitHub Pages, direto da branch `main` — todo merge/push nela publica automaticamente (workflow `pages build and deployment`, alguns segundos). Não existe ambiente de staging: o que está em `main` é o que o cliente vê.

⚠️ **`_headers.txt` não tem efeito hoje.** Esse arquivo segue a convenção de headers de segurança do Netlify/Cloudflare Pages, mas o **GitHub Pages não interpreta esse arquivo** — está aqui documentado e pronto para quando a hospedagem migrar (fora do escopo atual). A única proteção de headers que *funciona* no GitHub Pages hoje é a Content-Security-Policy via `<meta http-equiv>` no `<head>` de cada HTML — `X-Frame-Options` (proteção contra clickjacking) especificamente **não tem equivalente via `<meta>`** e fica pendente até a migração de hosting.

## Banco de dados (Supabase)

Ver [`supabase/migrations/README.md`](supabase/migrations/README.md) para a lista completa de migrations, ordem de aplicação, e o que falta para o reCAPTCHA (C4) sair do modo inerte.

Resumo da postura de segurança do backend:
- **RLS (Row Level Security)** ativo em toda tabela — não existe policy de escrita direta em `pedidos`; a única forma de criar um pedido é pela RPC `criar_pedido`, que recalcula preço/estoque/desconto do zero no servidor (o navegador nunca é a fonte de verdade do que é cobrado).
- Rate limiting por IP em `criar_pedido` (server-side, não cosmético) e em `consultar_status_pedido`.
- Idempotência em `criar_pedido` — reenvio automático em caso de falha de rede não duplica o pedido.
- Admin autenticado via Supabase Auth; toda função `admin_*` checa `is_admin()` e não é executável por `anon`.
- Segredos (chave de serviço, secret key do reCAPTCHA) ficam no Supabase Vault — nunca em código ou config pública.

## Segurança

Ver [`SECURITY.md`](SECURITY.md).

---

## Contato

📸 Instagram: [@nupieepro](https://www.instagram.com/nupieepro?igsh=MWg3dGtkeG1hOTZyYQ==)

---

*Feito com 💙🧡 pelo NUPIEEPRO — UFPI*
