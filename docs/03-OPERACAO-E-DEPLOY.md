# 03 — Operação, deploy e rotinas (Lojinha)

## Deploy
- **GitHub Pages**, branch `main`, pasta raiz. Merge/push em `main` publica em segundos (workflow "pages build and deployment"). **Não existe staging**: o que está em `main` é o que o cliente vê. Teste localmente antes.
- Rodar local: `python3 -m http.server 8000` e abrir `http://localhost:8000/index.html` ou `/admin.html`. **Aponta para o banco de produção.** Pedido de teste vira pedido real.
- Cache: se mudar CSS/JS/imagens, incrementar `CACHE` em `sw.js` / `admin-sw.js` (hoje `nupieepro-v25`); senão usuários recebem versão antiga.
- Edge Functions: `supabase functions deploy upload-imagem --project-ref scacjsosvlllapbgetos` (precisa do Supabase CLI logado).
- Migrations: colar no SQL Editor do Dashboard, na ordem do README de migrations.

## Rotinas do dia a dia (equipe financeira)
1. Abrir o `admin.html`, entrar com e-mail/senha do admin.
2. Aba **Pedidos**: conferir novos, abrir o pedido, ver o comprovante, **marcar pago**, mudar status (novo → confirmado → em produção → pronto → entregue; existem ainda os status pago e cancelado), anotar.
3. Aba **Produtos**: ajustar estoque/preço, ativar/desativar, duplicar, enviar foto.
4. Aba **Cupons**: criar/ativar/desativar.
5. Aba **Configurações**: PIX (`chave_pix`, `nome_recebedor`), WhatsApp, banners, aviso do topo, **manutenção** (fecha a loja) e **pausar checkout**.
6. Exportar CSV para a prestação de contas.

## Como fazer mudanças comuns
| Quero... | Onde |
|---|---|
| Trocar a chave PIX / recebedor | Admin → Configurações. **Além disso**, a chave PIX do e-mail está fixa em `resend-email` (constante `CHAVE_PIX`) |
| Mudar e-mail que recebe os pedidos | Admin → Configurações (`email_financeiro`) e secret `EMAIL_FINANCEIRO` da função |
| Novo cupom | Admin → Cupons (tipos existentes, incluindo `fixo_por_camisa`) |
| Novo tipo de desconto | Nova migration reescrevendo `criar_pedido` (copiar `20260903000001_...`). Faça `DROP FUNCTION` da assinatura antiga antes |
| Mudar cores/tema | Admin (tema) ou `design-tokens.css` |
| Fechar a loja temporariamente | Config `manutencao` |

## Problemas conhecidos / cuidados
- Nunca editar `criar_pedido` sem derrubar a assinatura antiga (`DROP FUNCTION`), senão fica uma versão órfã executável.
- Se o e-mail de pedido parar: conferir (a) segredo `service_role_key_notify_pedidos` no Vault (b) função `resend-email` ativa (c) secrets `SMTP_USER`/`SMTP_PASSWORD` (a senha de app do Gmail pode ser revogada) (d) logs da Edge Function.
- Se a loja ficar "vazia": já houve vazamento de sessão do admin para a loja (corrigido no commit "causa raiz do loja vazia"). Limpar cache/SW e checar a `anon key`.
- Projeto Supabase gratuito pausa por inatividade. Se a loja sumir, restaurar no Dashboard.

## Transferência de propriedade (checklist)
- [ ] Novo dono entra como Owner na organização GitHub `nupieepro`
- [ ] Novo dono entra como Owner na organização Supabase
- [ ] Trocar/atualizar e-mail e recuperação da conta Google `nupieeprotreinamentos@gmail.com`
- [ ] Criar admin novo em Auth → Users e inserir em `public.admin_users`; remover o antigo
- [ ] Rotacionar: service role key (e **atualizar o segredo do Vault `service_role_key_notify_pedidos`**), senha de app do Gmail (`SMTP_PASSWORD`)
- [ ] Registrar reCAPTCHA no nome do novo responsável

## Promoção por período (NUPI BLACK e futuras)
- Cada produto pode ter `preco_promocional`, `promo_inicio`, `promo_fim` e `promo_rotulo` (tabela `produtos`). O **servidor** decide o preço vigente pelo relógio do banco (`preco_vigente()`); a loja lê o catálogo por `listar_produtos_loja()` (já com `preco_atual`/`em_promocao`) e `criar_pedido` cobra o preço vigente. Fora da janela o preço volta ao normal sozinho.
- **Pelo painel admin (recomendado):** aba Produtos → editar o produto → bloco "🔥 Promoção por período": preço promocional, selo (ex.: NUPI BLACK), início e fim (horário de Fortaleza). Salve; para remover, deixe o preço promocional vazio e salve. A lista de produtos mostra a promoção de cada item e se está *agendada*, *no ar* ou *encerrada*. O banco confere antes de gravar (exige início e fim, fim depois do início, e preço promocional menor que o normal). Migration: `20261115000003_admin_promocao.sql`.
- Alternativa por SQL (SQL Editor): `update public.produtos set preco_promocional = 2.00, promo_inicio = timestamptz '2026-11-16 00:00:00-03', promo_fim = timestamptz '2026-11-30 23:59:59-03', promo_rotulo = 'NUPI BLACK' where id in (18,19,20,21);` (fuso de Fortaleza, -03).
- Para encerrar antes: `update public.produtos set promo_fim = now() where id in (...);`.
- Cupons **acumulam** com preço promocional (um cupom percentual vale sobre o preço já promocional). Se isso não for desejado, é preciso ajustar `criar_pedido` e `calcDesc` na loja.
- **Pendência de segurança tratada em 15/11/2026:** a coluna `produtos.custo` era legível por qualquer visitante pela API. A migration `20261115000002_ocultar_custo_do_publico_APLICAR_DEPOIS_DO_DEPLOY.sql` corrige; só aplicar depois que a loja nova (que usa `listar_produtos_loja`) estiver no ar.

## Como refazer a auditoria de acessibilidade (axe-core)
1. `python3 -m http.server 8765` na pasta do repo.
2. Em uma pasta fora do repo: `npm i axe-core@4.10.2 playwright`.
3. Com o Playwright (Chromium), abrir `http://localhost:8765/index.html`, injetar `node_modules/axe-core/axe.min.js` e rodar `await axe.run(document,{runOnly:{type:'tag',values:['wcag2a','wcag2aa','wcag21a','wcag21aa','best-practice']}})` na home, no detalhe de um produto (`abrirDetalhes(id)`), no checkout (`abrirCheckout()`) e em `abrirTermos()`.
4. Meta: 0 violações. Resultado de 15/11/2026: 0 nas quatro telas.
