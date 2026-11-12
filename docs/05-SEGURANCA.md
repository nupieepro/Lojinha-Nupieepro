# 05 — Segurança (Lojinha NUPIEEPRO)

Estado em 12/11/2026. Legenda: ✅ feito · 🟡 parcial/aguardando · 🔧 exige ação sua num painel · ➖ não se aplica (site estático + Supabase, sem servidor próprio).

## 1. Implementado
| Controle | Onde | Estado |
|---|---|---|
| **SQL injection** | Cliente só chama RPC/PostgREST parametrizados. Preço, estoque e desconto são recalculados no servidor por `criar_pedido` (SECURITY DEFINER, `search_path` fixo). Não há SQL dinâmico | ✅ |
| **Fraude de preço/desconto** | O navegador nunca define o valor cobrado; sem policy de escrita em `pedidos`; só a RPC cria pedido | ✅ |
| **Idempotência / pedido duplicado** | `chave_idempotencia` em `criar_pedido` | ✅ |
| **Rate limit por IP (força bruta/abuso)** | `pedidos_rate_limit` e `consulta_status_rate_limit` no banco. Login do admin: limite nativo do Supabase Auth | ✅ |
| **Enumeração de pedidos** | `consultar_status_pedido` exige número + WhatsApp, com rate limit | ✅ |
| **Admin** | Supabase Auth (JWT) + `is_admin()` dentro de cada RPC `admin_*`; `anon` sem EXECUTE nelas (teste automático impede regressão) | ✅ |
| **XSS** | `san()` no admin. Em 12/11/2026 corrigido o painel de cupons (código e descrição sem escape, inclusive dentro de `onclick`; agora via `data-cod`) | ✅ |
| **Upload de imagem** | `upload-imagem` (v4): exige JWT de admin, valida **bytes reais** (JPEG/PNG/GIF/WebP), ignora MIME/extensão do cliente, nome aleatório, limite 8 MB, CORS só para `nupieepro.github.io`, mensagens de erro genéricas. Impede subir HTML/SVG disfarçado | ✅ |
| **Anti-tabnabbing** | `rel="noopener noreferrer"` em links externos | ✅ |
| **CSP** | `<meta>` em `index.html` e `admin.html` (sem hosts externos de script, `object-src 'none'`, `base-uri 'self'`); teste automático valida | ✅ |
| **Integridade de arquivos** | `security/integridade.sha256` (supabase-js e qrcode.min.js) verificado em `npm test` e no CI | ✅ |
| **Cofre de segredos** | Nenhum segredo no repo (teste varre chaves privadas, service_role, tokens, senha SMTP). Segredos em Supabase Vault/Secrets | ✅ |
| **SAST / dependências / scanner** | Workflow *Segurança*: CodeQL, testes de segurança, e job semanal que confere se loja e admin estão no ar e a validade do certificado. Dependabot para Actions | ✅ |
| **Divulgação responsável** | `SECURITY.md` (Instagram) | ✅ |
| **Auditoria de alterações (append-only) + monitoramento de banco** | Migration `20261112000001_auditoria_antifraude.sql`: registra mudanças em `admin_users`, `config` (PIX, e-mail, manutenção), `cupons`, preço/ativo de `produtos` e `pedidos` (status, pago). Imutável (nem service_role edita/apaga) | ✅ **aplicada em 12/11/2026** e testada no banco real (log gravado, apagar bloqueado, RPC negada sem login; triggers de e-mail/número de pedido intactos) |
| **Antifraude de pagamento** | `admin_antifraude_resumo()` (mesma migration): sinaliza WhatsApp com ≥3 pedidos em 24 h, PIX marcado pago sem comprovante, cupom reutilizado pelo mesmo WhatsApp, valor > 3× a média e **qualquer alteração de total/desconto/cupom depois de criado o pedido** | ✅ aplicada com a migration |
| **Endpoint morto desativado** | `migrar-fotos-ibb` estava ativa, sem JWT e com CORS aberto, autenticando por senha em texto puro (`config.admin_senha`, que já não existe). Trocada por stub **410 Gone**; código arquivado em `supabase/functions/_arquivadas/` | ✅ |
| **Hardening** | `search_path` fixo em `_csv_campo` e `_pedidos_numero_unico_trg` (alerta do linter) | ✅ aplicada com a migration |
| **Proteção contra CSV/Formula Injection** | `_csv_campo` neutraliza `= + - @` ao exportar | ✅ |

