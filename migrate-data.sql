-- ============================================================
-- NUPIEEPRO STORE — Migração de Dados Google Sheets → Supabase
-- Execute DEPOIS do supabase-setup.sql
-- Dashboard → SQL Editor → New query → cole e clique Run
-- ============================================================

-- ============================================================
-- 1. PRODUTOS
-- Produtos atuais da loja NUPIEEPRO
-- ============================================================

INSERT INTO public.produtos
    (id, nome, descricao, preco, custo, tipo, categoria, tamanhos, imagens, estoque, destaque, novo, encomenda, prazo_encomenda, badge_extra, ativo, created_at, agendamento)
OVERRIDING SYSTEM VALUE
VALUES
    (1, 'Camisa PRETA — Eng. Produção',
     'Camisa oficial do NUPIEEPRO. 100% algodão, corte regular. Produto feito sob encomenda.',
     40, 30, 'camisa', 'camisa',
     'P - Normal,M - Normal,G - Normal,GG - Normal,P - BBL,M - BBL,G - BBL,GG - BBL',
     'https://i.ibb.co/qFjy5phF/53-20260319-104954-0000.png',
     99, true, true, true, 'Apenas sob encomenda', '', false, '2026-03-19T15:09:13.000Z', ''),

    (2, 'Camisa BRANCA — Eng. Produção',
     'Camisa oficial do NUPIEEPRO. 100% algodão, corte regular. Produto feito sob encomenda.',
     40, 30, 'camisa', 'camisa',
     'P - Normal,M - Normal,G - Normal,GG - Normal,P - BBL,M - BBL,G - BBL,GG - BBL',
     'https://i.ibb.co/F4vzJFcQ/55-20260319-104954-0002.png',
     99, true, true, true, 'Apenas sob encomenda', '', false, '2026-03-19T14:42:29.000Z', ''),

    (3, 'Camisa AZUL — Eng. Produção',
     'Camisa oficial do NUPIEEPRO. 100% algodão, corte regular. Produto feito sob encomenda.',
     40, 30, 'camisa', 'camisa',
     'P - Normal,M - Normal,G - Normal,GG - Normal,P - BBL,M - BBL,G - BBL,GG - BBL',
     'https://i.ibb.co/gbsSX7G9/54-20260319-104954-0001.png',
     99, true, true, true, 'Apenas sob encomenda', '', false, '2026-03-19T14:40:48.000Z', ''),

    (4, 'Ecobag Nupieepro',
     'Ecobag resistente com a identidade visual do NUPIEEPRO.',
     22, 10, 'unico', 'acessorio', '',
     'https://i.ibb.co/LhQ6gTYK/IMG-20260320-WA0034.jpg',
     20, false, false, false, '', '', true, '2026-03-21T14:32:00.000Z', ''),

    (5, 'Bloco de Notas',
     'Bloco de notas personalizado com a marca do NUPIEEPRO.',
     15, 6, 'unico', 'acessorio', '',
     'https://i.ibb.co/d3xZ9Hz/IMG-20260320-WA0035.jpg',
     30, false, false, false, '', '', true, '2026-03-21T14:32:35.000Z', ''),

    (6, 'Chaveiro Abridor',
     'Chaveiro abridor personalizado NUPIEEPRO. Prático e estiloso!',
     4, 1, 'unico', 'acessorio', '',
     'https://i.ibb.co/Z6TYmTPT/IMG-20260320-WA0033.jpg',
     50, false, false, false, '', '', true, '2026-03-21T14:33:24.000Z', ''),

    (7, 'Bottons personalizados',
     'Botton personalizado com a identidade do NUPIEEPRO.',
     3, 2, 'unico', 'acessorio',
     'Logo Nupieepro,Engenheiro de planilhas,Just-in-time,Engenharia de Produção,Foco em resultados',
     'https://i.ibb.co/21cJTrk4/Whats-App-Image-2026-03-21-at-18-22-55.jpg',
     44, true, true, false, '', '', true, '2026-03-21T18:28:06.000Z', ''),

    (8, 'Botton modelo 1 (cópia) (cópia)',
     'Botton personalizado com a identidade do NUPIEEPRO.',
     3, 2, 'unico', 'acessorio',
     'Nupieepro,Engenheiro de planilhas,Just-in-time,Foco em resultados,Engenharia de produção',
     '',
     44, true, true, false, '', '', false, '2026-03-21T18:19:52.000Z', ''),

    (9, 'Botton modelo 1 (cópia) (cópia) (cópia)',
     'Botton personalizado com a identidade do NUPIEEPRO.',
     3, 2, 'unico', 'acessorio',
     'Nupieepro,Engenheiro de planilhas,Just-in-time,Foco em resultados,Engenharia de produção',
     '',
     44, true, true, false, '', '', false, '2026-03-21T18:20:05.000Z', ''),

    (10, 'Botton modelo 1 (cópia) (cópia) (cópia) (cópia)',
     'Botton personalizado com a identidade do NUPIEEPRO.',
     3, 2, 'unico', 'acessorio',
     'Nupieepro,Engenheiro de planilhas,Just-in-time,Foco em resultados,Engenharia de produção',
     '',
     44, true, true, false, '', '', false, '2026-03-21T18:29:23.000Z', ''),

    (11, 'Botton modelo 1 (cópia) (cópia) (cópia) (cópia) (cópia)',
     'Botton personalizado com a identidade do NUPIEEPRO.',
     3, 2, 'unico', 'acessorio',
     'Nupieepro,Engenheiro de planilhas,Just-in-time,Foco em resultados,Engenharia de produção',
     'https://i.ibb.co/Kp1d6sTy/fdhdhdhdf.jpg',
     44, true, true, false, '', '', false, '2026-03-21T21:12:44.000Z', '')

