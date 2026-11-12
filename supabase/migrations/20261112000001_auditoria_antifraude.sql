-- ============================================================================
-- Auditoria de segurança (append-only) + antifraude + hardening de search_path
--
-- 1. public.auditoria_seguranca: trilha imutável (nem admin nem service_role
--    conseguem editar/apagar; só INSERT via triggers SECURITY DEFINER; SELECT só admin).
-- 2. Triggers: admin_users, config, cupons, produtos (preço/ativo) e pedidos
--    (status, pago e — principalmente — qualquer mudança em valores depois da criação).
--    Os blocos EXCEPTION garantem que falha de log NUNCA bloqueia venda/admin.
-- 3. admin_seguranca_resumo() e admin_antifraude_resumo(): RPCs só para admin.
-- 4. Fixa search_path de _csv_campo e _pedidos_numero_unico_trg (alerta do linter).
--
-- Reverter: DROP TRIGGER aud_*_trg ON <tabela>; DROP FUNCTION ...; DROP TABLE public.auditoria_seguranca;
-- ============================================================================

create table if not exists public.auditoria_seguranca (
  id          bigint generated always as identity primary key,
  criado_em   timestamptz not null default now(),
  ator        uuid,                 -- auth.uid(); NULL = SQL Editor / service_role / RPC pública
  tabela      text not null,
  operacao    text not null,
  registro_id text,
  campo       text,
  antes       text,
  depois      text
);
create index if not exists auditoria_seguranca_criado_em_idx on public.auditoria_seguranca (criado_em desc);
create index if not exists auditoria_seguranca_tabela_idx    on public.auditoria_seguranca (tabela, operacao, campo);

alter table public.auditoria_seguranca enable row level security;
drop policy if exists auditoria_seguranca_admin_select on public.auditoria_seguranca;
create policy auditoria_seguranca_admin_select on public.auditoria_seguranca
  for select to authenticated using (public.is_admin());
revoke all on table public.auditoria_seguranca from anon, authenticated;
grant select on table public.auditoria_seguranca to authenticated;

create or replace function public.auditoria_seguranca_imutavel()
returns trigger language plpgsql security definer set search_path = public as $$
begin raise exception 'auditoria_seguranca é somente-acréscimo (append-only)'; end $$;
revoke all on function public.auditoria_seguranca_imutavel() from public, anon, authenticated;
drop trigger if exists auditoria_seguranca_no_update on public.auditoria_seguranca;
create trigger auditoria_seguranca_no_update before update or delete on public.auditoria_seguranca
  for each row execute function public.auditoria_seguranca_imutavel();

-- helper interno de gravação (não exposto)
create or replace function public._aud(p_tabela text, p_op text, p_id text, p_campo text, p_antes text, p_depois text)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.auditoria_seguranca(ator, tabela, operacao, registro_id, campo, antes, depois)
  values (auth.uid(), p_tabela, p_op, p_id, p_campo, left(p_antes, 300), left(p_depois, 300));
exception when others then
  raise warning 'auditoria falhou (%.%): %', p_tabela, p_campo, sqlerrm;
end $$;
revoke all on function public._aud(text,text,text,text,text,text) from public, anon, authenticated;

-- admin_users: quem ganhou/perdeu acesso de admin
create or replace function public.aud_admin_users() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then perform public._aud('admin_users','INSERT', new.user_id::text, 'user_id', null, new.user_id::text);
  elsif tg_op = 'DELETE' then perform public._aud('admin_users','DELETE', old.user_id::text, 'user_id', old.user_id::text, null);
  end if;
  return null;
end $$;
revoke all on function public.aud_admin_users() from public, anon, authenticated;
drop trigger if exists aud_admin_users_trg on public.admin_users;
create trigger aud_admin_users_trg after insert or delete on public.admin_users for each row execute function public.aud_admin_users();

-- config: PIX, e-mail financeiro, manutenção etc.
create or replace function public.aud_config() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then perform public._aud('config','INSERT', new.chave, new.chave, null, new.valor::text);
  elsif tg_op = 'UPDATE' then
    if new.valor is distinct from old.valor then perform public._aud('config','UPDATE', new.chave, new.chave, old.valor::text, new.valor::text); end if;
  elsif tg_op = 'DELETE' then perform public._aud('config','DELETE', old.chave, old.chave, old.valor::text, null);
  end if;
  return null;
end $$;
revoke all on function public.aud_config() from public, anon, authenticated;
drop trigger if exists aud_config_trg on public.config;
create trigger aud_config_trg after insert or update or delete on public.config for each row execute function public.aud_config();

-- cupons: valor/tipo/limite/ativo
create or replace function public.aud_cupons() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then perform public._aud('cupons','INSERT', new.codigo, 'valor', null, new.tipo || ':' || new.valor::text);
  elsif tg_op = 'DELETE' then perform public._aud('cupons','DELETE', old.codigo, 'valor', old.tipo || ':' || old.valor::text, null);
  else
    if new.valor is distinct from old.valor or new.tipo is distinct from old.tipo then
      perform public._aud('cupons','UPDATE', new.codigo, 'valor', old.tipo || ':' || old.valor::text, new.tipo || ':' || new.valor::text); end if;
    if new.ativo is distinct from old.ativo then perform public._aud('cupons','UPDATE', new.codigo, 'ativo', old.ativo::text, new.ativo::text); end if;
    if new.limite is distinct from old.limite then perform public._aud('cupons','UPDATE', new.codigo, 'limite', old.limite::text, new.limite::text); end if;
  end if;
  return null;
end $$;
revoke all on function public.aud_cupons() from public, anon, authenticated;
drop trigger if exists aud_cupons_trg on public.cupons;
create trigger aud_cupons_trg after insert or update or delete on public.cupons for each row execute function public.aud_cupons();

