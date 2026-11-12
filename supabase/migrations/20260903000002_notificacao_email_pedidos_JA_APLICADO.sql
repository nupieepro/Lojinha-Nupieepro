-- ============================================================================
-- JÁ APLICADO EM PRODUÇÃO (extraído do banco em 12/11/2026) — só para recriar o banco do zero.
-- Notificação por e-mail de pedido: trigger -> pg_net -> Edge Function resend-email.
-- Pré-requisitos: extensões pg_net e supabase_vault; segredo no Vault chamado
--   service_role_key_notify_pedidos  (valor = service role key do projeto, NUNCA no Git);
--   Edge Function resend-email publicada (supabase/functions/resend-email) com secrets SMTP_USER/SMTP_PASSWORD.
-- Ordem: depois do schema inicial e de criar_pedido (usa a tabela pedidos).
-- ============================================================================
create extension if not exists pg_net;

create or replace function public._notify_email_on_pedidos()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_chave text;
begin
  select decrypted_secret into v_chave
  from vault.decrypted_secrets
  where name = 'service_role_key_notify_pedidos';

  if v_chave is null then
    raise warning 'Chave de notificação não encontrada no Vault — e-mail de pedido não enviado';
    return new;
  end if;

  perform net.http_post(
    url := 'https://scacjsosvlllapbgetos.supabase.co/functions/v1/resend-email',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer ' || v_chave
    ),
    body := jsonb_build_object(
      'event', tg_op,
      'record', to_jsonb(new)
    )
  );
  return new;
end;
$function$;

create or replace function public._pedidos_numero_unico_trg()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
declare
  v_base text;
  v_candidate text;
  v_n int := 1;
begin
  v_base := coalesce(nullif(trim(new.numero), ''), 'PED-' || to_char(now(), 'YYYYMMDDHH24MISS'));
  v_candidate := v_base;
  while exists (select 1 from public.pedidos p where p.numero = v_candidate) loop
    v_candidate := v_base || '-' || lpad(v_n::text, 3, '0');
    v_n := v_n + 1;
  end loop;
  new.numero := v_candidate;
  return new;
end;
$function$;

drop trigger if exists trg_pedidos_numero_unico on public.pedidos;
create trigger trg_pedidos_numero_unico before insert on public.pedidos
  for each row execute function public._pedidos_numero_unico_trg();

drop trigger if exists trg_pedidos_email_insert on public.pedidos;
create trigger trg_pedidos_email_insert after insert on public.pedidos
  for each row execute function public._notify_email_on_pedidos();

drop trigger if exists trg_pedidos_email_update on public.pedidos;
create trigger trg_pedidos_email_update after update of status, pago on public.pedidos
  for each row execute function public._notify_email_on_pedidos();
