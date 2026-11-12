# 04 — Credenciais e acessos (Lojinha)

> **Preencher antes de enviar ao sucessor.** Nunca commitar este arquivo preenchido num repositório público. Entregar por canal seguro (gerenciador de senhas / cofre) e guardar este arquivo fora do Git depois de preenchido.

| Serviço | Endereço | Usuário / e-mail | Senha | Observações |
|---|---|---|---|---|
| GitHub (org `nupieepro`) | https://github.com/nupieepro | ____________ | ____________ | Tem 2FA? ____ |
| Supabase (org `cyyfolwjvlhnrfadoibh`) | https://supabase.com/dashboard/project/scacjsosvlllapbgetos | ____________ | ____________ | Login via Google? ____ |
| Painel admin da loja | https://nupieepro.github.io/Lojinha-Nupieepro/admin.html | ____________ | ____________ | Usuário em Auth → Users + `admin_users` |
| Gmail do projeto (`nupieeprotreinamentos@gmail.com`) | https://mail.google.com | nupieeprotreinamentos@gmail.com | ____________ | Dono do Supabase |
| Gmail financeiro (`financeironupieepro@gmail.com`) | https://mail.google.com | financeironupieepro@gmail.com | ____________ | Recebe pedidos; chave PIX atual |
| Senha de app Gmail (secret `SMTP_PASSWORD` da `resend-email`) | https://myaccount.google.com/apppasswords | (conta usada em `SMTP_USER`) | ____________ | Gerar nova ao trocar de dono |
| Instagram @nupieepro | https://instagram.com/nupieepro | ____________ | ____________ | Canal de contato de segurança |
| reCAPTCHA (futuro) | https://www.google.com/recaptcha/admin | ____________ | ____________ | Ainda não cadastrado |

## Chaves técnicas (não são senhas de login)
| Item | Onde fica | Valor/Status |
|---|---|---|
| Supabase URL | `index.html`, `admin.html` | `https://scacjsosvlllapbgetos.supabase.co` (pública) |
| Anon/publishable key | `index.html`, `admin.html` | Pública por design (embutida no HTML) |
| Service role key | Supabase → Settings → API; cópia no Vault (`service_role_key_notify_pedidos`) | **Secreta.** Valor: ____________ (guardar no cofre) |
| `SMTP_USER` / `SMTP_PASSWORD` | Edge Function `resend-email` → Secrets | ____________ |
| `recaptcha_secret_key` | Vault (ainda não existe) | ____________ |