-- produtos: preço e ativação
create or replace function public.aud_produtos() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    if new.preco is distinct from old.preco then perform public._aud('produtos','UPDATE', new.id::text, 'preco', old.preco::text, new.preco::text); end if;
    if new.ativo is distinct from old.ativo then perform public._aud('produtos','UPDATE', new.id::text, 'ativo', old.ativo::text, new.ativo::text); end if;
  elsif tg_op = 'DELETE' then perform public._aud('produtos','DELETE', old.id::text, 'nome', old.nome, null);
  end if;
  return null;
end $$;
revoke all on function public.aud_produtos() from public, anon, authenticated;
drop trigger if exists aud_produtos_trg on public.produtos;
create trigger aud_produtos_trg after update or delete on public.produtos for each row execute function public.aud_produtos();

-- pedidos: status/pago (quem confirmou pagamento) e ALERTA se valores mudarem depois de criados
create or replace function public.aud_pedidos() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    if new.status is distinct from old.status then perform public._aud('pedidos','UPDATE', new.numero, 'status', old.status, new.status); end if;
    if new.pago is distinct from old.pago then perform public._aud('pedidos','UPDATE', new.numero, 'pago', old.pago::text, new.pago::text); end if;
    if new.total is distinct from old.total then perform public._aud('pedidos','ALERTA', new.numero, 'total', old.total::text, new.total::text); end if;
    if new.desconto is distinct from old.desconto then perform public._aud('pedidos','ALERTA', new.numero, 'desconto', old.desconto::text, new.desconto::text); end if;
    if new.cupom is distinct from old.cupom then perform public._aud('pedidos','ALERTA', new.numero, 'cupom', old.cupom, new.cupom); end if;
  elsif tg_op = 'DELETE' then perform public._aud('pedidos','DELETE', old.numero, 'total', old.total::text, null);
  end if;
  return null;
end $$;
revoke all on function public.aud_pedidos() from public, anon, authenticated;
drop trigger if exists aud_pedidos_trg on public.pedidos;
create trigger aud_pedidos_trg after update or delete on public.pedidos for each row execute function public.aud_pedidos();

-- painel de segurança (admin)
create or replace function public.admin_seguranca_resumo() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return jsonb_build_object(
    'gerado_em', now(),
    'eventos_30d', coalesce((select jsonb_object_agg(k, n) from (
        select tabela || ':' || operacao || ':' || coalesce(campo,'-') as k, count(*) n
        from public.auditoria_seguranca where criado_em > now() - interval '30 days' group by 1) s), '{}'::jsonb),
    'alertas_integridade_90d', coalesce((select jsonb_agg(to_jsonb(a)) from (
        select criado_em, ator, registro_id, campo, antes, depois from public.auditoria_seguranca
        where operacao = 'ALERTA' and criado_em > now() - interval '90 days' order by criado_em desc) a), '[]'::jsonb),
    'ultimos_eventos', coalesce((select jsonb_agg(to_jsonb(e)) from (
        select criado_em, ator, tabela, operacao, registro_id, campo, antes, depois
        from public.auditoria_seguranca order by id desc limit 50) e), '[]'::jsonb),
    'admins', (select count(*) from public.admin_users)
  );
end $$;
revoke all on function public.admin_seguranca_resumo() from public, anon;
grant execute on function public.admin_seguranca_resumo() to authenticated;

-- antifraude (regras simples e explicáveis; só sinaliza, nunca bloqueia sozinho)
create or replace function public.admin_antifraude_resumo() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'acesso negado' using errcode = '42501'; end if;
  return jsonb_build_object(
    'gerado_em', now(),
    'whatsapp_3mais_pedidos_24h', coalesce((select jsonb_agg(to_jsonb(r)) from (
        select whatsapp, count(*) pedidos, sum(total) total from public.pedidos
        where created_at > now() - interval '24 hours' group by whatsapp having count(*) >= 3) r), '[]'::jsonb),
    'pix_pago_sem_comprovante_30d', coalesce((select jsonb_agg(to_jsonb(r)) from (
        select numero, nome, total, created_at from public.pedidos
        where pago and upper(coalesce(pagamento,'')) like 'PIX%' and comprovante_path is null
          and created_at > now() - interval '30 days' order by created_at desc limit 50) r), '[]'::jsonb),
    'cupom_reutilizado_mesmo_whatsapp_30d', coalesce((select jsonb_agg(to_jsonb(r)) from (
        select whatsapp, cupom, count(*) usos from public.pedidos
        where cupom is not null and cupom <> '' and created_at > now() - interval '30 days'
        group by whatsapp, cupom having count(*) > 1) r), '[]'::jsonb),
    'valor_muito_acima_da_media_30d', coalesce((select jsonb_agg(to_jsonb(r)) from (
        select numero, nome, total, created_at from public.pedidos
        where created_at > now() - interval '30 days'
          and total > 3 * (select coalesce(avg(total),0) from public.pedidos where created_at > now() - interval '90 days')
        order by total desc limit 20) r), '[]'::jsonb),
    'valores_alterados_apos_criacao_90d', coalesce((select jsonb_agg(to_jsonb(r)) from (
        select criado_em, ator, registro_id as pedido, campo, antes, depois from public.auditoria_seguranca
        where tabela = 'pedidos' and operacao = 'ALERTA' and criado_em > now() - interval '90 days'
        order by criado_em desc) r), '[]'::jsonb)
  );
end $$;
revoke all on function public.admin_antifraude_resumo() from public, anon;
grant execute on function public.admin_antifraude_resumo() to authenticated;

-- linter: search_path mutável
alter function public._csv_campo(text) set search_path = public;
alter function public._pedidos_numero_unico_trg() set search_path = public;
