# 03 — Operação, deploy e rotinas (Lojinha)

## Deploy
- **GitHub Pages**, branch `main`, pasta raiz. Merge/push em `main` publica em segundos (workflow "pages build and deployment"). **Não existe staging**: o que está em `main` é o que o cliente vê. Teste localmente antes.
- Rodar local: `python3 -m http.server 8000` e abrir `http://localhost:8000/index.html` ou `/admin.html`. **Aponta para o banco de produção.** Pedido de teste vira pedido real.
- Cache: se mudar CSS/JS/imagens, incrementar `CACHE` em `sw.js` / `admin-sw.js` (hoje `nupieepro-v20`); senão usuários recebem versão antiga.
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