ON CONFLICT (id) DO NOTHING;

-- Atualiza a sequência para continuar após ID 11
SELECT setval('public.produtos_id_seq', (SELECT MAX(id) FROM public.produtos));


-- ============================================================
-- 2. CUPONS
-- ============================================================

INSERT INTO public.cupons (codigo, tipo, valor, minimo, limite, usos, descricao, produtos_restringidos, ativo, created_at)
VALUES
    ('CALOUROEP10', 'percentual', 10, 0, 42, 2,
     'Comece sua jornada na Engenharia de Produção com 10% de desconto em produtos como chaveiro, ecobag e bloco de notas.',
     '4,5,2006', true, '2026-03-19T11:09:11.000Z'),

    ('DESCONTO15NUPI', 'percentual', 15, 0, 500, 0,
     '',
     '4,5,6,7,8,9,10,11', true, '2026-04-27T07:40:57.000Z')
ON CONFLICT (codigo) DO UPDATE SET
    tipo = EXCLUDED.tipo,
    valor = EXCLUDED.valor,
    minimo = EXCLUDED.minimo,
    limite = EXCLUDED.limite,
    usos = EXCLUDED.usos,
    descricao = EXCLUDED.descricao,
    produtos_restringidos = EXCLUDED.produtos_restringidos,
    ativo = EXCLUDED.ativo,
    created_at = EXCLUDED.created_at;


-- ============================================================
-- 3. CONFIGURAÇÕES DO GOOGLE SHEETS
-- (ON CONFLICT atualiza os valores existentes)
-- ============================================================

INSERT INTO public.config (chave, valor) VALUES
    ('nome_loja',            'NUPIEEPRO STORE'),
    ('chave_pix',            'financeironupieepro@gmail.com'),
    ('nome_recebedor',       'NUPIEEPRO'),
    ('whatsapp',             '5586999976226'),
    ('email_financeiro',     'financeironupieepro@gmail.com'),
    ('mensagem_boas_vindas', 'Bem-vindo(a), Nupilover!'),
    ('sub_marca',            'Núcleo Piauiense de Estudantes de Engenharia de Produção'),
    ('link_instagram',       'https://www.instagram.com/nupieepro?igsh=MWg3dGtkeG1hOTZyYQ=='),
    ('rodape_whatsapp',      'Prazo de confirmação: 24h úteis.'),
    ('manutencao',           'false'),
    ('pausar_checkout',      'false'),
    ('aviso_topo_texto',     ''),
    ('aviso_topo_tipo',      'info'),
    ('aviso_topo_ativo',     'false'),
    ('banner_1_img',         ''),
    ('banner_1_link',        ''),
    ('banner_1_ativo',       'false'),
    ('banner_2_img',         ''),
    ('banner_2_link',        ''),
    ('banner_2_ativo',       'false'),
    ('banner_3_img',         ''),
    ('banner_3_link',        ''),
    ('banner_3_ativo',       'false')
ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;


