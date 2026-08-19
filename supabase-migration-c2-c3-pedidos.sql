-- ============================================================
-- C2 — Validação server-side de pedidos
-- C3 — Rate limiting real no servidor
-- + Correção: comprovante de PIX era exigido do cliente e depois descartado
--   (nunca era enviado nem salvo — o admin não tinha como conferir o
--   pagamento que o próprio site exigia como comprovante)
-- ============================================================
-- Substitui o INSERT direto do client em public.pedidos (WITH CHECK TRUE,
-- preço/desconto/total calculados no navegador) por uma única RPC
-- SECURITY DEFINER que:
--   1. Aplica rate limit por IP no servidor (o rlOk() atual é só
--      localStorage — burlável limpando o navegador)
--   2. Recalcula subtotal a partir de public.produtos (nunca confia no
--      preço enviado pelo client)
--   3. Confere estoque real e debita atomicamente (evita overselling)
--   4. Valida e aplica cupom inteiramente no servidor
--   5. Salva o caminho do comprovante de pagamento (bucket privado,
--      só admin lê)
--
-- Depende de C1 já estar aplicado (usa public.is_admin() na policy de
-- leitura do bucket de comprovantes). Aplicar tudo junto no cutover.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Novas colunas em pedidos
-- ------------------------------------------------------------
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS comprovante_path TEXT DEFAULT '';

-- ------------------------------------------------------------
-- 2. CHECK constraints — dados obrigatórios não podem mais chegar vazios
--    direto pela API (hoje qualquer INSERT anon passava, sem nenhuma
--    validação de formato/obrigatoriedade no banco)
-- ------------------------------------------------------------
ALTER TABLE public.pedidos
    DROP CONSTRAINT IF EXISTS pedidos_nome_obrigatorio,
    ADD  CONSTRAINT pedidos_nome_obrigatorio CHECK (nome <> ''),
    DROP CONSTRAINT IF EXISTS pedidos_whatsapp_formato,
    ADD  CONSTRAINT pedidos_whatsapp_formato CHECK (whatsapp ~ '^[0-9]{10,13}$'),
    DROP CONSTRAINT IF EXISTS pedidos_itens_nao_vazio,
    ADD  CONSTRAINT pedidos_itens_nao_vazio CHECK (jsonb_typeof(itens) = 'array' AND jsonb_array_length(itens) > 0),
    DROP CONSTRAINT IF EXISTS pedidos_valores_nao_negativos,
    ADD  CONSTRAINT pedidos_valores_nao_negativos CHECK (subtotal >= 0 AND desconto >= 0 AND total >= 0);

-- ------------------------------------------------------------
-- 3. Rate limit por IP (tabela interna — nenhum acesso direto via API)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pedidos_rate_limit (
    ip            TEXT PRIMARY KEY,
    janela_inicio TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    contagem      INT NOT NULL DEFAULT 0
);
ALTER TABLE public.pedidos_rate_limit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pedidos_rate_limit FROM anon, authenticated;

-- ------------------------------------------------------------
-- 4. Bucket privado para comprovantes de pagamento
--    (upload liberado pro cliente durante o checkout; leitura só pra
--    admin — diferente do bucket "produtos", que é público de propósito)
-- ------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('comprovantes', 'comprovantes', false)
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='comprovantes_anon_insert') THEN
        CREATE POLICY "comprovantes_anon_insert" ON storage.objects
            FOR INSERT TO anon WITH CHECK (bucket_id = 'comprovantes');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='comprovantes_admin_select') THEN
        CREATE POLICY "comprovantes_admin_select" ON storage.objects
            FOR SELECT TO authenticated USING (bucket_id = 'comprovantes' AND public.is_admin());
    END IF;
END $$;

