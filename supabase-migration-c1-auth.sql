-- ============================================================
-- C1 — Migração do admin para Supabase Auth de verdade
-- ============================================================
-- Elimina: config.admin_senha em texto plano, _validar_admin() comparando
-- string, e toda função admin_* recebendo senha como argumento RPC.
--
-- Substitui por: Supabase Auth (JWT real, com expiração) + tabela
-- admin_users mapeando auth.uid() -> permissão de admin, checada via
-- função is_admin().
--
-- IMPORTANTE — ORDEM DE APLICAÇÃO (ver relatório de corte):
--   1. Criar o usuário admin em Authentication → Users no Dashboard
--      (e-mail: marketingnupieepro@gmail.com, "Auto Confirm User" marcado)
--   2. Aplicar este script inteiro
--   3. Rodar a query de vínculo no final (liga o auth.users.id à admin_users)
--   4. Fazer o merge do PR para main (GitHub Pages passa a servir o
--      admin.html novo, que já usa supabase.auth.signInWithPassword)
--   Passos 2-4 devem acontecer próximos no tempo: assim que este script
--   roda, o admin.html ANTIGO (com senha em texto plano) para de funcionar
--   imediatamente, porque ele fala com o mesmo banco.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Tabela de administradores (mapeia auth.uid() -> é admin)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.admin_users (
    user_id    UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    criado_em  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'admin_users' AND policyname = 'admin_users_self_select') THEN
        -- Um admin só enxerga a própria linha — evita que a tabela vire uma lista pública de quem é admin
        CREATE POLICY "admin_users_self_select" ON public.admin_users
            FOR SELECT TO authenticated USING (user_id = auth.uid());
    END IF;
END $$;

-- Ninguém tem INSERT/UPDATE/DELETE via API nessa tabela — só o dono do projeto via SQL Editor.
REVOKE INSERT, UPDATE, DELETE ON public.admin_users FROM anon, authenticated;

-- ------------------------------------------------------------
-- 2. Helper: o usuário autenticado atual é admin?
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.admin_users au WHERE au.user_id = auth.uid()
    );
$$;

REVOKE EXECUTE ON FUNCTION public.is_admin() FROM anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

-- ------------------------------------------------------------
-- 3. Verificação de sessão (substitui admin_login — não recebe mais senha,
--    só confirma se o JWT atual pertence a um admin)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_verificar_sessao()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
    SELECT public.is_admin();
$$;

REVOKE EXECUTE ON FUNCTION public.admin_verificar_sessao() FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_verificar_sessao() TO authenticated;

