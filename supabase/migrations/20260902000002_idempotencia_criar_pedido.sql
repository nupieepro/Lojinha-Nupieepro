-- ============================================================
-- Idempotência em criar_pedido() — já aplicado direto em produção.
-- Achado sinalizado na auditoria B7: se a resposta da RPC se perder
-- por instabilidade de rede DEPOIS do servidor já ter criado o
-- pedido (estoque decrementado, cupom usado), o cliente só vê "erro,
-- tente novamente" e pode reenviar o mesmo pedido, duplicando-o.
-- ============================================================

ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS chave_idempotencia TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS pedidos_chave_idempotencia_key
    ON public.pedidos(chave_idempotencia) WHERE chave_idempotencia IS NOT NULL;

-- criar_pedido ganha o parâmetro p_chave_idempotencia (12º, com DEFAULT NULL —
-- retrocompatível com quem ainda não manda). Isso muda a lista de parâmetros da
-- função, o que faz o Postgres criar um NOVO overload em vez de substituir o
-- existente (mesma pegadinha do CREATE OR REPLACE já documentada nas migrações
-- do C1/C4) — por isso o DROP FUNCTION explícito da assinatura de 11 parâmetros
-- logo depois. Sem isso, ficam dois "criar_pedido" coexistindo e o PostgREST
-- pode não conseguir escolher qual chamar (erro de função ambígua).
CREATE OR REPLACE FUNCTION public.criar_pedido(
    p_nome text, p_whatsapp text, p_email text, p_entrega text, p_endereco text,
    p_pagamento text, p_observacao text, p_itens jsonb,
    p_cupom_codigo text DEFAULT NULL::text,
    p_comprovante_path text DEFAULT NULL::text,
    p_recaptcha_token text DEFAULT NULL::text,
    p_chave_idempotencia text DEFAULT NULL::text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    v_recaptcha_secret    TEXT;
    v_recaptcha_min_score NUMERIC;
    v_req_id       BIGINT;
    v_status       INT;
    v_content      TEXT;
    v_tentativas   INT;
    v_rc_success   BOOLEAN;
    v_rc_score     NUMERIC;
    -- Variáveis DEDICADAS pro lookup de idempotência — usar v_numero/v_subtotal/
    -- v_desconto/v_total aqui foi um bug real, pego em teste antes de ir pra
    -- produção: SELECT INTO sobre zero linhas (o caso normal, chave nova) zera
    -- essas variáveis pra NULL como efeito colateral, e como elas são
    -- reaproveitadas no resto da função, TODO pedido nascia com subtotal/
    -- desconto/total NULL/0. Corrigido com variáveis próprias, sem overlap.
    v_idemp_numero    TEXT;
    v_idemp_subtotal  NUMERIC;
    v_idemp_desconto  NUMERIC;
    v_idemp_total     NUMERIC;
BEGIN
    -- Checado ANTES de qualquer outra coisa (nem consome cota de rate limit) —
    -- um reenvio legítimo (retry de rede) não deve custar nada ao cliente.
    IF COALESCE(TRIM(p_chave_idempotencia), '') <> '' THEN
        SELECT numero, subtotal, desconto, total
        INTO v_idemp_numero, v_idemp_subtotal, v_idemp_desconto, v_idemp_total
        FROM public.pedidos WHERE chave_idempotencia = p_chave_idempotencia;
        IF FOUND THEN
            RETURN jsonb_build_object('ok', true, 'numero', v_idemp_numero, 'subtotal', v_idemp_subtotal, 'desconto', v_idemp_desconto, 'total', v_idemp_total);
        END IF;
    END IF;

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
    END IF;

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
        itens, subtotal, desconto, cupom, total, comprovante_path, chave_idempotencia
    ) VALUES (
        TRIM(p_nome), p_whatsapp, COALESCE(TRIM(p_email), ''), p_entrega, COALESCE(p_endereco, ''),
        p_pagamento, COALESCE(p_observacao, ''), v_snapshot, v_subtotal, v_desconto,
        COALESCE(v_cupom_aplicado, ''), v_total, COALESCE(p_comprovante_path, ''),
        NULLIF(TRIM(p_chave_idempotencia), '')
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
$function$;

DROP FUNCTION IF EXISTS public.criar_pedido(text, text, text, text, text, text, text, jsonb, text, text, text);