-- ------------------------------------------------------------
-- 5. RPC criar_pedido — único caminho de escrita em pedidos daqui pra frente
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.criar_pedido(
    p_nome             TEXT,
    p_whatsapp         TEXT,
    p_email            TEXT,
    p_entrega          TEXT,
    p_endereco         TEXT,
    p_pagamento        TEXT,
    p_observacao       TEXT,
    p_itens            JSONB,           -- [{"id":1,"qtd":2,"tamanho":"M"}, ...]
    p_cupom_codigo     TEXT DEFAULT NULL,
    p_comprovante_path TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ip           TEXT;
    v_janela       TIMESTAMPTZ;
    v_contagem     INT;
    v_item         JSONB;
    v_produto      RECORD;
    v_qtd          INT;
    v_subtotal     NUMERIC := 0;
    v_snapshot     JSONB   := '[]'::JSONB;
    v_cupom        RECORD;
    v_cupom_aplicado TEXT;    -- nome do cupom só é setado se um cupom válido foi usado;
                              -- v_cupom (RECORD) não pode ser lido fora do bloco onde foi
                              -- atribuído — um RECORD nunca populado nem tem campos, e
                              -- acessar v_cupom.codigo nesse estado derruba a função com
                              -- "record is not assigned yet" (quebraria todo pedido sem cupom)
    v_restrito     INT[];
    v_base_desc    NUMERIC := 0;
    v_desconto     NUMERIC := 0;
    v_total        NUMERIC := 0;
    v_numero       TEXT;
    v_id           INT;
BEGIN
    ----------------------------------------------------------------
    -- Rate limit: 5 pedidos a cada 10 minutos por IP (mesma regra que
    -- já existia no client, agora impossível de burlar limpando o navegador)
    ----------------------------------------------------------------
    v_ip := NULLIF(TRIM(SPLIT_PART(COALESCE(current_setting('request.headers', true)::JSON->>'x-forwarded-for', ''), ',', 1)), '');
    v_ip := COALESCE(v_ip, 'desconhecido');

    SELECT janela_inicio, contagem INTO v_janela, v_contagem
    FROM public.pedidos_rate_limit WHERE ip = v_ip FOR UPDATE;

    IF NOT FOUND THEN
        INSERT INTO public.pedidos_rate_limit(ip, janela_inicio, contagem) VALUES (v_ip, NOW(), 1);
    ELSIF NOW() - v_janela > INTERVAL '10 minutes' THEN
        UPDATE public.pedidos_rate_limit SET janela_inicio = NOW(), contagem = 1 WHERE ip = v_ip;
    ELSIF v_contagem >= 5 THEN
        RETURN jsonb_build_object('ok', false, 'erro', 'Limite de pedidos atingido. Tente novamente em alguns minutos.');
    ELSE
        UPDATE public.pedidos_rate_limit SET contagem = contagem + 1 WHERE ip = v_ip;
    END IF;

    ----------------------------------------------------------------
    -- Validação básica
    ----------------------------------------------------------------
    IF COALESCE(TRIM(p_nome), '') = '' OR COALESCE(TRIM(p_whatsapp), '') = '' THEN
        RETURN jsonb_build_object('ok', false, 'erro', 'Preencha nome e WhatsApp.');
    END IF;
    IF p_whatsapp !~ '^[0-9]{10,13}$' THEN
        RETURN jsonb_build_object('ok', false, 'erro', 'WhatsApp inválido.');
    END IF;
    IF p_entrega = 'Entrega' AND COALESCE(TRIM(p_endereco), '') = '' THEN
        RETURN jsonb_build_object('ok', false, 'erro', 'Informe o endereço de entrega.');
    END IF;
    IF jsonb_typeof(p_itens) IS DISTINCT FROM 'array' OR jsonb_array_length(p_itens) = 0 THEN
        RETURN jsonb_build_object('ok', false, 'erro', 'Sacola vazia.');
    END IF;

    ----------------------------------------------------------------
    -- Recalcula cada item a partir do banco — nunca confia em preço/nome
    -- vindos do client. Confere estoque (exceto para sob encomenda).
    ----------------------------------------------------------------
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_itens) LOOP
        v_id  := (v_item->>'id')::INT;
        v_qtd := (v_item->>'qtd')::INT;

        IF v_id IS NULL OR v_qtd IS NULL OR v_qtd <= 0 OR v_qtd > 50 THEN
            RETURN jsonb_build_object('ok', false, 'erro', 'Item inválido na sacola.');
        END IF;

        SELECT * INTO v_produto FROM public.produtos WHERE id = v_id AND ativo = TRUE;
        IF NOT FOUND THEN
            RETURN jsonb_build_object('ok', false, 'erro', 'Produto indisponível: item removido do catálogo.');
        END IF;

        IF NOT v_produto.encomenda AND v_produto.estoque < v_qtd THEN
            RETURN jsonb_build_object('ok', false, 'erro', 'Estoque insuficiente para "' || v_produto.nome || '".');
        END IF;

        v_subtotal := v_subtotal + (v_produto.preco * v_qtd);
        v_snapshot := v_snapshot || jsonb_build_object(
            'id', v_produto.id, 'nome', v_produto.nome, 'preco', v_produto.preco,
            'qtd', v_qtd, 'tamanho', v_item->>'tamanho',
            'tipo', v_produto.tipo, 'categoria', v_produto.categoria
        );
    END LOOP;

    ----------------------------------------------------------------
    -- Cupom — validado e calculado inteiramente no servidor
    ----------------------------------------------------------------
    IF COALESCE(TRIM(p_cupom_codigo), '') <> '' THEN
        SELECT * INTO v_cupom FROM public.cupons WHERE codigo = UPPER(TRIM(p_cupom_codigo)) AND ativo = TRUE;
        IF NOT FOUND THEN
            RETURN jsonb_build_object('ok', false, 'erro', 'Cupom inválido.');
        END IF;
        IF v_cupom.usos >= v_cupom.limite THEN
            RETURN jsonb_build_object('ok', false, 'erro', 'Cupom esgotado.');
        END IF;

        IF COALESCE(v_cupom.produtos_restringidos, '') <> '' THEN
            SELECT ARRAY_AGG(x::INT) INTO v_restrito FROM UNNEST(STRING_TO_ARRAY(v_cupom.produtos_restringidos, ',')) AS x;
            SELECT COALESCE(SUM((elem->>'preco')::NUMERIC * (elem->>'qtd')::INT), 0) INTO v_base_desc
            FROM jsonb_array_elements(v_snapshot) AS elem
            WHERE (elem->>'id')::INT = ANY(v_restrito);
            IF v_base_desc = 0 THEN
                RETURN jsonb_build_object('ok', false, 'erro', 'Cupom não é válido para os itens da sua sacola.');
            END IF;
        ELSE
            v_base_desc := v_subtotal;
        END IF;

        IF v_base_desc < v_cupom.minimo THEN
            RETURN jsonb_build_object('ok', false, 'erro', 'Pedido mínimo de R$' || v_cupom.minimo::TEXT || ' para usar este cupom.');
        END IF;

        v_desconto := CASE WHEN v_cupom.tipo = 'percentual'
            THEN ROUND(v_base_desc * v_cupom.valor / 100, 2)
            ELSE LEAST(v_cupom.valor, v_base_desc)
        END;
        v_cupom_aplicado := v_cupom.codigo;  -- só toca v_cupom aqui dentro, onde ele é garantidamente válido
    END IF;

    v_total := GREATEST(0, v_subtotal - v_desconto);

    ----------------------------------------------------------------
    -- Debita estoque atomicamente (WHERE estoque >= qtd garante que uma
    -- corrida entre dois pedidos concorrentes nunca vende a mesma unidade
    -- duas vezes) e insere o pedido. Qualquer falha aqui reverte tudo.
    ----------------------------------------------------------------
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_itens) LOOP
        v_id  := (v_item->>'id')::INT;
        v_qtd := (v_item->>'qtd')::INT;

        -- Sob encomenda não decrementa estoque (não tem controle de estoque de verdade —
        -- estoque=0 é o normal). Só produtos que NÃO são encomenda entram nesse UPDATE;
        -- o WHERE estoque>=qtd garante atomicidade contra corrida entre pedidos concorrentes.
        UPDATE public.produtos SET estoque = estoque - v_qtd
        WHERE id = v_id AND encomenda = FALSE AND estoque >= v_qtd;

        IF NOT FOUND AND EXISTS (SELECT 1 FROM public.produtos WHERE id = v_id AND encomenda = FALSE) THEN
            RAISE EXCEPTION 'Estoque de um item mudou durante a compra. Tente novamente.';
        END IF;
    END LOOP;

    INSERT INTO public.pedidos (
        nome, whatsapp, email, entrega, endereco, pagamento, observacao,
        itens, subtotal, desconto, cupom, total, comprovante_path
    ) VALUES (
        TRIM(p_nome), p_whatsapp, COALESCE(TRIM(p_email), ''), p_entrega, COALESCE(p_endereco, ''),
        p_pagamento, COALESCE(p_observacao, ''), v_snapshot, v_subtotal, v_desconto,
        COALESCE(v_cupom_aplicado, ''), v_total, COALESCE(p_comprovante_path, '')
    )
    RETURNING numero INTO v_numero;

    IF v_cupom_aplicado IS NOT NULL THEN
        UPDATE public.cupons SET usos = usos + 1 WHERE codigo = v_cupom_aplicado;
    END IF;

    RETURN jsonb_build_object('ok', true, 'numero', v_numero, 'subtotal', v_subtotal, 'desconto', v_desconto, 'total', v_total);
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('ok', false, 'erro', SQLERRM);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.criar_pedido(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,JSONB,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.criar_pedido(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,JSONB,TEXT,TEXT) TO anon, authenticated;

-- ------------------------------------------------------------
-- 6. Fecha o INSERT direto — toda criação de pedido passa pela RPC acima
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "pedidos_publico_insert" ON public.pedidos;
