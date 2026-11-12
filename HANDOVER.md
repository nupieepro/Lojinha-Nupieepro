# HANDOVER — Lojinha NUPIEEPRO

Documento de passagem para quem assume a manutenção. Estado verificado em 12/11/2026.

## Resumo

- Site estático (`index.html` loja, `admin.html` painel), sem build. Hospedado no **GitHub Pages**, direto da `main` (merge = deploy; não há staging).
- Backend: **Supabase**, projeto `scacjsosvlllapbgetos` (nome "Lojinha", us-east-1, Postgres 17). Status: ACTIVE_HEALTHY.
- Mais detalhes técnicos: `README.md`, `SECURITY.md`, `supabase/migrations/README.md`.

## Contas e serviços (o sucessor precisa de acesso a todos)

| Serviço | Para quê | Observação |
|---|---|---|
| GitHub (org `nupieepro`) | Código e hospedagem (Pages) | Transferir ownership da org/repo |
| Supabase (org `cyyfolwjvlhnrfadoibh`) | Banco, Auth, Storage, Edge Functions | Transferir ownership da organização ou convidar como Owner |
| Conta Google do núcleo | Dona do projeto Supabase e do reCAPTCHA (futuro) | Trocar e-mail/recuperação |
| Instagram @nupieepro | Canal de contato de segurança (SECURITY.md) | |

## Edge Functions no Supabase

| Função | No repo? | Obs |
|---|---|---|
| `upload-imagem` | Sim | Upload de foto de produto (admin). Ativa, v3 |
| `resend-email` | **Não** | Existe só no Supabase (v8, verify_jwt=true). Usa Resend; precisa do secret da API. Versionar ou remover |
| `migrar-fotos-ibb` | **Não** | Migração única de fotos do ImgBB. Provavelmente descartável |

## Pendências conhecidas

1. **reCAPTCHA v3 (C4) inerte.** Cadastrar o site em google.com/recaptcha, guardar a secret no Vault (`recaptcha_secret_key`) e colocar a site key no `index.html`.
2. **`_headers.txt` sem efeito** no GitHub Pages (sem X-Frame-Options). Resolve migrando o hosting (ex.: Cloudflare Pages, como o Sistema).
3. Supabase Auth: **proteção contra senha vazada desativada** (ativar no dashboard, Auth > Passwords).
4. Funções `_pedidos_numero_unico_trg` e `_csv_campo` sem `search_path` fixo (baixo risco).
5. Extensão `pg_net` no schema `public` (mover para `extensions`).
6. Tabela `pedidos_backup_20260427`: backup antigo; avaliar apagar.
7. Aviso do linter sobre RPCs `SECURITY DEFINER` executáveis por `anon`/`authenticated` é **esperado**: `criar_pedido` e `consultar_status_pedido` são públicas por design; as `admin_*` checam `is_admin()` internamente.

## Primeiros passos para o sucessor

1. Ganhar acesso a GitHub e Supabase (acima).
2. Criar/conferir o admin em Supabase > Authentication > Users e o vínculo em `public.admin_users`.
3. Anotar o e-mail de notificação financeira e a chave PIX em uso (ficam na tabela `config`, editável em `admin.html`).
4. Rodar localmente: `python3 -m http.server 8000`. **Cuidado**: aponta para o banco de produção.
5. Resolver as pendências acima por ordem.

## Segredos

Nenhum segredo está no código (a `anon key` é pública por design). Secret keys ficam no Supabase (Vault / secrets das Edge Functions). Quem assumir deve **rotacionar** as chaves de serviço do Supabase após a troca de donos.
