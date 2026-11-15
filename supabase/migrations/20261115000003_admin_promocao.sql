-- ============================================================================
-- ADMIN: enxergar e editar a promoção por período (preço promocional + início + fim + rótulo)
--
-- * admin_get_produtos: passa a devolver preco_promocional, promo_inicio, promo_fim, promo_rotulo e
--   preco_vigente (o preço que a loja está cobrando AGORA). Chaves novas = o admin antigo as ignora.
-- * admin_salvar_produto: aceita as 4 chaves de promoção. COMPATÍVEL com o admin antigo: se o JSON não trouxer
--   'preco_promocional', a promoção existente NÃO é alterada. Valida antes de gravar (mensagens em português):
--     - promoção exige início e fim, com fim depois do início;
--     - preço promocional precisa ser menor que o preço normal.
-- Reverter: recriar as duas funções a partir de 20260902000001_c1_supabase_auth_admin.sql.
-- ============================================================================

create or replace function public.admin_get_produtos()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'Acesso negado' using errcode = '42501';
  end if;

  select jsonb_agg(
    jsonb_build_object(
      'id',               p.id,
      'nome',             p.nome,
      'descricao',        p.descricao,
      'preco',            p.preco,
      'custo',            p.custo,
      'tipo',             p.tipo,
      'categoria',        p.categoria,
      'tamanhos',         p.tamanhos,
      'imagens',          p.imagens,
      'estoque',          p.estoque,
      'destaque',         p.destaque,
      'novo',             p.novo,
      'encomenda',        p.encomenda,
      'prazo_encomenda',  p.prazo_encomenda,
      'badge_extra',      p.badge_extra,
      'ativo',            p.ativo,
      'agendamento',      p.agendamento,
      'preco_promocional', p.preco_promocional,
      'promo_inicio',     p.promo_inicio,
      'promo_fim',        p.promo_fim,
      'promo_rotulo',     p.promo_rotulo,
      'preco_vigente',    public.preco_vigente(p.preco, p.preco_promocional, p.promo_inicio, p.promo_fim)
    ) order by p.id
  ) into v_result
  from public.produtos p;

  return coalesce(v_result, '[]'::jsonb);
end;
$$;

create or replace function public.admin_salvar_produto(produto jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_id   int;
  v_tams text;
  v_imgs text;
  v_tem_promo boolean := (produto ? 'preco_promocional');
  v_promo numeric;
  v_ini   timestamptz;
  v_fim   timestamptz;
  v_rot   text;
  v_preco_ref numeric;
begin
  if not public.is_admin() then
    raise exception 'Acesso negado' using errcode = '42501';
  end if;

  v_tams := case
    when jsonb_typeof(produto->'tamanhos') = 'array'
    then (select string_agg(v, ',') from jsonb_array_elements_text(produto->'tamanhos') as v)
    else coalesce(produto->>'tamanhos', '')
  end;

  v_imgs := case
    when jsonb_typeof(produto->'imagens') = 'array'
    then (select string_agg(v, ',') from jsonb_array_elements_text(produto->'imagens') as v)
    else coalesce(produto->>'imagens', '')
  end;

  v_id := nullif((produto->>'id')::text, '')::int;

  -- Promoção: só mexe se a chave vier no JSON (admin antigo não manda -> promoção intacta)
  if v_tem_promo then
    v_promo := nullif(produto->>'preco_promocional', '')::numeric;
    v_ini   := nullif(produto->>'promo_inicio', '')::timestamptz;
    v_fim   := nullif(produto->>'promo_fim', '')::timestamptz;
    v_rot   := nullif(trim(coalesce(produto->>'promo_rotulo', '')), '');
    if v_promo is null then
      v_ini := null; v_fim := null; v_rot := null;           -- sem preço promocional = sem promoção
    else
      if v_promo < 0 then
        raise exception 'O preço promocional não pode ser negativo.';
      end if;
      if v_ini is null or v_fim is null or v_fim <= v_ini then
        raise exception 'Informe o início e o fim da promoção (o fim precisa ser depois do início).';
      end if;
      v_preco_ref := coalesce((produto->>'preco')::numeric,
                              (select p.preco from public.produtos p where p.id = v_id), 0);
      if v_promo >= v_preco_ref then
        raise exception 'O preço promocional precisa ser menor que o preço normal (R$ %).', to_char(v_preco_ref, 'FM999990.00');
      end if;
    end if;
  end if;

  if v_id is null then
    insert into public.produtos (
      nome, descricao, preco, custo, tipo, categoria,
      tamanhos, imagens, estoque, destaque, novo, encomenda,
      prazo_encomenda, badge_extra, ativo, agendamento,
      preco_promocional, promo_inicio, promo_fim, promo_rotulo, updated_at
    ) values (
      produto->>'nome',
      coalesce(produto->>'descricao', ''),
      coalesce((produto->>'preco')::decimal, 0),
      coalesce((produto->>'custo')::decimal, 0),
      coalesce(produto->>'tipo', 'unico'),
      coalesce(produto->>'categoria', 'acessorio'),
      v_tams,
      v_imgs,
      coalesce((produto->>'estoque')::int, 0),
      coalesce((produto->>'destaque')::boolean, false),
      coalesce((produto->>'novo')::boolean, false),
      coalesce((produto->>'encomenda')::boolean, false),
      coalesce(produto->>'prazo_encomenda', ''),
      coalesce(produto->>'badge_extra', ''),
      coalesce((produto->>'ativo')::boolean, true),
      coalesce(produto->>'agendamento', ''),
      v_promo, v_ini, v_fim, v_rot,
      now()
    );
  else
    update public.produtos set
      nome            = coalesce(produto->>'nome',           nome),
      descricao       = coalesce(produto->>'descricao',      descricao),
      preco           = coalesce((produto->>'preco')::decimal, preco),
      custo           = coalesce((produto->>'custo')::decimal, custo),
      tipo            = coalesce(produto->>'tipo',           tipo),
      categoria       = coalesce(produto->>'categoria',      categoria),
      tamanhos        = v_tams,
      imagens         = v_imgs,
      estoque         = coalesce((produto->>'estoque')::int, estoque),
      destaque        = coalesce((produto->>'destaque')::boolean, destaque),
      novo            = coalesce((produto->>'novo')::boolean, novo),
      encomenda       = coalesce((produto->>'encomenda')::boolean, encomenda),
      prazo_encomenda = coalesce(produto->>'prazo_encomenda', prazo_encomenda),
      badge_extra     = coalesce(produto->>'badge_extra',    badge_extra),
      ativo           = coalesce((produto->>'ativo')::boolean, ativo),
      agendamento     = coalesce(produto->>'agendamento',    agendamento),
      preco_promocional = case when v_tem_promo then v_promo else preco_promocional end,
      promo_inicio      = case when v_tem_promo then v_ini   else promo_inicio end,
      promo_fim         = case when v_tem_promo then v_fim   else promo_fim end,
      promo_rotulo      = case when v_tem_promo then v_rot   else promo_rotulo end,
      updated_at      = now()
    where id = v_id;
  end if;

  return jsonb_build_object('ok', true);
end;
$$;
