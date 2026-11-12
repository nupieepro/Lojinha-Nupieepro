# 02 — Banco de dados e backend (Lojinha)

Projeto Supabase **`scacjsosvlllapbgetos`** ("Lojinha"), organização `cyyfolwjvlhnrfadoibh`, região us-east-1, Postgres 17. Estado em 12/11/2026: 9 produtos, 55 pedidos (último em 28/10/2026), 5 cupons, 1 admin.

## Tabelas (schema `public`)
| Tabela | Conteúdo |
|---|---|
| `produtos` | Catálogo (nome, preço, estoque, tamanhos, fotos, categoria/coleção, ativo) |
| `pedidos` | Pedidos. Colunas: `numero`, `nome`, `whatsapp`, `email`, `entrega`, `endereco`, `pagamento`, `observacao`, `itens` (jsonb), `subtotal`, `desconto`, `cupom`, `total`, `status`, `pago`, `anotacao`, `anotacao_interna`, `comprovante_path`, `chave_idempotencia`, timestamps |
| `cupons` | Cupons (inclui tipo `fixo_por_camisa`; `LF2026` = R$ 5 por camisa) |
| `config` | Chave/valor (`chave`,`valor`). Chaves em uso: `nome_loja`, `sub_marca`, `chave_pix`, `nome_recebedor`, `whatsapp`, `rodape_whatsapp`, `link_instagram`, `email_financeiro`, `mensagem_boas_vindas`, `hero_*`, `banner_1..3_{ativo,img,link}`, `aviso_topo_{ativo,tipo,texto}`, `categorias_produtos`, `manutencao`, `pausar_checkout`, `recaptcha_min_score`, `_last_update` |
| `admin_users` | Quem é admin (vínculo com `auth.users`) |
| `pedidos_rate_limit`, `consulta_status_rate_limit` | Controle de abuso por IP |
| `pedidos_backup_20260427` | Backup antigo (candidata a apagar) |

## RPCs públicas (executáveis por `anon`, por design)
- `criar_pedido(p_nome, p_whatsapp, p_email, p_entrega, p_endereco, p_pagamento, p_observacao, p_itens, p_cupom_codigo, p_comprovante_path, p_recaptcha_token, p_chave_idempotencia)`
- `consultar_status_pedido(p_numero, p_whatsapp)`

## RPCs de admin (exigem `is_admin()`)
`admin_verificar_sessao`, `admin_dashboard`, `admin_get_pedidos(status)`, `admin_atualizar_pedido(numero,status,pago,anotacao)`, `admin_exportar_csv`, `admin_get_produtos`, `admin_salvar_produto`, `admin_get_cupons`, `admin_salvar_cupom`, `admin_get_config`, `admin_salvar_config`, `is_admin`.
O linter do Supabase marca todas como "SECURITY DEFINER executável por authenticated". Isso é esperado: cada uma verifica `is_admin()` por dentro.

## Migrations (ordem de aplicação em banco novo)
Ver `supabase/migrations/README.md`. Resumo: schema inicial → bucket `produtos` → validação server-side + rate limit (C2/C3) → reCAPTCHA (C4, inerte) → migração do admin para Supabase Auth (C1) → idempotência → consulta de status → cupom LF2026. Elas são aplicadas **manualmente no SQL Editor** (não há CI de banco).

**Itens que existem no banco de produção e NÃO estão nas migrations do repo** (quem recriar o banco do zero precisa refazer):
1. Triggers em `pedidos`: `trg_pedidos_email_insert`, `trg_pedidos_email_update` (chamam `_notify_email_on_pedidos()`) e `trg_pedidos_numero_unico` (`_pedidos_numero_unico_trg()`).
2. Função `public._notify_email_on_pedidos()` (SECURITY DEFINER): lê o segredo `service_role_key_notify_pedidos` do **Vault** e faz `net.http_post` para `https://scacjsosvlllapbgetos.supabase.co/functions/v1/resend-email` com `{event, record}`.
3. Extensão `pg_net` (instalada em `public`; ideal mover para `extensions`).
4. Segredo no Vault `service_role_key_notify_pedidos` (a service role key do projeto).
5. Edge Function `resend-email` e `migrar-fotos-ibb` (ver abaixo).

## Edge Functions
| Função | Repo? | Função |
|---|---|---|
| `upload-imagem` | sim | Admin envia foto de produto. Valida JWT + `admin_users`, tipos jpeg/png/webp/gif, até 8 MB, grava no bucket `produtos` com service role. `verify_jwt=false` na plataforma (a checagem é feita dentro) |
| `resend-email` | **não** (só no Supabase, v8) | Chamada pelo trigger. No INSERT de pedido envia e-mail ao financeiro e, se houver, ao cliente, via **Gmail SMTP (smtp.gmail.com:465)**. Secrets necessários: `SMTP_USER`, `SMTP_PASSWORD` (senha de app do Gmail); opcionais `EMAIL_FINANCEIRO` (padrão financeironupieepro@gmail.com), `NOME_LOJA`. A chave PIX do e-mail está **fixa no código**. O HTML do e-mail interpola `nome` do cliente sem escapar (risco baixo de HTML injection no e-mail) |
| `migrar-fotos-ibb` | **não** | Migração única de fotos do ImgBB para o Storage. Provavelmente descartável |

> Cópia do código do `resend-email`: baixar com `supabase functions download resend-email --project-ref scacjsosvlllapbgetos` e versionar em `supabase/functions/resend-email/`.

## Storage
- `produtos` (público): fotos de produto. Escrita só pela Edge Function.
- `comprovantes` (privado): comprovantes enviados pelo cliente; o admin vê por URL assinada.

## reCAPTCHA v3 (C4) — estado
Inerte. Falta cadastrar o site em google.com/recaptcha (v3), guardar a **Secret Key** no Vault com o nome `recaptcha_secret_key` (hoje o Vault só tem `service_role_key_notify_pedidos`) e colocar a **Site Key** no `index.html` com `grecaptcha.execute()`. `recaptcha_min_score` já existe na `config`.

## Advisors do Supabase (12/11/2026)
Sem críticos. Avisos: `_pedidos_numero_unico_trg` e `_csv_campo` sem `search_path` fixo; `pg_net` em `public`; proteção de senha vazada desligada no Auth; RLS sem policy em `pedidos`, `*_rate_limit` e backup (intencional: só as RPCs acessam).
