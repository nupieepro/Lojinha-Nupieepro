-- ============================================================
-- B9 — Consulta de status real do pedido (já aplicado em produção)
-- ============================================================
-- Achado: "Meus Pedidos" no site era só um retrato congelado do momento da
-- compra (localStorage) — sem jeito de ver o status atual (confirmado / em
-- produção / pronto / entregue) sem falar com a loja pelo WhatsApp. RPC
-- pública, mas exige numero + whatsapp batendo juntos (o numero sozinho, ainda
-- que baseado em timestamp, não é segredo suficiente pra expor status de
-- pedido alheio) e tem rate limit próprio por IP.

CREATE TABLE IF NOT EXISTS public.consulta_status_rate_limit (
    ip TEXT PRIMARY KEY,
    janela_inicio TIMESTAMPTZ NOT NULL,
    contagem INT NOT NULL DEFAULT 1
);
ALTER TABLE public.consulta_status_rate_limit ENABLE ROW LEVEL SECURITY;
-- Sem policies: nenhum papel de cliente acessa direto, só a função abaixo.

CREATE OR REPLACE FUNCTION public.consultar_status_pedido(p_numero TEXT, p_whatsapp TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ip       TEXT;
    v_janela   TIMESTAMPTZ;
    v_contagem INT;
    v_row      RECORD;
BEGIN
    v_ip := NULLIF(TRIM(SPLIT_PART(COALESCE(current_setting('request.headers', true)::JSON->>'x-forwarded-for', ''), ',', 1)), '');
    v_ip := COALESCE(v_ip, 'desconhecido');

    -- Rate limit próprio (não compartilha cota com criar_pedido): 20 consultas
    -- por IP a cada 10 minutos.
    SELECT janela_inicio, contagem INTO v_janela, v_contagem
    FROM public.consulta_status_rate_limit WHERE ip = v_ip FOR UPDATE;

    IF NOT FOUND THEN
        INSERT INTO public.consulta_status_rate_limit(ip, janela_inicio, contagem) VALUES (v_ip, NOW(), 1);
    ELSIF NOW() - v_janela > INTERVAL '10 minutes' THEN
        UPDATE public.consulta_status_rate_limit SET janela_inicio = NOW(), contagem = 1 WHERE ip = v_ip;
    ELSIF v_contagem >= 20 THEN
        RETURN jsonb_build_object('ok', false, 'erro', 'Muitas consultas. Tente novamente em alguns minutos.');
    ELSE
        UPDATE public.consulta_status_rate_limit SET contagem = contagem + 1 WHERE ip = v_ip;
    END IF;

    IF COALESCE(TRIM(p_numero), '') = '' OR COALESCE(TRIM(p_whatsapp), '') = '' THEN
        RETURN jsonb_build_object('ok', false, 'erro', 'Informe o número do pedido e o WhatsApp usado na compra.');
    END IF;

    SELECT status, pago, total, created_at, entrega
    INTO v_row
    FROM public.pedidos
    WHERE numero = TRIM(p_numero)
      AND whatsapp = REGEXP_REPLACE(p_whatsapp, '\D', '', 'g');

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'erro', 'Pedido não encontrado. Confira o número e o WhatsApp usado na compra.');
    END IF;

    RETURN jsonb_build_object(
        'ok', true, 'status', v_row.status, 'pago', v_row.pago,
        'total', v_row.total, 'data', v_row.created_at, 'entrega', v_row.entrega
    );
END;
$$;

REVOKE ALL ON FUNCTION public.consultar_status_pedido(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consultar_status_pedido(TEXT, TEXT) TO anon, authenticated;
