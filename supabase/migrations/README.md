# Migrations — NUPIEEPRO STORE

Schema e funções do backend Supabase (projeto `scacjsosvlllapbgetos`), em ordem de aplicação. Nomeação segue o padrão do Supabase CLI (`YYYYMMDDHHMMSS_descricao.sql`), então este diretório é compatível com `supabase db push` / `supabase migration list` caso o projeto passe a usar o CLI formalmente — hoje cada arquivo é aplicado manualmente pelo SQL Editor do Dashboard, na ordem abaixo.

## Ordem de aplicação (banco novo, do zero)

| # | Arquivo | O que faz |
|---|---------|-----------|
| 1 | `20260815000000_schema_inicial.sql` | Tabelas base (`produtos`, `pedidos`, `cupons`, `config`), RLS inicial, funções `admin_*` na versão original (com parâmetro `chave`) |
| 2 | `20260815000001_storage_bucket_produtos.sql` | Bucket público `produtos` no Storage (fotos de produto), sem policy de escrita pra anon/authenticated — upload só pela Edge Function `upload-imagem` |
| 3 | `20260823000001_c2_c3_validacao_pedidos_rate_limit.sql` | RPC `criar_pedido` (validação server-side de preço/estoque/cupom — cliente nunca é confiado), rate limit por IP, bucket privado `comprovantes` |
| 4 | `20260823000002_c4_recaptcha_v3.sql` | Estende `criar_pedido` com verificação de reCAPTCHA v3 server-side (inerte até a chave secreta ser cadastrada no Vault — ver [C4 pendente](#c4-pendente) abaixo) |
| 5 | `20260902000001_c1_supabase_auth_admin.sql` | Corta a autenticação do admin de senha em texto plano pra Supabase Auth real (JWT). Reescreve todas as funções `admin_*` sem o parâmetro `chave`, gate por `is_admin()`. **Depois de aplicar este arquivo, é preciso já ter criado a conta do admin em Authentication → Users e rodar a query de vínculo no final do script** — sem isso ninguém consegue logar no painel. |
| 6 | `20260902000002_idempotencia_criar_pedido.sql` | Estende `criar_pedido` (mais uma vez) com uma chave de idempotência — protege contra pedido duplicado se a resposta da RPC se perder por instabilidade de rede depois do servidor já ter criado o pedido |
| 7 | `20260902000003_consulta_status_pedido.sql` | RPC pública `consultar_status_pedido` — permite ao cliente ver o status atual do pedido (não só o retrato congelado do momento da compra) |

Cada arquivo 3-7 faz `DROP FUNCTION` da assinatura anterior de `criar_pedido`/`admin_*` antes de recriar — necessário porque mudar a lista de parâmetros de uma função faz o Postgres criar um *overload* novo em vez de substituir (`CREATE OR REPLACE` só troca uma função de mesma assinatura). Sem o `DROP` explícito, a versão anterior fica órfã no schema, ainda executável.

## `archive/`

Dois arquivos que **não fazem parte da sequência acima** — histórico de produção, não algo a reaplicar num banco novo:

- `20260501_seed_dados_google_sheets_executado.sql` — carga única dos dados que vieram da planilha do Google Sheets, na migração inicial da loja pro Supabase. IDs fixos; rodar de novo falha ou sobrescreve dado real.
- `20260820_hotfix_admin_pre_c1_supersedido.sql` — hotfix aplicado direto em produção (export CSV quebrado, CSV/Formula Injection, faturamento com pedido não pago) enquanto o admin ainda usava a autenticação antiga por senha, antes do corte do C1. As mesmas correções já estão dentro de `20260902000001_c1_supabase_auth_admin.sql`.

## C4 pendente

O arquivo 4 (reCAPTCHA) deixa a verificação **inerte por design** até duas coisas acontecerem, que só o dono do projeto pode fazer:

1. Registrar o site em [google.com/recaptcha/admin/create](https://www.google.com/recaptcha/admin/create) (reCAPTCHA v3, domínio `nupieepro.github.io`).
2. Guardar a **Secret Key** no Supabase Vault (`vault.create_secret(...)`, nome `recaptcha_secret_key`) — nunca em código — e adicionar a chamada de `grecaptcha.execute()` no `index.html` com a **Site Key** (pública).

Até lá, `criar_pedido` funciona normalmente sem a checagem de reCAPTCHA (ela só entra em vigor quando a secret key existe no Vault).

## Fora daqui

- `supabase/functions/upload-imagem/` — Edge Function que recebe upload de foto de produto autenticado (JWT + checagem em `admin_users`), grava no bucket com a service role.
- `supabase/config.toml` — configuração do Supabase CLI (usada se `supabase functions deploy` rodar localmente).
