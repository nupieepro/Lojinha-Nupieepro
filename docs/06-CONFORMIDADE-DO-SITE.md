# 06 — Conformidade do site (lista dos 17 pontos + extras)

Estado em 15/11/2026, na loja (`index.html`). Legenda: ✅ feito e testado · 🟡 feito, mas depende de decisão/validação sua · ➖ não se aplica.
Este documento **não é parecer jurídico**: os pontos 🟡 devem ser validados por um advogado ou contador do núcleo.

| # | Ponto | Estado | Como está |
|---|---|---|---|
| 1 | Política de privacidade | ✅ | Janela "Privacidade e Proteção de Dados" (rodapé e checkout): quem é o responsável, dados coletados, finalidade e base legal (LGPD art. 7º, V), com quem os dados passam (Supabase, Google/Gmail, WhatsApp), cookies, retenção e direitos (art. 18) |
| 2 | Termos de serviço | ✅ | Janela "Termos de compra": quem vende, como comprar, preços e promoções, estoque, cartão (NFC, acréscimo informado no pagamento), retirada/entrega |
| 3 | Aviso de cookies | ➖ | A loja **não usa cookies nem rastreadores**. Guarda só sacola, pedidos e dados de preenchimento no aparelho (localStorage), e isso está dito na política. Sem cookies de terceiros, o aviso não é necessário |
| 4 | Política de reembolso/troca | 🟡 | Janela "Trocas e devoluções": 7 dias de arrependimento, 30 dias para defeito, encomenda só por defeito. **Os prazos são escolha padrão** (seguem o CDC) e precisam ser confirmados pelo núcleo |
| 5 | Formulários na LGPD | ✅ | Aviso "Ao enviar o pedido você concorda com Termos, Privacidade e Trocas" antes do botão, com links. Base legal é a execução da compra, então não exige caixa de consentimento separada |
| 6 | Só dados necessários | ✅ | E-mail é opcional; endereço só se escolher entrega; comprovante só no PIX; sem CPF, sem data de nascimento |
| 7 | Scripts de tracking | ✅ | Nenhum (sem Analytics, Pixel, etc.). Fontes, ícones e bibliotecas são locais (sem CDN) |
| 8 | Acessibilidade | ✅ | **axe-core 4.10 (WCAG 2.0/2.1 A e AA + boas práticas): 0 violações** na home, detalhe do produto, checkout e termos. Ver §Testes. Teste com leitor de tela real continua recomendado |
| 9 | Alt nas imagens | ✅ | Todas as `<img>` têm `alt`; um teste automático impede regressão |
| 10 | Contraste | ✅ | Corrigido para AA (4,5:1). O laranja da marca (#f85900) com texto branco dava 3,3:1; texto pequeno agora usa #c84800 (mesma identidade, tom mais fechado). Cinza dos textos de apoio e verdes/vermelhos dos selos também ajustados. Título grande e decorativos mantêm a cor original |
| 11 | Navegação por teclado | ✅ | Link "Pular para o conteúdo", foco visível (anel azul), Esc fecha só a janela do topo, o foco entra na janela ao abrir e volta ao botão ao fechar, o fundo fica inerte com janela aberta, barra da sacola acessível por Enter/Espaço |
| 12 | Sem avaliações falsas | ✅ | A loja não tem avaliações |
| 13 | Sem promessas falsas | 🟡 | O "De" é o preço de tabela real do produto. **Confirmar** que R$ 3, R$ 16 e R$ 20 eram os preços praticados antes da promoção (evita a prática de "preço de de" inflado). A promoção tem data de fim e termina sozinha; as mudanças de preço ficam na trilha `auditoria_seguranca` |
| 14 | Copyright das imagens | 🟡 | A animação do destaque é código original (as referências de logomarcas **não** foram copiadas). Conferir: licença da fonte **Adumu** (a League Spartan e o Font Awesome são livres, e Font Awesome pede manter o aviso de licença no arquivo de ícones), e as fotos dos produtos |
| 15 | Dados da empresa | 🟡 | Sem CNPJ/CPF, o site se identifica como "NUPIEEPRO, organização estudantil sem fins lucrativos da UFPI", com contato no Instagram. Se um dia houver CNPJ, inserir na janela de Termos e na de Privacidade |
| 16 | Conformidade LGPD | 🟡 | Declarados: responsável, finalidade, base legal, operadores, retenção, direitos. **Falta**: definir um prazo numérico de retenção (hoje "pelo tempo necessário para entregar e prestar contas"), nomear uma pessoa responsável por atender pedidos de titulares e manter uma lista simples das operações de tratamento |
| 17 | Riscos jurídicos | 🟡 | Pontos a validar: acréscimo no cartão (a legislação permite preços diferentes por meio de pagamento se informado de forma clara; o site avisa), prazos de arrependimento, e a entidade sem CNPJ vendendo (consultar um advogado/contador) |

## Extras além da lista
- Segurança do banco e da loja: `docs/05-SEGURANCA.md` (preço decidido no servidor, rate limit, auditoria imutável, antifraude, upload validado, custo do produto fora da API pública).
- Preço nunca vem do navegador: o pedido envia só `id`, `qtd` e `tamanho`; o servidor calcula (testado).
- Promoção encerra sozinha (relógio do banco), e a loja reconfere o catálogo a cada 5 min e ao voltar para a aba.
- Movimento reduzido: quem desativa animações no aparelho vê o destaque parado (sem pulsar, sem brilho).

## Testes que travam regressão (rodam no CI)
`npm test` verifica, entre outros: um único `<main>` que **não** engloba as janelas, link de pular, todas as janelas com `role`/`aria-label`, todas as imagens com `alt`, e que `criar_pedido` não recebe preço do cliente.
Auditoria completa de acessibilidade (reexecutável): abrir a loja, injetar o `axe-core` e rodar `axe.run()` nas 4 telas; o procedimento usado em 15/11/2026 está descrito em `docs/03-OPERACAO-E-DEPLOY.md`.