-- ------------------------------------------------------------
-- 3.5 Remove as assinaturas ANTIGAS (com parâmetro "chave") antes de criar
--     as novas. CREATE OR REPLACE só substitui uma função de mesma
--     assinatura — como o parâmetro "chave" está sendo removido de todas,
--     sem este DROP explícito o Postgres criaria sobrecargas novas ao lado
--     das antigas, deixando as antigas (ainda GRANT'adas para anon) órfãs
--     no schema em vez de efetivamente substituídas.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_dashboard(TEXT);
DROP FUNCTION IF EXISTS public.admin_get_pedidos(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.admin_atualizar_pedido(TEXT, TEXT, TEXT, BOOLEAN, TEXT);
DROP FUNCTION IF EXISTS public.admin_exportar_csv(TEXT);
DROP FUNCTION IF EXISTS public.admin_get_produtos(TEXT);
DROP FUNCTION IF EXISTS public.admin_salvar_produto(TEXT, JSONB);
DROP FUNCTION IF EXISTS public.admin_get_cupons(TEXT);
DROP FUNCTION IF EXISTS public.admin_salvar_cupom(TEXT, JSONB);
DROP FUNCTION IF EXISTS public.admin_get_config(TEXT);
DROP FUNCTION IF EXISTS public.admin_salvar_config(TEXT, JSONB);

-- ------------------------------------------------------------
-- 4. Funções admin_* reescritas — sem parâmetro "chave", gate por is_admin()
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_dashboard()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_faturado      NUMERIC := 0;
    v_faturado_pago NUMERIC := 0;
    v_total         INTEGER := 0;
    v_cancelados    INTEGER := 0;
    v_hoje          INTEGER := 0;
    v_ticket        NUMERIC := 0;
    v_mais_vendido  JSONB   := NULL;
    v_pagamentos    JSONB   := '{}'::JSONB;
    v_desconto      NUMERIC := 0;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Acesso negado' USING ERRCODE = '42501';
    END IF;

    SELECT COALESCE(SUM(total), 0) INTO v_faturado FROM public.pedidos WHERE status <> 'cancelado';
    -- Recebido de verdade: só pedidos com pagamento confirmado. "Faturamento
    -- total" sozinho inflava a métrica somando pedidos ainda não pagos (achado B8).
    SELECT COALESCE(SUM(total), 0) INTO v_faturado_pago FROM public.pedidos WHERE status <> 'cancelado' AND pago = TRUE;
    SELECT COUNT(*) INTO v_total FROM public.pedidos WHERE status <> 'cancelado';
    SELECT COUNT(*) INTO v_cancelados FROM public.pedidos WHERE status = 'cancelado';
    SELECT COUNT(*) INTO v_hoje FROM public.pedidos WHERE status <> 'cancelado' AND created_at >= CURRENT_DATE;

    IF v_total > 0 THEN
        v_ticket := ROUND(v_faturado / v_total, 2);
    END IF;

    SELECT jsonb_build_object('nome', nome_prod, 'qtd', total_qtd)
    INTO v_mais_vendido
    FROM (
        SELECT item->>'nome' AS nome_prod, SUM((item->>'qtd')::INT) AS total_qtd
        FROM public.pedidos, jsonb_array_elements(itens::JSONB) AS item
        WHERE status <> 'cancelado'
        GROUP BY nome_prod
        ORDER BY total_qtd DESC
        LIMIT 1
    ) sub;

    SELECT jsonb_object_agg(pagamento, qty)
    INTO v_pagamentos
    FROM (
        SELECT pagamento, COUNT(*) AS qty
        FROM public.pedidos WHERE status <> 'cancelado'
        GROUP BY pagamento
    ) sub;

    SELECT COALESCE(SUM(desconto), 0) INTO v_desconto
    FROM public.pedidos WHERE status <> 'cancelado' AND cupom <> '';

    RETURN jsonb_build_object(
        'total_faturado',      v_faturado,
        'total_faturado_pago', v_faturado_pago,
        'total_pedidos',       v_total,
        'total_cancelados',    v_cancelados,
        'pedidos_hoje',        v_hoje,
        'ticket_medio',        v_ticket,
        'mais_vendido',        v_mais_vendido,
        'pagamentos',          COALESCE(v_pagamentos, '{}'::JSONB),
        'desconto_cupons',     v_desconto
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_get_pedidos(status TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_rows JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Acesso negado' USING ERRCODE = '42501';
    END IF;

    /* 'pago' nao e um valor de status (status nunca vira 'pago' — pagamento e a coluna
       booleana p.pago, separada). Sem este CASE, o filtro "Pago" do admin sempre
       voltava vazio: comparava status = 'pago', que nenhuma linha satisfaz. */
    SELECT jsonb_agg(row_to_json(p)::JSONB ORDER BY p.created_at DESC)
    INTO v_rows
    FROM public.pedidos p
    WHERE (
        admin_get_pedidos.status IS NULL
        OR (CASE WHEN admin_get_pedidos.status = 'pago' THEN p.pago = TRUE
                 ELSE p.status = admin_get_pedidos.status END)
    );

    RETURN COALESCE(v_rows, '[]'::JSONB);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_atualizar_pedido(
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
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Acesso negado' USING ERRCODE = '42501';
    END IF;

    UPDATE public.pedidos p SET
        status           = COALESCE(admin_atualizar_pedido.status,   p.status),
        pago             = COALESCE(admin_atualizar_pedido.pago,     p.pago),
        anotacao_interna = COALESCE(admin_atualizar_pedido.anotacao, p.anotacao_interna),
        updated_at       = NOW()
    WHERE p.numero = admin_atualizar_pedido.numero;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'erro', 'Pedido não encontrado');
    END IF;

    RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public._csv_campo(v TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    -- Neutraliza CSV/Formula Injection: campo de texto livre do cliente (nome,
    -- observacao, endereco, etc) comecando com =, +, -, @, TAB ou CR e' interpretado
    -- como formula por Excel/Sheets ao abrir o export -- pode rodar comando externo
    -- ou vazar dado. Prefixa com aspa simples pra forcar leitura como texto, e
    -- escapa aspas duplas embutidas em TODO campo (achado na auditoria B8).
    SELECT '"' || REPLACE(
        CASE WHEN v ~ '^[=+\-@\t\r]' THEN '''' || v ELSE v END,
        '"', '""'
    ) || '"'
$$;

CREATE OR REPLACE FUNCTION public.admin_exportar_csv()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_csv TEXT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Acesso negado' USING ERRCODE = '42501';
    END IF;

    SELECT 'Nº Pedido,Data,Nome,WhatsApp,Email,Entrega,Endereço,Pagamento,Status,Pago,Total,Itens,Cupom,Desconto,Anotação' || E'\n' ||
           STRING_AGG(
               public._csv_campo(numero) || ',' ||
               public._csv_campo(TO_CHAR(created_at AT TIME ZONE 'America/Fortaleza', 'DD/MM/YYYY HH24:MI')) || ',' ||
               public._csv_campo(COALESCE(nome,'')) || ',' ||
               public._csv_campo(COALESCE(whatsapp,'')) || ',' ||
               public._csv_campo(COALESCE(email,'')) || ',' ||
               public._csv_campo(COALESCE(entrega,'')) || ',' ||
               public._csv_campo(COALESCE(endereco,'')) || ',' ||
               public._csv_campo(COALESCE(pagamento,'')) || ',' ||
               public._csv_campo(COALESCE(status,'')) || ',' ||
               public._csv_campo(CASE WHEN pago THEN 'Sim' ELSE 'Não' END) || ',' ||
               public._csv_campo(total::TEXT) || ',' ||
               public._csv_campo(COALESCE((SELECT STRING_AGG(item->>'qtd' || 'x ' || (item->>'nome'), ' | ') FROM jsonb_array_elements(itens) AS item), '')) || ',' ||
               public._csv_campo(COALESCE(cupom,'')) || ',' ||
               public._csv_campo(desconto::TEXT) || ',' ||
               public._csv_campo(COALESCE(anotacao_interna,'')),
               E'\n' ORDER BY created_at DESC
           )
    INTO v_csv
    FROM public.pedidos;

    RETURN COALESCE(v_csv, '');
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_get_produtos()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Acesso negado' USING ERRCODE = '42501';
    END IF;

    -- Mesma lista de campos que a função anterior devolvia (sem created_at/updated_at,
    -- que nunca fizeram parte do contrato consumido pelo admin.html)
    SELECT jsonb_agg(
        jsonb_build_object(
            'id',              p.id,
            'nome',            p.nome,
            'descricao',       p.descricao,
            'preco',           p.preco,
            'custo',           p.custo,
            'tipo',            p.tipo,
            'categoria',       p.categoria,
            'tamanhos',        p.tamanhos,
            'imagens',         p.imagens,
            'estoque',         p.estoque,
            'destaque',        p.destaque,
            'novo',            p.novo,
            'encomenda',       p.encomenda,
            'prazo_encomenda', p.prazo_encomenda,
            'badge_extra',     p.badge_extra,
            'ativo',           p.ativo,
            'agendamento',     p.agendamento
        ) ORDER BY p.id
    )
    INTO v_result
    FROM public.produtos p;

    RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_salvar_produto(produto JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id   INT;
    v_tams TEXT;
    v_imgs TEXT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Acesso negado' USING ERRCODE = '42501';
    END IF;

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
            nome            = COALESCE(produto->>'nome',           nome),
            descricao       = COALESCE(produto->>'descricao',      descricao),
            preco           = COALESCE((produto->>'preco')::DECIMAL, preco),
            custo           = COALESCE((produto->>'custo')::DECIMAL, custo),
            tipo            = COALESCE(produto->>'tipo',           tipo),
            categoria       = COALESCE(produto->>'categoria',      categoria),
            tamanhos        = v_tams,
            imagens         = v_imgs,
            estoque         = COALESCE((produto->>'estoque')::INT, estoque),
            destaque        = COALESCE((produto->>'destaque')::BOOLEAN, destaque),
            novo            = COALESCE((produto->>'novo')::BOOLEAN, novo),
            encomenda       = COALESCE((produto->>'encomenda')::BOOLEAN, encomenda),
            prazo_encomenda = COALESCE(produto->>'prazo_encomenda', prazo_encomenda),
            badge_extra     = COALESCE(produto->>'badge_extra',    badge_extra),
            ativo           = COALESCE((produto->>'ativo')::BOOLEAN, ativo),
            agendamento     = COALESCE(produto->>'agendamento',    agendamento),
            updated_at      = NOW()
        WHERE id = v_id;
    END IF;

    RETURN jsonb_build_object('ok', TRUE);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_get_cupons()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Acesso negado' USING ERRCODE = '42501';
    END IF;

    SELECT jsonb_agg(row_to_json(c)::JSONB ORDER BY c.id)
    INTO v_result
    FROM public.cupons c;

    RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_salvar_cupom(cupom JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Acesso negado' USING ERRCODE = '42501';
    END IF;

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

CREATE OR REPLACE FUNCTION public.admin_get_config()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_cfg JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Acesso negado' USING ERRCODE = '42501';
    END IF;

    SELECT jsonb_object_agg(c.chave, c.valor) INTO v_cfg FROM public.config c;
    RETURN COALESCE(v_cfg, '{}'::JSONB);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_salvar_config(config JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    cfg_key   TEXT;
    cfg_value TEXT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Acesso negado' USING ERRCODE = '42501';
    END IF;

    FOR cfg_key IN SELECT jsonb_object_keys(admin_salvar_config.config) LOOP
        cfg_value := (admin_salvar_config.config) ->> cfg_key;
        INSERT INTO public.config (chave, valor)
        VALUES (cfg_key, cfg_value)
        ON CONFLICT ON CONSTRAINT config_pkey
        DO UPDATE SET valor = EXCLUDED.valor;
    END LOOP;

    RETURN jsonb_build_object('ok', TRUE);
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('ok', false, 'erro', SQLERRM);
END;
$$;

-- ------------------------------------------------------------
-- 5. Remove as funções antigas baseadas em senha
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_login(TEXT);
DROP FUNCTION IF EXISTS public._validar_admin(TEXT);

-- ------------------------------------------------------------
-- 6. Trava de permissões: nenhuma função admin_* é executável por anon
-- ------------------------------------------------------------
DO $$
DECLARE
    fn TEXT;
BEGIN
    FOREACH fn IN ARRAY ARRAY[
        'admin_dashboard()', 'admin_get_pedidos(text)', 'admin_atualizar_pedido(text,text,boolean,text)',
        'admin_exportar_csv()', 'admin_get_produtos()', 'admin_salvar_produto(jsonb)',
        'admin_get_cupons()', 'admin_salvar_cupom(jsonb)', 'admin_get_config()', 'admin_salvar_config(jsonb)'
    ]
    LOOP
        EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%s FROM anon', fn);
        EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO authenticated', fn);
    END LOOP;
END $$;

-- ------------------------------------------------------------
-- 7. Remove a senha em texto plano do config e simplifica a policy pública
-- ------------------------------------------------------------
DELETE FROM public.config WHERE chave = 'admin_senha';

DROP POLICY IF EXISTS "config_publico_select" ON public.config;
CREATE POLICY "config_publico_select" ON public.config
    FOR SELECT TO anon USING (TRUE);

-- ------------------------------------------------------------
-- 8. Vincula o usuário Auth ao papel de admin
--    (só funciona depois que a conta é criada em Authentication → Users
--    no Dashboard, com o e-mail marketingnupieepro@gmail.com)
-- ------------------------------------------------------------
INSERT INTO public.admin_users (user_id)
SELECT id FROM auth.users WHERE email = 'marketingnupieepro@gmail.com'
ON CONFLICT (user_id) DO NOTHING;

-- Verificação: deve retornar 1 linha se o vínculo funcionou
SELECT au.user_id, u.email, au.criado_em
FROM public.admin_users au JOIN auth.users u ON u.id = au.user_id;
