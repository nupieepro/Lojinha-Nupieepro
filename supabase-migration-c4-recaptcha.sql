-- ============================================================
-- C4 — reCAPTCHA v3 com verificação server-side
-- ============================================================
-- ATENÇÃO: a definição de criar_pedido() abaixo ficou desatualizada depois da
-- auditoria B7 (chave de idempotência) — a versão CANÔNICA e atual da função
-- está em supabase-migration-idempotencia-pedido.sql (12 parâmetros, inclui
-- p_chave_idempotencia). Se for aplicar este arquivo do zero num ambiente novo,
-- aplique este primeiro e depois o de idempotência por cima.
-- O honeypot (#honeypot) permanece como camada extra — reCAPTCHA não o
-- substitui, complementa.
--
-- A verificação acontece DENTRO da mesma RPC que cria o pedido
-- (criar_pedido), não numa chamada separada — se fosse separada, um
-- client malicioso simplesmente pularia a etapa de verificação e
-- chamaria criar_pedido direto, tornando o reCAPTCHA decorativo.
--
-- PRÉ-REQUISITO: chave secreta cadastrada no Vault antes de aplicar:
--   select vault.create_secret('<CHAVE_SECRETA_AQUI>', 'recaptcha_secret_key',
--     'Chave secreta do reCAPTCHA v3 — usada só server-side em criar_pedido.');
-- Sem isso, a verificação fica desativada automaticamente (ver comentário
-- "modo sem chave" abaixo) — a função nunca quebra por falta da chave,
-- só deixa de aplicar essa camada.
-- ============================================================

-- Assinatura antiga (10 parâmetros) precisa ser derrubada explicitamente —
-- CREATE OR REPLACE não troca o parâmetro novo por um "com default": muda
-- a lista de tipos, então sem o DROP o Postgres criaria uma sobrecarga nova
-- ao lado da antiga em vez de substituir (mesmo problema já corrigido no
-- C1 pras funções admin_*).
DROP FUNCTION IF EXISTS public.criar_pedido(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,JSONB,TEXT,TEXT);

-- Score mínimo configurável sem precisar de novo deploy (mesmo padrão das
-- demais chaves em config, ex. pausar_checkout)
INSERT INTO public.config (chave, valor) VALUES ('recaptcha_min_score', '0.5')
ON CONFLICT (chave) DO NOTHING;

CREATE OR REPLACE FUNCTION public.criar_pedido(
    p_nome             TEXT,
    p_whatsapp         TEXT,
    p_email            TEXT,
    p_entrega          TEXT,
    p_endereco         TEXT,
    p_pagamento        TEXT,
    p_observacao       TEXT,
    p_itens            JSONB,
    p_cupom_codigo     TEXT DEFAULT NULL,
    p_comprovante_path TEXT DEFAULT NULL,
    p_recaptcha_token  TEXT DEFAULT NULL
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
    v_cupom_aplicado TEXT;
    v_restrito     INT[];
    v_base_desc    NUMERIC := 0;
    v_desconto     NUMERIC := 0;
    v_total        NUMERIC := 0;
    v_numero       TEXT;
    v_id           INT;
    -- reCAPTCHA
    v_recaptcha_secret    TEXT;
    v_recaptcha_min_score NUMERIC;
    v_req_id       BIGINT;
    v_status       INT;
    v_content      TEXT;
    v_tentativas   INT;
    v_rc_success   BOOLEAN;
    v_rc_score     NUMERIC;
BEGIN
    ----------------------------------------------------------------
    -- Rate limit (igual antes)
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
    -- reCAPTCHA v3 — verificado direto com o Google via pg_net, dentro
    -- da mesma chamada que cria o pedido (não dá pra pular chamando outra
    -- RPC). "Modo sem chave": se ninguém cadastrou a chave secreta no
    -- Vault ainda, essa camada fica inativa e o pedido segue normalmente
    -- pelas outras validações — nunca quebra o checkout por chave ausente.
    ----------------------------------------------------------------
    SELECT decrypted_secret INTO v_recaptcha_secret
    FROM vault.decrypted_secrets WHERE name = 'recaptcha_secret_key';

    IF v_recaptcha_secret IS NOT NULL THEN
        IF COALESCE(p_recaptcha_token, '') = '' THEN
            RETURN jsonb_build_object('ok', false, 'erro', 'Verificação de segurança ausente. Recarregue a página e tente novamente.');
        END IF;

        SELECT COALESCE(NULLIF(valor,'')::NUMERIC, 0.5) INTO v_recaptcha_min_score
        FROM public.config WHERE chave = 'recaptcha_min_score';
        v_recaptcha_min_score := COALESCE(v_recaptcha_min_score, 0.5);

        v_req_id := net.http_get(
            url    := 'https://www.google.com/recaptcha/api/siteverify',
            params := jsonb_build_object('secret', v_recaptcha_secret, 'response', p_recaptcha_token, 'remoteip', v_ip)
        );

        -- Espera a resposta assíncrona do pg_net por até ~3s (20 x 150ms).
        -- v_status/v_content ficam NULL se nada chegar a tempo — nunca dá
        -- erro de "record not assigned" porque são escalares, não RECORD.
        v_tentativas := 0;
        v_status := NULL;
        LOOP
            SELECT status_code, content INTO v_status, v_content FROM net._http_response WHERE id = v_req_id;
            EXIT WHEN v_status IS NOT NULL OR v_tentativas >= 20;
            PERFORM pg_sleep(0.15);
            v_tentativas := v_tentativas + 1;
        END LOOP;

        IF v_status = 200 THEN
            v_rc_success := (v_content::JSONB->>'success')::BOOLEAN;
            v_rc_score   := COALESCE((v_content::JSONB->>'score')::NUMERIC, 0);
            IF NOT COALESCE(v_rc_success, false) OR v_rc_score < v_recaptcha_min_score THEN
                RETURN jsonb_build_object('ok', false, 'erro', 'Não foi possível confirmar que você não é um robô. Recarregue a página e tente novamente.');
            END IF;
        END IF;
        -- Se v_status for NULL ou diferente de 200 (Google fora do ar, timeout),
        -- a verificação é pulada propositalmente: uma instabilidade externa não
        -- pode derrubar o checkout inteiro. Honeypot + rate limit + validação de
        -- estoque/cupom continuam de pé de qualquer forma nesse cenário raro.
    END IF;

    ----------------------------------------------------------------
    -- Validação básica (igual antes)
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
    -- Recalcula cada item a partir do banco (igual antes)
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
    -- Cupom (igual antes)
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
        v_cupom_aplicado := v_cupom.codigo;
    END IF;

    v_total := GREATEST(0, v_subtotal - v_desconto);

    ----------------------------------------------------------------
    -- Debita estoque e insere o pedido (igual antes)
    ----------------------------------------------------------------
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_itens) LOOP
        v_id  := (v_item->>'id')::INT;
        v_qtd := (v_item->>'qtd')::INT;

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

REVOKE EXECUTE ON FUNCTION public.criar_pedido(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,JSONB,TEXT,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.criar_pedido(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,JSONB,TEXT,TEXT,TEXT) TO anon, authenticated;
