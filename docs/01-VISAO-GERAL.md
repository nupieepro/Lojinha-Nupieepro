# 01 — Visão geral e arquitetura (Lojinha NUPIEEPRO)

## O que é
Loja virtual do núcleo (camisas, ecobag, bloco de notas, chaveiro, bottons etc.), usada por estudantes da UFPI. Fluxo de compra: cliente escolhe produtos, aplica cupom, preenche dados, paga por **PIX** (QR Code/copia-e-cola gerado no navegador) ou outro meio, envia o comprovante e o pedido também pode ser mandado por **WhatsApp**. A equipe financeira acompanha e confirma tudo no painel admin.

Duas aplicações, sem framework e sem build:

| Arquivo | Papel | URL em produção |
|---|---|---|
| `index.html` | Vitrine, carrinho, checkout, PIX, "Meus pedidos" | https://nupieepro.github.io/Lojinha-Nupieepro/ |
| `admin.html` | Painel: pedidos, produtos, cupons, configurações, dashboard, preview da loja | https://nupieepro.github.io/Lojinha-Nupieepro/admin.html |

> O README antigo diz `nupieepro.github.io` (raiz). **Isso está errado**: a raiz devolve 404. A loja mora no caminho `/Lojinha-Nupieepro/`.

Cada HTML tem `<style>` e `<script>` inline. Não existe `package.json`, bundler nem testes automatizados. Para alterar algo, edita-se o HTML e faz-se merge na `main`.

## Componentes
```
Navegador (cliente / admin)
   │  HTML+JS estático (GitHub Pages, branch main)
   ▼
Supabase (projeto scacjsosvlllapbgetos, "Lojinha", us-east-1)
   ├─ PostgREST/RPC  → toda regra de negócio (preço, estoque, cupom, rate limit, idempotência)
   ├─ Auth           → só o admin (e-mail/senha). Cliente é anônimo (anon key pública)
   ├─ Storage        → bucket público `produtos` (fotos), bucket privado `comprovantes`
   ├─ Edge Functions → upload-imagem (admin sobe foto), resend-email (e-mail do pedido)
   ├─ pg_net + Vault → trigger da tabela `pedidos` chama resend-email
   └─ Realtime       → admin recebe aviso de novo pedido
Gmail SMTP (via resend-email) → e-mail para o financeiro e para o cliente
WhatsApp (link wa.me)         → cliente envia o pedido pronto à equipe
```

## Arquivos do repositório
| Item | Para quê |
|---|---|
| `design-tokens.css` | Cores/sombras/transições compartilhadas por loja e admin |
| `fontawesome-subset.css`, `fonts/` | Ícones e fontes (Adumu para títulos, League Spartan para corpo) hospedados localmente, sem CDN |
| `vendor/supabase-js-2.116.0.min.js` | supabase-js vendorizado (sem CDN) |
| `qrcode.min.js` | Gera o QR do PIX no navegador |
| `manifest.json`, `admin-manifest.json` | PWA instalável (loja e admin separados) |
| `sw.js` (cache `nupieepro-v20`), `admin-sw.js` | Service workers. **Ao mudar assets, aumentar o número do cache**, senão navegadores ficam com a versão velha |
| `supabase/migrations/` | Schema e RPCs (ver `02-BANCO-E-BACKEND.md`) |
| `supabase/functions/upload-imagem/` | Edge Function de upload de foto |
| `supabase/config.toml` | Config do Supabase CLI (project_id `scacjsosvlllapbgetos`) |
| `_headers.txt` | **Sem efeito** no GitHub Pages (convenção Netlify/Cloudflare) |
| `SECURITY.md`, `LICENSE.txt` | Política de segurança e licença |

## Loja (`index.html`) — o que cada bloco faz
Funções principais (todas inline no HTML):
- **Catálogo:** `carregarAPI`/`buscarAPI` (lê produtos do Supabase), `normalizarProduto`, `filtrar`, `renderVitrine`, `criarCardProduto`, `abrirDetalhes` (modal), `renderHeroBanner` (banners da home, vindos da tabela `config`), `aplicarTema` (tema/cores vindos da config).
- **Carrinho:** `adicionarAoCarrinho`, `alterarQtd`, `renderCarrinho`, `salvarCarrinho`/`carregarCarrinho` (localStorage), `sincronizarCarrinhoComProdutos` (remove item que saiu de linha/estoque).
- **Cupom:** `validarCupom`, `autoAplicarCupom`, `atualizarBannerCupom`, `descontoUnit`. O cupom **`LF2026`** (R$ 5 por camisa) vem pré-selecionado. **O navegador só mostra o desconto; quem vale é o servidor** (`criar_pedido` recalcula).
- **Checkout:** `abrirCheckout`, `toggleEndereco`, `togglePix`, `gerarQRPix`/`gerarPayloadPix`/`copiarPix` (payload PIX EMV montado no cliente com `chave_pix`, `nome_recebedor` da config), `previewComprovante` (upload do comprovante), `enviarPedidoZap` (chama a RPC **`criar_pedido`** e abre o WhatsApp com o resumo).
- **Pós-compra:** `abrirMeusPedidos`/`verificarStatusPedido` (RPC **`consultar_status_pedido`**, exige número do pedido + WhatsApp), histórico em localStorage (`lerHist`/`salvarHist`).
- Outros: LGPD (`abrirLGPD`), compartilhar, modal "Sobre".

## Painel admin (`admin.html`)
Login por Supabase Auth (`fazerLogin`); depois `admin_verificar_sessao`/`is_admin()` confirma se o usuário está em `public.admin_users`. Abas: **Dashboard** (`admin_dashboard`), **Pedidos** (listar, abrir, mudar status, marcar pago, anotação interna, ver comprovante via URL assinada, exportar CSV, aviso de novo pedido), **Produtos** (criar/editar/duplicar/ativar, fotos por upload ou URL, margem), **Cupons**, **Configurações** (tudo da tabela `config`: nome da loja, PIX, WhatsApp, banners, avisos do topo, manutenção, pausar checkout, categorias/coleções), **Preview** (iframe da loja).

Todas as chamadas do admin passam por funções `admin_*` (SECURITY DEFINER) que checam `is_admin()` no banco. Ter a página aberta não dá poder nenhum.

## Segurança (resumo do que existe)
- RLS em todas as tabelas; **não há policy de escrita direta** em `pedidos`: só a RPC `criar_pedido` cria pedido.
- `criar_pedido` recalcula preço, estoque, desconto; tem **rate limit por IP**, **idempotência** (reenvio não duplica) e **reCAPTCHA v3 opcional** (inerte, ver pendências).
- CSP via `<meta>` nos HTMLs (clickjacking sem mitigação, pois o GitHub Pages ignora `_headers.txt`).
- `admin.html` ainda é público na URL; o que protege é o login.
