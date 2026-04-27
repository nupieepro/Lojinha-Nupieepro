-- ============================================================
-- NUPIEEPRO STORE — Supabase Setup
-- Execute este arquivo inteiro no SQL Editor do Supabase
-- Dashboard → SQL Editor → New query → cole e clique Run
-- ============================================================

-- ============================================================
-- 1. TABELAS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.config (
    chave TEXT PRIMARY KEY,
    valor TEXT DEFAULT ''
);

CREATE TABLE IF NOT EXISTS public.produtos (
    id             SERIAL PRIMARY KEY,
    nome           TEXT NOT NULL DEFAULT '',
    descricao      TEXT DEFAULT '',
    preco          DECIMAL(10,2) DEFAULT 0,
    custo          DECIMAL(10,2) DEFAULT 0,
    tipo           TEXT DEFAULT 'unico',
    categoria      TEXT DEFAULT 'acessorio',
    tamanhos       TEXT DEFAULT '',
    imagens        TEXT DEFAULT '',
    estoque        INT DEFAULT 0,
    destaque       BOOLEAN DEFAULT FALSE,
    novo           BOOLEAN DEFAULT FALSE,
    encomenda      BOOLEAN DEFAULT FALSE,
    prazo_encomenda TEXT DEFAULT '',
    badge_extra    TEXT DEFAULT '',
    ativo          BOOLEAN DEFAULT TRUE,
    agendamento    TEXT DEFAULT '',
    created_at     TIMESTAMPTZ DEFAULT NOW(),
    updated_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.cupons (
    id                    SERIAL PRIMARY KEY,
    codigo                TEXT UNIQUE NOT NULL,
    tipo                  TEXT DEFAULT 'percentual',
    valor                 DECIMAL(10,2) DEFAULT 0,
    minimo                DECIMAL(10,2) DEFAULT 0,
    limite                INT DEFAULT 500,
    usos                  INT DEFAULT 0,
    descricao             TEXT DEFAULT '',
    produtos_restringidos TEXT DEFAULT '',
    ativo                 BOOLEAN DEFAULT TRUE,
    created_at            TIMESTAMPTZ DEFAULT NOW(),
    updated_at            TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.pedidos (
    id         SERIAL PRIMARY KEY,
    numero     TEXT UNIQUE NOT NULL,
    nome       TEXT DEFAULT '',
    whatsapp   TEXT DEFAULT '',
    email      TEXT DEFAULT '',
    entrega    TEXT DEFAULT '',
    endereco   TEXT DEFAULT '',
    pagamento  TEXT DEFAULT '',
    observacao TEXT DEFAULT '',
    itens      JSONB DEFAULT '[]',
    subtotal   DECIMAL(10,2) DEFAULT 0,
    desconto   DECIMAL(10,2) DEFAULT 0,
    cupom      TEXT DEFAULT '',
    total      DECIMAL(10,2) DEFAULT 0,
    status     TEXT DEFAULT 'novo',
    pago       BOOLEAN DEFAULT FALSE,
    anotacao   TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 2. HABILITAR REALTIME (mudanças propagadas instantaneamente)
-- ============================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'produtos') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.produtos;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'cupons') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.cupons;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'config') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.config;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'pedidos') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.pedidos;
    END IF;
END $$;

-- ============================================================
-- 3. ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE public.produtos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cupons   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.config   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pedidos  ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'produtos' AND policyname = 'produtos_publico_select') THEN
        CREATE POLICY "produtos_publico_select" ON public.produtos
            FOR SELECT TO anon USING (ativo = TRUE);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'cupons' AND policyname = 'cupons_publico_select') THEN
        CREATE POLICY "cupons_publico_select" ON public.cupons
            FOR SELECT TO anon USING (ativo = TRUE);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'config' AND policyname = 'config_publico_select') THEN
        CREATE POLICY "config_publico_select" ON public.config
            FOR SELECT TO anon USING (chave != 'admin_senha');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'pedidos' AND policyname = 'pedidos_publico_insert') THEN
        CREATE POLICY "pedidos_publico_insert" ON public.pedidos
            FOR INSERT TO anon WITH CHECK (TRUE);
    END IF;