-- ============================================================
-- 4. PEDIDOS HISTÓRICOS
-- Dados atuais dos logs da loja
-- ============================================================

-- -- INSERT INTO public.pedidos
--     (numero, nome, whatsapp, email, entrega, endereco, pagamento, observacao, itens, subtotal, desconto, cupom, total, status, pago, anotacao, created_at)
/* VALUES

-- -- Pedidos históricos
-- -- (valores comentados para evitar erro de sintaxe)

-- ('2026-001', '19/03/2026, 10:55:35', 'novo', false, 'Rayan', '86999880958', '', 'Retirada UFPI', '', 'PIX', '[{"id":6,"nome":"Chaveiro Abridor","descricao":"Chaveiro abridor personalizado NUPIEEPRO. Prático e estiloso!","preco":4,"tipo":"unico","categoria":"acessorio","tamanhos":[],"imagens":["https://i.ibb.co/Kj00Xbys/unnamed-5.png"],"estoque":50,"destaque":false,"novo":false,"encomenda":false,"prazo_encomenda":"","badge_extra":"","img":"https://i.ibb.co/Kj00Xbys/unnamed-5.png","tamanho":"Único","qtd":1}]', 4, 0.4, 'CALOUROEP10', 3.6, '', ''),

-- ('2026-001', '19/03/2026, 11:14:52', 'novo', false, 'Raissa', '89999811929', '', 'Retirada UFPI', '', 'PIX', '[{"id":7,"nome":"Botton Personalizado","preco":3,"tipo":"unico","categoria":"acessorio","img":"https://i.ibb.co/mrsm95Kv/1769766015274.png","descricao":"Botton personalizado NUPIEEPRO.","tamanhos":[],"estoque":100,"destaque":false,"encomenda":false,"tamanho":"Único","qtd":1},{"id":6,"nome":"Chaveiro Abridor","preco":4,"tipo":"unico","categoria":"acessorio","img":"https://i.ibb.co/Kj00Xbys/unnamed-5.png","descricao":"Chaveiro abridor personalizado NUPIEEPRO.","tamanhos":[],"estoque":50,"destaque":false,"encomenda":false,"tamanho":"Único","qtd":1}]', 7, 0.4, 'CALOUROEP10', 6.6, '', ''),

-- ('2026-002', '19/03/2026, 11:18:01', 'cancelado', false, 'Raissa', '89999811929', '', 'Retirada UFPI', '', 'PIX', '[{"id":1,"nome":"Camisa PRETA — Eng. Produção","preco":40,"tipo":"camisa","categoria":"camisa","img":"https://i.ibb.co/TDhnM6xW/unnamed.png","descricao":"Camisa oficial do NUPIEEPRO. 100% algodão.","tamanhos":["P - Normal","M - Normal","G - Normal","GG - Normal","P - BBL","M - BBL","G - BBL","GG - BBL"],"estoque":99,"destaque":true,"encomenda":true,"prazo_encomenda":"Apenas sob encomenda","tamanho":"M - BBL","qtd":1},{"id":2,"nome":"Camisa BRANCA — Eng. Produção","descricao":"Camisa oficial do NUPIEEPRO. 100% algodão, corte regular. Produto feito sob encomenda.","preco":40,"tipo":"camisa","categoria":"camisa","tamanhos":["P - Normal","M - Normal","G - Normal","GG - Normal","P - BBL","M - BBL","G - BBL","GG - BBL"],"imagens":["https://i.ibb.co/bM9mqjXS/unnamed-1.png"],"estoque":99,"destaque":false,"novo":false,"encomenda":true,"prazo_encomenda":"Apenas sob encomenda","badge_extra":"","img":"https://i.ibb.co/bM9mqjXS/unnamed-1.png","tamanho":"M - Normal","qtd":1},{"id":3,"nome":"Camisa AZUL — Eng. Produção","descricao":"Camisa oficial do NUPIEEPRO. 100% algodão, corte regular. Produto feito sob encomenda.","preco":40,"tipo":"camisa","categoria":"camisa","tamanhos":["P - Normal","M - Normal","G - Normal","GG - Normal","P - BBL","M - BBL","G - BBL","GG - BBL"],"imagens":["https://i.ibb.co/qLzdtvkN/unnamed-2.png"],"estoque":99,"destaque":false,"novo":false,"encomenda":true,"prazo_encomenda":"Apenas sob encomenda","badge_extra":"","img":"https://i.ibb.co/qLzdtvkN/unnamed-2.png","tamanho":"GG - BBL","qtd":1},{"id":4,"nome":"Ecobag Nupieepro","descricao":"Ecobag resistente com a identidade visual do NUPIEEPRO.","preco":22,"tipo":"unico","categoria":"acessorio","tamanhos":[],"imagens":["https://i.ibb.co/7dj3kxt0/unnamed-3.png"],"estoque":20,"destaque":false,"novo":false,"encomenda":false,"prazo_encomenda":"","badge_extra":"","img":"https://i.ibb.co/7dj3kxt0/unnamed-3.png","tamanho":"Único","qtd":1},{"id":5,"nome":"Bloco de Notas","descricao":"Bloco de notas personalizado com a marca do NUPIEEPRO.","preco":15,"tipo":"unico","categoria":"acessorio","tamanhos":[],"imagens":["https://i.ibb.co/hxxnxrbF/unnamed-4.png"],"estoque":30,"destaque":false,"novo":false,"encomenda":false,"prazo_encomenda":"","badge_extra":"","img":"https://i.ibb.co/hxxnxrbF/unnamed-4.png","tamanho":"Único","qtd":1},{"id":6,"nome":"Chaveiro Abridor","descricao":"Chaveiro abridor personalizado NUPIEEPRO. Prático e estiloso!","preco":4,"tipo":"unico","categoria":"acessorio","tamanhos":[],"imagens":["https://i.ibb.co/Kj00Xbys/unnamed-5.png"],"estoque":50,"destaque":false,"novo":false,"encomenda":false,"prazo_encomenda":"","badge_extra":"","img":"https://i.ibb.co/Kj00Xbys/unnamed-5.png","tamanho":"Único","qtd":1},{"id":7,"nome":"Botton Personalizado","descricao":"Botton personalizado com a identidade do NUPIEEPRO.","preco":3,"tipo":"unico","categoria":"acessorio","tamanhos":[],"imagens":["https://drive.google.com/file/d/1bU77pRAONquHB-KkHEhENp9Zor-KzU9j/view?usp=drivesdk"],"estoque":48,"destaque":false,"novo":true,"encomenda":false,"prazo_encomenda":"","badge_extra":"","img":"https://drive.google.com/file/d/1bU77pRAONquHB-KkHEhENp9Zor-KzU9j/view?usp=drivesdk","tamanho":"Único","qtd":1}]', 164, 0, '', 164, '', ''),

-- ('2026-001', '21/03/2026, 16:28:03', 'novo', false, 'Ana Lívia', '98970217504', '', 'Retirada UFPI', '', 'Dinheiro', '[{"id":7,"nome":"Botton Personalizado","descricao":"Botton personalizado com a identidade do NUPIEEPRO.","preco":3,"tipo":"unico","categoria":"acessorio","tamanhos":["Nupieepro","Engenheiro de planilhas","Just-in-time","Foco em resultados","Engenharia de produção"],"imagens":["https://i.ibb.co/21jz3XfN/IMG-20260319-WA0049.jpg"],"estoque":44,"destaque":true,"novo":true,"encomenda":false,"prazo_encomenda":"","badge_extra":"","img":"https://i.ibb.co/21jz3XfN/IMG-20260319-WA0049.jpg","tamanho":"Único","qtd":1}]', 3, 0, '', 3, '', ''),

-- ('2026-003', '21/03/2026, 17:09:16', 'novo', false, 'Pedro Lucas', '8699906647', '', 'Retirada UFPI', '', 'Cartão', '[{"id":3,"nome":"Camisa AZUL — Eng. Produção","descricao":"Camisa oficial do NUPIEEPRO. 100% algodão, corte regular. Produto feito sob encomenda.","preco":40,"tipo":"camisa","categoria":"camisa","tamanhos":["P - Normal","M - Normal","G - Normal","GG - Normal","P - BBL","M - BBL","G - BBL","GG - BBL"],"imagens":["https://i.ibb.co/gbsSX7G9/54-20260319-104954-0001.png"],"estoque":99,"destaque":true,"novo":true,"encomenda":true,"prazo_encomenda":"Apenas sob encomenda","badge_extra":"","img":"https://i.ibb.co/gbsSX7G9/54-20260319-104954-0001.png","tamanho":"G - BBL","qtd":1}]', 40, 0, '', 40, '', ''),

-- ('2026-001', '21/03/2026, 17:34:45', 'novo', false, 'LUIS HENRIQUE MENDES OLIVEIRA', '5586981816467', 'henrique14luis@outlook.com.br', 'Retirada UFPI', '', 'Cartão', '[{"id":7,"nome":"Botton Personalizado","descricao":"Botton personalizado com a identidade do NUPIEEPRO.","preco":3,"tipo":"unico","categoria":"acessorio","tamanhos":["Nupieepro","Engenheiro de planilhas","Just-in-time","Foco em resultados","Engenharia de produção"],"imagens":["https://i.ibb.co/21jz3XfN/IMG-20260319-WA0049.jpg"],"estoque":44,"destaque":true,"novo":true,"encomenda":false,"prazo_encomenda":"","badge_extra":"","img":"https://i.ibb.co/21jz3XfN/IMG-20260319-WA0049.jpg","tamanho":"Único","qtd":1}]', 3, 0, '', 3, '', ''),

-- ('2026-002', '21/03/2026, 17:37:51', 'novo', false, 'LUIS HENRIQUE MENDES OLIVEIRA', '5586981816467', 'henrique14luis@outlook.com.br', 'Retirada UFPI', '', 'Dinheiro', '[{"id":5,"nome":"Bloco de Notas","descricao":"Bloco de notas personalizado com a marca do NUPIEEPRO.","preco":15,"tipo":"unico","categoria":"acessorio","tamanhos":[],"imagens":["https://i.ibb.co/d3xZ9Hz/IMG-20260320-WA0035.jpg"],"estoque":30,"destaque":false,"novo":false,"encomenda":false,"prazo_encomenda":"","badge_extra":"","img":"https://i.ibb.co/d3xZ9Hz/IMG-20260320-WA0035.jpg","tamanho":"Único","qtd":1},{"id":4,"nome":"Ecobag Nupieepro","descricao":"Ecobag resistente com a identidade visual do NUPIEEPRO.","preco":22,"tipo":"unico","categoria":"acessorio","tamanhos":[],"imagens":["https://i.ibb.co/LhQ6gTYK/IMG-20260320-WA0034.jpg"],"estoque":20,"destaque":false,"novo":false,"encomenda":false,"prazo_encomenda":"","badge_extra":"","img":"https://i.ibb.co/LhQ6gTYK/IMG-20260320-WA0034.jpg","tamanho":"Único","qtd":1},{"id":6,"nome":"Chaveiro Abridor","descricao":"Chaveiro abridor personalizado NUPIEEPRO. Prático e estiloso!","preco":4,"tipo":"unico","categoria":"acessorio","tamanhos":[],"imagens":["https://i.ibb.co/Z6TYmTPT/IMG-20260320-WA0033.jpg"],"estoque":50,"destaque":false,"novo":false,"encomenda":false,"prazo_encomenda":"","badge_extra":"","img":"https://i.ibb.co/Z6TYmTPT/IMG-20260320-WA0033.jpg","tamanho":"Único","qtd":1}]', 41, 0, '', 41, '', ''),

-- ('2026-001', '21/03/2026, 17:59:39', 'novo', false, 'MARIA LIMA SOUSA', '558699414611', 'Wal3c@yahoo.com.br', 'Entrega', 'QUADRA 105 CASA 06', 'Dinheiro', '[]', 295, 0, '', 295, '', ''),

-- ('2026-002', '21/03/2026, 18:31:56', 'novo', false, 'MARIA LIMA SOUSA', '558699414611', 'Wal3c@yahoo.com.br', 'Retirada UFPI', 'QUADRA 105 CASA 06', 'Cartão', '[]', 21, 0, '', 21, '', ''),

-- ('2026-004', '21/03/2026, 19:18:14', 'novo', false, 'Luiz Alves', '86999597740', '', 'Retirada UFPI', '', 'Dinheiro', '[]', 80, 0, '', 80, '', ''),

-- ('2026-001', '22/03/2026, 09:23:17', 'novo', false, 'Suzane', '99984660913', '', 'Retirada UFPI', '', 'Dinheiro', '[]', 40, 0, '', 40, '', ''),

-- ('2026-005', '22/03/2026, 09:26:12', 'novo', false, 'Suzane', '5599984660913', '', 'Retirada UFPI', '', 'Dinheiro', '[]', 40, 0, '', 40, '', ''),

-- ('2026-001', '23/03/2026, 14:14:19', 'novo', false, 'Davi Costa Leal', '86994362690', 'davicostaleal@gmail.com', 'Retirada UFPI', '', 'PIX', '[]', 12, 0, '', 12, '', ''),

-- ('2026-001', '23/03/2026, 14:16:40', 'novo', false, 'Maria Victoria Alves de Carvalho', '8688877139', '', 'Retirada UFPI', '', 'PIX', '[]', 3, 0, '', 3, '', ''),

-- ('2026-002', '23/03/2026, 15:59:54', 'novo', false, 'Rayan', '86999880958', '', 'Retirada UFPI', '', 'PIX', '[]', 6, 0, '', 6, '', ''),

-- ('2026-001', '23/03/2026, 20:08:32', 'novo', false, 'José Alves da Silva Neto', '5586981397222', 'joose.neto52@gmail.com', 'Retirada UFPI', '', 'PIX', '[]', 43, 0, '', 43, '', ''),

-- ('2026-001', '23/03/2026, 21:03:12', 'novo', false, 'Sérgio Alves Da Silva', '86988108118', '', 'Retirada UFPI', '', 'PIX', '[]', 40, 0, '', 40, '', ''),

-- ('2026-001', '23/03/2026, 21:48:46', 'novo', false, 'Marcus Vinicius Pereira Brito', '86988211486', '10marcusvini123@gmail.com', 'Retirada UFPI', '', 'PIX', '[]', 68, 0, '', 68, '', ''),

-- ('2026-001', '25/03/2026, 09:34:05', 'novo', false, 'Açucena Macedo', '99984763701', 'acucenaguimaraesdema@gmail.com', 'Retirada UFPI', '', 'PIX', '[]', 40, 0, '', 40, '', ''),

-- ('2026-001', '25/03/2026, 17:59:33', 'novo', false, 'Patrícia Pereira', '86999294292', 'patypm2004@gmail.com', 'Retirada UFPI', '', 'PIX', '[]', 43, 0, '', 43, '', ''),

-- ('2026-001', '28/03/2026, 16:40:48', 'novo', false, 'Nicolas Desidério Costa Olivei', '86988043610', '', 'Retirada UFPI', '', 'PIX', '[]', 22, 0, '', 22, '', ''),

-- ('2026-001', '28/03/2026, 22:30:12', 'novo', false, 'Sarinne Lima Guimarães', '99991918637', 'sarinnel@gmail.com', 'Retirada UFPI', '', 'PIX', '[]', 40, 0, '', 40, '', ''),

-- ('2026-006', '31/03/2026, 14:58:34', 'novo', false, 'Nara Luiza', '99984669451', '', 'Retirada UFPI', '', 'Dinheiro', '[]', 40, 0, '', 40, '', ''),

-- ('2026-007', '31/03/2026, 15:24:24', 'novo', false, 'João Pedro Pláci', '99988499007', '', 'Retirada UFPI', '', 'Dinheiro', '[]', 43, 0, '', 43, '', ''),

-- ('2026-008', '31/03/2026, 19:48:48', 'novo', false, 'Max', '0', '', 'Retirada UFPI', '', 'Dinheiro', '[]', 10, 0, '', 10, '', 'Já foi entregue.'),

-- ('2026-001', '03/04/2026, 18:48:59', 'novo', false, 'Chrislanne Emanuelle da Silva Santos', '86988758555', 'chrislanne.santos@ufpi.edu.br', 'Retirada UFPI', '', 'PIX', '[]', 40, 0, '', 40, '', ''),

-- ('2026-001', '03/04/2026, 20:25:53', 'novo', false, 'Chrislanne Emanuelle da Silva Santos', '86988758555', 'chrislanne.santos@ufpi.edu.br', 'Retirada UFPI', '', 'PIX', '[]', 9, 0, '', 9, '', ''),

-- ('2026-002', '05/04/2026, 17:56:08', 'novo', false, 'Chrislanne Emanuelle da Silva Santos', '86988758555', 'chrislanne.santos@ufpi.edu.br', 'Retirada UFPI', '', 'PIX', '[]', 40, 0, '', 40, '', ''),

-- ('2026-001', '05/04/2026, 21:08:39', 'novo', false, 'Bárbara Moura', '86994194071', 'barbaraamourasantoss@gmail.com', 'Retirada UFPI', '', 'PIX', '[]', 40, 0, '', 40, '', ''),

-- ('2026-001', '06/04/2026, 09:35:48', 'novo', false, 'Ronnald Silva', '86995831427', 'ronnaldsilva514@gmail.com', 'Retirada UFPI', '', 'PIX', '[]', 40, 0, '', 40, '', ''),

-- ('2026-001', '08/04/2026, 13:39:36', 'novo', false, 'Maria Eduarda Oliveira Silva', '86995106695', 'meduarda.olis13@gmail.com', 'Retirada UFPI', '', 'PIX', '[]', 40, 0, '', 40, '', ''),

-- ('2026-001-581', '17/04/2026, 22:52:47', 'novo', false, 'Micaele da Silva Leal', '89994156754', 'lealmicaele4@gmail.com', 'Retirada UFPI', '', 'Dinheiro', '[{"id":2,"nome":"Bloco de Notas","preco":15,"tipo":"unico","categoria":"acessorio","img":"https://i.ibb.co/bxrKScQ/IMG-20260321-WA0026.jpg","descricao":"Bloco de notas personalizado NUPIEEPRO.","tamanhos":[],"estoque":30,"destaque":false,"encomenda":false,"tamanho":"Único","qtd":1},{"id":4,"nome":"Botton Personalizado","preco":3,"tipo":"botton","categoria":"acessorio","img":"https://i.ibb.co/8ggFsfXq/IMG-20260319-WA0050.jpg","descricao":"Botton personalizado NUPIEEPRO. Escolha o design desejado.","tamanhos":[],"tipos_botton":["Logo NUPIEEPRO","Engenharia de Produção","Símbolo Engrenagem","Just-in-Time","Foco em Resultados"],"estoque":100,"destaque":false,"encomenda":false,"tamanho":"Foco em Resultados","qtd":2}]', 21, 0, '', 21, '', ''),

-- ('2026-009-376', '23/04/2026, 15:39:06', 'novo', false, 'Maria', '89981073467', '', 'Retirada UFPI', '', 'Dinheiro', '[{"id":3,"nome":"Chaveiro Abridor","preco":4,"tipo":"unico","categoria":"acessorio","img":"https://i.ibb.co/7JVsZwxg/IMG-20260321-WA0027.jpg","descricao":"Chaveiro abridor personalizado NUPIEEPRO.","tamanhos":[],"estoque":50,"destaque":false,"encomenda":false,"tamanho":"Único","qtd":1}]', 4, 0, '', 4, '', ''),

-- ('2026-001-360', '27/04/2026, 00:48:21', 'novo', false, 'mkbn', '3189977485', '', 'Retirada UFPI', '', 'PIX', '[{"id":3,"nome":"Chaveiro Abridor","preco":4,"tipo":"unico","categoria":"acessorio","img":"https://i.ibb.co/7JVsZwxg/IMG-20260321-WA0027.jpg","descricao":"Chaveiro abridor personalizado NUPIEEPRO.","tamanhos":[],"estoque":50,"destaque":false,"encomenda":false,"tamanho":"Único","qtd":1}]', 4, 0, '', 4, '', '')

*/ -- ON CONFLICT (numero) DO NOTHING;


-- ============================================================
-- PRONTO!
-- Resultado esperado:
--   produtos: 11 (3 camisas ativas + 8 acessórios)
--   cupons:   2 (CALOUROEP10 + DESCONTO15NUPI)
--   config:   25 configurações da loja
--   pedidos:  35 históricos
--   config:   valores completos do GS
-- ============================================================
