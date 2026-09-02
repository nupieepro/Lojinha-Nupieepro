# Política de Segurança

A Lojinha NUPIEEPRO processa pagamentos reais via PIX e dados pessoais reais de estudantes (nome, WhatsApp, e-mail, endereço). Levamos relatos de vulnerabilidade a sério.

## Reportando uma vulnerabilidade

**Não abra uma issue pública** para falhas de segurança — isso expõe o problema antes de ele ser corrigido.

Encontrou algo que pareça uma vulnerabilidade real (não um bug comum de funcionamento)? Entre em contato direto, em privado:

📸 Instagram: [@nupieepro](https://www.instagram.com/nupieepro) (mensagem direta)

Inclua, se possível: o que você encontrou, os passos pra reproduzir, e o impacto que você acredita que isso tem. Não precisa de prova de conceito elaborada — uma descrição clara já ajuda.

## O que está fora de escopo

- Engenharia social contra membros do núcleo.
- Ataques de negação de serviço (não teste isso contra o site em produção).
- Vulnerabilidades que dependem de acesso físico a um dispositivo de outra pessoa.
- Relatos automatizados de scanners genéricos sem confirmação manual de que o achado é real e explorável.

## O que esperar

Este é um projeto mantido por estudantes, não uma empresa com equipe de segurança dedicada — não há SLA formal de resposta nem programa de recompensa (bug bounty). Ainda assim, todo relato legítimo é levado a sério e recebe retorno.

## Postura de segurança do projeto

Resumo técnico em [`README.md`](README.md#banco-de-dados-supabase). Detalhe completo de cada decisão de segurança (autenticação, validação server-side, RLS, rate limiting, CSP) está documentado nos comentários dos próprios arquivos de migration em [`supabase/migrations/`](supabase/migrations/).