END $$;

-- ============================================================
-- 4. HELPER: VALIDAÇÃO DA SENHA DO ADMIN
-- ============================================================

CREATE OR REPLACE FUNCTION public._validar_admin(p_senha TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_senha TEXT;
BEGIN
    SELECT valor INTO v_senha FROM public.config WHERE chave = 'admin_senha';
    IF v_senha IS NULL OR p_senha IS DISTINCT FROM v_senha THEN
        RAISE EXCEPTION 'Acesso negado';
    END IF;
END;
$$;

-- ============================================================
-- 5. FUNÇÕES RPC DO ADMIN (todas validam a senha antes de agir)
-- ============================================================

-- LOGIN
CREATE OR REPLACE FUNCTION public.admin_login(chave TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._validar_admin(chave);
    RETURN TRUE;
EXCEPTION WHEN OTHERS THEN
    RETURN FALSE;
END;
$$;

-- DASHBOARD
CREATE OR REPLACE FUNCTION public.admin_dashboard(chave TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_total_faturado  DECIMAL;
    v_total_pedidos   INT;
    v_pedidos_hoje    INT;
    v_ticket_medio    DECIMAL;
    v_mais_vendido    JSONB;
    v_total_cancelados INT;
    v_desconto_cupons DECIMAL;
    v_pagamentos      JSONB;
BEGIN
    PERFORM public._validar_admin(chave);

    SELECT COALESCE(SUM(total),0)            INTO v_total_faturado  FROM public.pedidos WHERE status != 'cancelado';
    SELECT COUNT(*)                           INTO v_total_pedidos   FROM public.pedidos;
    SELECT COUNT(*)                           INTO v_pedidos_hoje    FROM public.pedidos WHERE created_at::date = CURRENT_DATE;
    SELECT COALESCE(AVG(total),0)             INTO v_ticket_medio    FROM public.pedidos WHERE status != 'cancelado';
    SELECT COUNT(*)                           INTO v_total_cancelados FROM public.pedidos WHERE status = 'cancelado';
    SELECT COALESCE(SUM(desconto),0)          INTO v_desconto_cupons FROM public.pedidos WHERE cupom != '' AND status != 'cancelado';

    SELECT jsonb_build_object('nome', nome, 'qtd', qtd) INTO v_mais_vendido
    FROM (
        SELECT item->>'nome' AS nome, SUM((item->>'qtd')::INT) AS qtd
        FROM public.pedidos, jsonb_array_elements(itens) AS item
        WHERE status != 'cancelado'
        GROUP BY item->>'nome'
        ORDER BY qtd DESC
        LIMIT 1
    ) t;

    SELECT jsonb_object_agg(pagamento, cnt) INTO v_pagamentos
    FROM (
        SELECT pagamento, COUNT(*) AS cnt
        FROM public.pedidos WHERE status != 'cancelado'
        GROUP BY pagamento
    ) t;

    RETURN jsonb_build_object(
        'total_faturado',   v_total_faturado,
        'total_pedidos',    v_total_pedidos,
        'pedidos_hoje',     v_pedidos_hoje,
        'ticket_medio',     v_ticket_medio,
        'mais_vendido',     v_mais_vendido,
        'total_cancelados', v_total_cancelados,
        'desconto_cupons',  v_desconto_cupons,
        'pagamentos',       COALESCE(v_pagamentos, '{}'::JSONB)
    );
END;
$$;

-- LISTAR PEDIDOS
CREATE OR REPLACE FUNCTION public.admin_get_pedidos(chave TEXT, status TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    PERFORM public._validar_admin(chave);

    SELECT jsonb_agg(
        jsonb_build_object(
            'numero',     p.numero,
            'nome',       p.nome,
            'whatsapp',   p.whatsapp,
            'email',      p.email,
            'entrega',    p.entrega,
            'endereco',   p.endereco,
            'pagamento',  p.pagamento,
            'observacao', p.observacao,
            'itens',      p.itens,
            'subtotal',   p.subtotal,
            'desconto',   p.desconto,
            'cupom',      p.cupom,
            'total',      p.total,
            'status',     p.status,
            'pago',       p.pago,
            'anotacao',   p.anotacao,
            'data',       TO_CHAR(p.created_at AT TIME ZONE 'America/Fortaleza', 'DD/MM/YYYY HH24:MI')
        ) ORDER BY p.created_at DESC
    )
    INTO v_result
    FROM public.pedidos p
    WHERE (admin_get_pedidos.status IS NULL OR p.status = admin_get_pedidos.status);

    RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;

-- ATUALIZAR PEDIDO
CREATE OR REPLACE FUNCTION public.admin_atualizar_pedido(
    chave    TEXT,
    numero   TEXT,
    status   TEXT    DEFAULT NULL,
    pago     BOOLEAN DEFAULT NULL,
    anotacao TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._validar_admin(chave);

    UPDATE public.pedidos p SET
        status     = COALESCE(admin_atualizar_pedido.status,   p.status),
        pago       = COALESCE(admin_atualizar_pedido.pago,     p.pago),
        anotacao   = COALESCE(admin_atualizar_pedido.anotacao, p.anotacao),
        updated_at = NOW()
    WHERE p.numero = admin_atualizar_pedido.numero;

    RETURN jsonb_build_object('ok', TRUE);
END;
$$;

-- EXPORTAR CSV
CREATE OR REPLACE FUNCTION public.admin_exportar_csv(chave TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_csv TEXT;
BEGIN
    PERFORM public._validar_admin(chave);

    SELECT 'Nº Pedido,Data,Nome,WhatsApp,Email,Entrega,Endereço,Pagamento,Status,Pago,Total,Itens,Cupom,Desconto,Anotação' || E'\n' ||
           STRING_AGG(
               '"' || numero || '",' ||
               '"' || TO_CHAR(created_at AT TIME ZONE 'America/Fortaleza', 'DD/MM/YYYY HH24:MI') || '",' ||
               '"' || COALESCE(nome,'') || '",' ||
               '"' || COALESCE(whatsapp,'') || '",' ||
               '"' || COALESCE(email,'') || '",' ||
               '"' || COALESCE(entrega,'') || '",' ||
               '"' || REPLACE(COALESCE(endereco,''), '"', '""') || '",' ||
               '"' || COALESCE(pagamento,'') || '",' ||
               '"' || COALESCE(status,'') || '",' ||
               '"' || (CASE WHEN pago THEN 'Sim' ELSE 'Não' END) || '",' ||
               '"' || total::TEXT || '",' ||
               '"' || COALESCE((SELECT STRING_AGG(item->>'qtd' || 'x ' || item->>'nome', ' | ') FROM jsonb_array_elements(itens) AS item), '') || '",' ||
               '"' || COALESCE(cupom,'') || '",' ||
               '"' || desconto::TEXT || '",' ||
               '"' || REPLACE(COALESCE(anotacao,''), '"', '""') || '"',
               E'\n' ORDER BY created_at DESC
           )
    INTO v_csv
    FROM public.pedidos;

    RETURN COALESCE(v_csv, '');
END;
$$;

-- LISTAR PRODUTOS (admin vê todos, ativos e inativos)
CREATE OR REPLACE FUNCTION public.admin_get_produtos(chave TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    PERFORM public._validar_admin(chave);

    SELECT jsonb_agg(
        jsonb_build_object(
            'id',             p.id,
            'nome',           p.nome,
            'descricao',      p.descricao,
            'preco',          p.preco,
            'custo',          p.custo,
            'tipo',           p.tipo,
            'categoria',      p.categoria,
            'tamanhos',       p.tamanhos,
            'imagens',        p.imagens,
            'estoque',        p.estoque,
            'destaque',       p.destaque,
            'novo',           p.novo,
            'encomenda',      p.encomenda,
            'prazo_encomenda',p.prazo_encomenda,
            'badge_extra',    p.badge_extra,
            'ativo',          p.ativo,
            'agendamento',    p.agendamento
        ) ORDER BY p.id
    )
    INTO v_result
    FROM public.produtos p;

    RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;

-- SALVAR PRODUTO (insert ou update)
CREATE OR REPLACE FUNCTION public.admin_salvar_produto(chave TEXT, produto JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id      INT;
    v_tams    TEXT;
    v_imgs    TEXT;
BEGIN
    PERFORM public._validar_admin(chave);

    -- Normaliza arrays JS → texto separado por vírgula
    v_tams := CASE
        WHEN jsonb_typeof(produto->'tamanhos') = 'array'
        THEN (SELECT STRING_AGG(v, ',') FROM jsonb_array_elements_text(produto->'tamanhos') AS v)
        ELSE COALESCE(produto->>'tamanhos', '')
    END;

    v_imgs := CASE
        WHEN jsonb_typeof(produto->'imagens') = 'array'
        THEN (SELECT STRING_AGG(v, ',') FROM jsonb_array_elements_text(produto->'imagens') AS v)
        ELSE COALESCE(produto->>'imagens', '')
    END;

    v_id := NULLIF((produto->>'id')::TEXT, '')::INT;

    IF v_id IS NULL THEN
        INSERT INTO public.produtos (
            nome, descricao, preco, custo, tipo, categoria,
            tamanhos, imagens, estoque, destaque, novo, encomenda,
            prazo_encomenda, badge_extra, ativo, agendamento, updated_at
        ) VALUES (
            produto->>'nome',
            COALESCE(produto->>'descricao', ''),
            COALESCE((produto->>'preco')::DECIMAL, 0),
            COALESCE((produto->>'custo')::DECIMAL, 0),
            COALESCE(produto->>'tipo', 'unico'),
            COALESCE(produto->>'categoria', 'acessorio'),
            v_tams,
            v_imgs,
            COALESCE((produto->>'estoque')::INT, 0),
            COALESCE((produto->>'destaque')::BOOLEAN, FALSE),
            COALESCE((produto->>'novo')::BOOLEAN, FALSE),
            COALESCE((produto->>'encomenda')::BOOLEAN, FALSE),
            COALESCE(produto->>'prazo_encomenda', ''),
            COALESCE(produto->>'badge_extra', ''),
            COALESCE((produto->>'ativo')::BOOLEAN, TRUE),
            COALESCE(produto->>'agendamento', ''),
            NOW()
        );
    ELSE
        UPDATE public.produtos SET
            nome             = COALESCE(produto->>'nome',           nome),
            descricao        = COALESCE(produto->>'descricao',      descricao),
            preco            = COALESCE((produto->>'preco')::DECIMAL, preco),
            custo            = COALESCE((produto->>'custo')::DECIMAL, custo),
            tipo             = COALESCE(produto->>'tipo',           tipo),
            categoria        = COALESCE(produto->>'categoria',      categoria),
            tamanhos         = v_tams,
            imagens          = v_imgs,
            estoque          = COALESCE((produto->>'estoque')::INT, estoque),
            destaque         = COALESCE((produto->>'destaque')::BOOLEAN, destaque),
            novo             = COALESCE((produto->>'novo')::BOOLEAN, novo),
            encomenda        = COALESCE((produto->>'encomenda')::BOOLEAN, encomenda),
            prazo_encomenda  = COALESCE(produto->>'prazo_encomenda', prazo_encomenda),
            badge_extra      = COALESCE(produto->>'badge_extra',    badge_extra),
            ativo            = COALESCE((produto->>'ativo')::BOOLEAN, ativo),
            agendamento      = COALESCE(produto->>'agendamento',    agendamento),
            updated_at       = NOW()
        WHERE id = v_id;
    END IF;

    RETURN jsonb_build_object('ok', TRUE);
END;
$$;

-- LISTAR CUPONS
CREATE OR REPLACE FUNCTION public.admin_get_cupons(chave TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    PERFORM public._validar_admin(chave);

    SELECT jsonb_agg(row_to_json(c)::JSONB ORDER BY c.id)
    INTO v_result
    FROM public.cupons c;

    RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;

-- SALVAR CUPOM (insert ou update)
CREATE OR REPLACE FUNCTION public.admin_salvar_cupom(chave TEXT, cupom JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public._validar_admin(chave);

    INSERT INTO public.cupons (codigo, tipo, valor, minimo, limite, usos, descricao, ativo, updated_at)
    VALUES (
        UPPER(cupom->>'codigo'),
        COALESCE(cupom->>'tipo',              'percentual'),
        COALESCE((cupom->>'valor')::DECIMAL,  0),
        COALESCE((cupom->>'minimo')::DECIMAL, 0),
        COALESCE((cupom->>'limite')::INT,     500),
        COALESCE((cupom->>'usos')::INT,       0),
        COALESCE(cupom->>'descricao',         ''),
        COALESCE((cupom->>'ativo')::BOOLEAN,  TRUE),
        NOW()
    )
    ON CONFLICT (codigo) DO UPDATE SET
        tipo       = EXCLUDED.tipo,
        valor      = EXCLUDED.valor,
        minimo     = EXCLUDED.minimo,
        limite     = EXCLUDED.limite,
        usos       = EXCLUDED.usos,
        descricao  = EXCLUDED.descricao,
        ativo      = EXCLUDED.ativo,
        updated_at = NOW();

    RETURN jsonb_build_object('ok', TRUE);
END;
$$;

-- OBTER CONFIGURAÇÕES
CREATE OR REPLACE FUNCTION public.admin_get_config(chave TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    PERFORM public._validar_admin(chave);

    SELECT jsonb_object_agg(c.chave, c.valor) INTO v_result
    FROM public.config c
    WHERE c.chave != 'admin_senha';

    RETURN COALESCE(v_result, '{}'::JSONB);
END;
$$;

-- SALVAR CONFIGURAÇÕES (atualização parcial por chave)
CREATE OR REPLACE FUNCTION public.admin_salvar_config(chave TEXT, config JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_key TEXT;
    v_val TEXT;
BEGIN
    PERFORM public._validar_admin(chave);

    FOR v_key, v_val IN SELECT * FROM jsonb_each_text(config) LOOP
        -- Protege a chave de senha — só pode ser alterada diretamente no banco
        IF v_key = 'admin_senha' THEN CONTINUE; END IF;
        INSERT INTO public.config AS cfg (chave, valor)
        VALUES (v_key, v_val)
        ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;
    END LOOP;

    RETURN jsonb_build_object('ok', TRUE);
END;
$$;

-- ============================================================
-- 6. DADOS INICIAIS
-- ============================================================

-- IMPORTANTE: Troque 'SUA_SENHA_AQUI' pela senha do admin atual
INSERT INTO public.config (chave, valor) VALUES ('admin_senha', 'nupi@admin2025')
ON CONFLICT (chave) DO NOTHING;

-- Configurações padrão da loja (ajuste conforme necessário)
INSERT INTO public.config (chave, valor) VALUES
    ('nome_loja',            'NUPIEEPRO STORE'),
    ('mensagem_boas_vindas', 'Produtos oficiais do NUPIEEPRO — UFPI!'),
    ('chave_pix',            'financeiro.nupieepro@gmail.com'),
    ('nome_recebedor',       'NUPIEEPRO'),
    ('whatsapp',             '5586999976226'),
    ('manutencao',           'false'),
    ('pausar_checkout',      'false')
ON CONFLICT (chave) DO NOTHING;

-- ============================================================
-- PRONTO! Agora atualize SUPABASE_URL e SUPABASE_ANON_KEY
-- em index.html e admin.html com os valores do seu projeto.
-- Encontre-os em: Supabase Dashboard → Settings → API
-- ============================================================
