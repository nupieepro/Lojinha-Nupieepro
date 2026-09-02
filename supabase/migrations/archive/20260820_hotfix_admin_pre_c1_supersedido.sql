-- ============================================================
-- ⚠️ ARQUIVO HISTÓRICO — NÃO REAPLICAR NUM BANCO NOVO
--
-- Este script foi um hotfix aplicado direto em produção ENQUANTO o
-- painel admin ainda usava as funções antigas com parâmetro "chave"
-- (senha em texto plano), antes do corte do C1 pra Supabase Auth.
-- Corrige: export CSV quebrado (bug de tipo cliente/servidor), CSV/
-- Formula Injection, e a métrica de faturamento somando pedido não
-- pago.
--
-- Essas mesmas correções já estão incorporadas nas funções admin_*
-- criadas por 20260902000001_c1_supabase_auth_admin.sql (a versão
-- SEM o parâmetro "chave", que é a que roda em produção hoje). Este
-- arquivo é mantido só como registro de auditoria de uma correção
-- real que já foi feita — não faz parte da sequência de migrations
-- pra montar o banco do zero. Rodar isso contra um banco que já
-- passou pelo C1 falha (as funções com "chave" não existem mais).
-- ============================================================
--
-- B8 — Correções de admin encontradas na auditoria aprofundada
-- Já aplicadas direto em produção (todas retrocompatíveis com a
-- assinatura atual das funções, pré-cutover do C1). Este arquivo
-- é o registro/auditoria e a versão a reaplicar em caso de restore.
-- ============================================================

-- ------------------------------------------------------------
-- 1. CSV: neutraliza CSV/Formula Injection e escapa aspas em TODO
--    campo (antes só endereço/anotação escapavam aspas; nenhum
--    campo neutralizava fórmula). nome/observação/endereço são
--    texto livre do cliente.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._csv_campo(v TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT '"' || REPLACE(
        CASE WHEN v ~ '^[=+\-@\t\r]' THEN '''' || v ELSE v END,
        '"', '""'
    ) || '"'
$$;

CREATE OR REPLACE FUNCTION public.admin_exportar_csv(chave text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_csv TEXT;
BEGIN
    PERFORM public._validar_admin(chave);

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
               -- coluna correta é anotacao_interna (admin_atualizar_pedido grava
               -- aqui); a versão anterior lia "anotacao", uma coluna morta que
               -- nunca é escrita por nenhum fluxo do painel.
               public._csv_campo(COALESCE(anotacao_interna,'')),
               E'\n' ORDER BY created_at DESC
           )
    INTO v_csv
    FROM public.pedidos;

    RETURN COALESCE(v_csv, '');
END;
$function$;

-- ------------------------------------------------------------
-- 2. Dashboard: separa "total em pedidos" (inclui não pagos) de
--    "recebido" (pago=true) — o card único "Faturamento total"
--    somava todo pedido não cancelado, inclusive PIX nunca
--    confirmado, inflando a métrica exibida ao admin.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_dashboard(chave text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_senha        TEXT;
    v_faturado     NUMERIC  := 0;
    v_faturado_pago NUMERIC := 0;
    v_total        INTEGER  := 0;
    v_cancelados   INTEGER  := 0;
    v_hoje         INTEGER  := 0;
    v_ticket       NUMERIC  := 0;
    v_mais_vendido JSONB    := NULL;
    v_pagamentos   JSONB    := '{}'::JSONB;
    v_desconto     NUMERIC  := 0;
BEGIN
    SELECT c.valor INTO v_senha FROM public.config c WHERE c.chave = 'admin_senha';
    IF v_senha IS NULL OR admin_dashboard.chave <> v_senha THEN
        RAISE EXCEPTION 'Acesso negado';
    END IF;

    SELECT COALESCE(SUM(total), 0) INTO v_faturado FROM public.pedidos WHERE status <> 'cancelado';
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
        GROUP BY nome_prod ORDER BY total_qtd DESC LIMIT 1
    ) sub;

    SELECT jsonb_object_agg(pagamento, qty)
    INTO v_pagamentos
    FROM (SELECT pagamento, COUNT(*) AS qty FROM public.pedidos WHERE status <> 'cancelado' GROUP BY pagamento) sub;

    SELECT COALESCE(SUM(desconto), 0) INTO v_desconto FROM public.pedidos WHERE status <> 'cancelado' AND cupom <> '';

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
$function$;

-- ------------------------------------------------------------
-- 3. Agendamento de produto: campo existia no form do admin e era
--    salvo no banco, mas nada em index.html nem na RLS filtrava por
--    ele — produto "agendado" ficava visível na loja imediatamente
--    ao publicar, não na data marcada.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "produtos_publico_select" ON public.produtos;
CREATE POLICY "produtos_publico_select" ON public.produtos
    FOR SELECT TO anon
    USING (
        ativo = true
        AND (
            agendamento IS NULL OR agendamento = ''
            OR agendamento <= to_char(now() AT TIME ZONE 'America/Fortaleza', 'YYYY-MM-DD"T"HH24:MI')
        )
    );
