-- Pedidos: dados de contato, status e proteção básica contra abuso.

alter table public.orders
  add column if not exists customer_phone text,
  add column if not exists order_note text;

alter table public.orders drop constraint if exists orders_status_check;
update public.orders set status = 'entregue' where status = 'concluido';
alter table public.orders
  add constraint orders_status_check
  check (status in ('novo','em_preparo','saiu_para_entrega','entregue','cancelado'));

create index if not exists orders_business_created_idx
  on public.orders (business_id, created_at desc);
create index if not exists orders_business_status_created_idx
  on public.orders (business_id, status, created_at desc);

create schema if not exists private;
create table if not exists private.customer_order_rate_limits (
  client_key text primary key,
  window_started_at timestamptz not null,
  request_count integer not null check (request_count >= 0)
);

-- Limite simples: até 10 tentativas por IP a cada 10 minutos.
create or replace function public.enforce_customer_order_rate_limit()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_headers jsonb := coalesce(current_setting('request.headers', true), '{}')::jsonb;
  v_ip text;
  v_key text;
  v_row private.customer_order_rate_limits%rowtype;
begin
  v_ip := nullif(trim(coalesce(v_headers ->> 'cf-connecting-ip', split_part(coalesce(v_headers ->> 'x-forwarded-for', ''), ',', 1))), '');
  if v_ip is null then
    v_ip := 'unknown';
  end if;
  v_key := encode(extensions.digest(v_ip, 'sha256'), 'hex');

  select * into v_row
  from private.customer_order_rate_limits
  where client_key = v_key
  for update;

  if not found then
    insert into private.customer_order_rate_limits (client_key, window_started_at, request_count)
    values (v_key, now(), 1);
    return;
  end if;

  if v_row.window_started_at <= now() - interval '10 minutes' then
    update private.customer_order_rate_limits
    set window_started_at = now(), request_count = 1
    where client_key = v_key;
    return;
  end if;

  if v_row.request_count >= 10 then
    raise exception 'Muitas tentativas de pedido. Aguarde alguns minutos e tente novamente.';
  end if;

  update private.customer_order_rate_limits
  set request_count = request_count + 1
  where client_key = v_key;
end;
$$;

-- A nova RPC mantém o cálculo de preços existente no servidor e acrescenta
-- telefone/observação. O WhatsApp só é aberto no navegador depois desta chamada.
create or replace function public.create_customer_order_v2(
  p_business_id uuid,
  p_customer_name text,
  p_customer_phone text,
  p_locality_id uuid,
  p_address_note text,
  p_payment_method text,
  p_cash_amount numeric,
  p_order_note text,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_order_id uuid;
  v_name text := nullif(trim(coalesce(p_customer_name, '')), '');
  v_phone text := nullif(regexp_replace(coalesce(p_customer_phone, ''), '[^0-9+]', '', 'g'), '');
  v_note text := nullif(trim(coalesce(p_order_note, '')), '');
begin
  if v_name is not null and length(v_name) > 120 then
    raise exception 'Nome inválido.';
  end if;
  if v_phone is null or length(v_phone) < 10 or length(v_phone) > 16 then
    raise exception 'Informe um telefone válido.';
  end if;
  if v_note is not null and length(v_note) > 500 then
    raise exception 'Observação muito longa.';
  end if;

  perform public.enforce_customer_order_rate_limit();
  v_order_id := public.create_customer_order(
    p_business_id,
    v_name,
    p_locality_id,
    p_address_note,
    p_payment_method,
    p_cash_amount,
    p_items
  );

  update public.orders
  set customer_phone = v_phone, order_note = v_note
  where id = v_order_id and business_id = p_business_id;

  return v_order_id;
end;
$$;

revoke all on function public.enforce_customer_order_rate_limit() from public;
revoke all on function public.enforce_customer_order_rate_limit() from anon, authenticated;
revoke all on function public.create_customer_order_v2(uuid, text, text, uuid, text, text, numeric, text, jsonb) from public;
grant execute on function public.create_customer_order_v2(uuid, text, text, uuid, text, text, numeric, text, jsonb) to anon, authenticated;

-- As funções auxiliares e a RPC antiga não devem ficar expostas diretamente.
revoke all on function public.store_schedule_for_date(uuid, date) from public, anon, authenticated;
revoke all on function public.store_status_at(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.create_customer_order(uuid, text, uuid, text, text, numeric, jsonb) from public, anon, authenticated;