## 2. Itens da lista que não se aplicam
Isolamento de contêiner/servidor, resposta a ransomware, quarentena, armadilhas em servidor (não há servidor); coletor central de logs/SIEM, normalizador, correlação, inteligência de ameaças (desproporcional); triagem de phishing (sem caixa de e-mail no sistema); WAF/firewall dinâmico, anti-bot e controle de taxa de borda (o GitHub Pages não permite — ver §3).

## 3. Limitação estrutural: GitHub Pages
O GitHub Pages **não aceita headers HTTP personalizados**, então a loja não tem `X-Frame-Options`, HSTS customizado nem WAF/rate limit de borda (o `_headers.txt` do repo não tem efeito). A solução real é **migrar a hospedagem para Cloudflare Pages**, como o Sistema (o `_headers.txt` já está pronto): ganha headers, WAF, rate limit, Bot Fight Mode e Turnstile. Ao migrar, atualizar os links do Sistema (`js/app.js`) e o CORS da `upload-imagem`.

## 4. Ações suas (painéis)
1. ~~Aplicar a migration de auditoria~~ (feito). Falta só **rodar** `select public.admin_antifraude_resumo();` de vez em quando (logado como admin).
2. **Supabase → Auth:** *Leaked password protection*, MFA para o admin, senha mínima maior.
3. **reCAPTCHA v3 (ou Cloudflare Turnstile):** hoje a proteção anti-bot do checkout é só o rate limit por IP. Cadastrar o site e guardar a secret no Vault (`recaptcha_secret_key`).
4. **`resend-email`** (v9, 12/11/2026): já escapa o HTML do cliente, valida o e-mail contra injeção de cabeçalhos SMTP (CRLF) e não devolve texto de erro. **Falta**: trocar o Gmail SMTP por um provedor transacional (Resend/Brevo) com domínio autenticado (SPF/DKIM) e tirar a chave PIX fixa do código. **Atenção:** a v9 não teve envio real testado; na próxima compra, conferir se o e-mail chegou (Supabase → Edge Functions → resend-email → Logs). Se falhar, reverter para a v8 (código antigo no histórico do Git).
5. **Backup:** o plano gratuito não tem backup automático. Pro (diário/PITR) ou `pg_dump` agendado para local externo; testar restauração em projeto novo 1× por semestre. Os comprovantes (`comprovantes`) e fotos (`produtos`) também precisam de cópia.
6. **GitHub:** Secret scanning + push protection, branch protection na `main`, 2FA na organização.
7. **Admin:** manter 1–2 admins no máximo; a tabela `admin_users` tem 1 hoje.

## 5. Rotinas
| Frequência | Ação |
|---|---|
| Diária (equipe) | Conferir pedidos "pagos sem comprovante" e divergências de valor |
| Semanal | Resultado do workflow *Segurança*; alertas do Dependabot |
| Mensal | `select public.admin_seguranca_resumo();` e `select public.admin_antifraude_resumo();` logado como admin |
| Trimestral | Atualizar supabase-js e `qrcode.min.js` (ler changelog), regenerar `security/integridade.sha256`, subir `CACHE` dos service workers |
| Semestral | Teste de restauração; rotacionar service role e senha de app do Gmail |

## 6. Resposta a incidente
1. **Conter:** `manutencao` na `config` (fecha a loja) e `pausar_checkout`; remover admin suspeito de `admin_users` e *Sign out* no Supabase Auth; rotacionar service role (e atualizar o segredo do Vault `service_role_key_notify_pedidos`).
2. **Investigar:** trilha `auditoria_seguranca`, Dashboard → Logs (API/Auth/Edge Functions), `pedidos` recentes.
3. **Corrigir e restaurar** a partir de backup se necessário.
4. **LGPD:** dados de clientes (nome, WhatsApp, e-mail, endereço) vazados exigem aviso aos titulares e à ANPD.
5. Registrar a linha do tempo em uma issue.

## 7. Riscos aceitos
- Chave PIX é pública por natureza (aparece no QR).
- RPCs `criar_pedido` e `consultar_status_pedido` são públicas por design.
- reCAPTCHA inativo; e-mail do pedido depende de senha de app do Gmail.
