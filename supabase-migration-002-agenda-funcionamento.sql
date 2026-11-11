-- Agenda de funcionamento por dia para o Império do Açaí.
-- Execute este arquivo inteiro no SQL Editor do Supabase, antes de publicar o site.

alter table public.businesses
  add column if not exists manual_force_closed boolean not null default false;

create table if not exists public.business_weekly_hours (
  business_id uuid not null references public.businesses(id) on delete cascade,
  weekday smallint not null check (weekday between 0 and 6), -- 0=domingo, 6=sábado
  is_open boolean not null default false,
  opens_at time,
  closes_at time,
  primary key (business_id, weekday),
  check (
    (is_open = false and opens_at is null and closes_at is null)
    or (is_open = true and opens_at is not null and closes_at is not null and opens_at <> closes_at)
  )
);

create table if not exists public.business_schedule_exceptions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  exception_date date not null,
  is_open boolean not null,
  opens_at time,
  closes_at time,
  created_at timestamptz not null default now(),
  unique (business_id, exception_date),
  check (
    (is_open = false and opens_at is null and closes_at is null)
    or (is_open = true and opens_at is not null and closes_at is not null and opens_at <> closes_at)
  )
);

create index if not exists business_schedule_exceptions_lookup_idx
  on public.business_schedule_exceptions (business_id, exception_date);

-- Migra a programação anterior para todos os dias da semana sem apagar os
-- campos antigos. Sem horário configurado, conserva o antigo abre/fecha manual.
insert into public.business_weekly_hours (business_id, weekday, is_open, opens_at, closes_at)
select
  b.id,
  d.weekday,
  case
    when b.auto_open_time is not null and b.auto_close_time is not null and b.auto_open_time <> b.auto_close_time then true
    else b.is_open
  end,
  case
    when b.auto_open_time is not null and b.auto_close_time is not null and b.auto_open_time <> b.auto_close_time then b.auto_open_time
    when b.is_open then time '00:00'
    else null
  end,
  case
    when b.auto_open_time is not null and b.auto_close_time is not null and b.auto_open_time <> b.auto_close_time then b.auto_close_time
    when b.is_open then time '23:59'
    else null
  end
from public.businesses b
cross join generate_series(0, 6) as d(weekday)
on conflict (business_id, weekday) do nothing;

alter table public.business_weekly_hours enable row level security;
alter table public.business_schedule_exceptions enable row level security;

drop policy if exists "admin agenda semanal" on public.business_weekly_hours;
create policy "admin agenda semanal" on public.business_weekly_hours
  for all to authenticated
  using (public.is_store_admin(business_id))
  with check (public.is_store_admin(business_id));

drop policy if exists "admin excecoes de agenda" on public.business_schedule_exceptions;
create policy "admin excecoes de agenda" on public.business_schedule_exceptions
  for all to authenticated
  using (public.is_store_admin(business_id))
  with check (public.is_store_admin(business_id));

grant select, insert, update, delete on public.business_weekly_hours, public.business_schedule_exceptions to authenticated;
revoke all on public.business_weekly_hours, public.business_schedule_exceptions from anon;

-- Retorna a regra aplicável a uma data. Exceções sempre vencem a regra semanal.
create or replace function public.store_schedule_for_date(p_business_id uuid, p_date date)
returns table (is_exception boolean, is_open boolean, opens_at time, closes_at time)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select true, e.is_open, e.opens_at, e.closes_at
  from public.business_schedule_exceptions e
  where e.business_id = p_business_id and e.exception_date = p_date
  union all
  select false, w.is_open, w.opens_at, w.closes_at
  from public.business_weekly_hours w
  where w.business_id = p_business_id
    and w.weekday = extract(dow from p_date)::smallint
    and not exists (
      select 1
      from public.business_schedule_exceptions e
      where e.business_id = p_business_id and e.exception_date = p_date
    )
  limit 1;
$$;

-- Fonte única da situação da loja. O horário é sempre calculado no servidor
-- pelo fuso America/Fortaleza, inclusive para expedientes que viram o dia.
create or replace function public.store_status_at(
  p_business_id uuid,
  p_reference timestamptz default now()
)
returns table (aberto boolean, mensagem text, proxima_abertura timestamptz)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_business record;
  v_now_local timestamp;
  v_today date;
  v_now_time time;
  v_today_rule record;
  v_previous_rule record;
  v_candidate_rule record;
  v_today_has_exception boolean := false;
  v_candidate_date date;
  v_candidate_start timestamp;
  v_next_opening timestamp;
  v_offset integer;
begin
  select b.id, b.manual_force_closed
  into v_business
  from public.businesses b
  where b.id = p_business_id;

  if not found then
    raise exception 'Loja não encontrada.';
  end if;

  if v_business.manual_force_closed then
    return query select false, 'Cardápio fechado manualmente.', null::timestamptz;
    return;
  end if;

  v_now_local := p_reference at time zone 'America/Fortaleza';
  v_today := v_now_local::date;
  v_now_time := v_now_local::time;

  select * into v_today_rule
  from public.store_schedule_for_date(p_business_id, v_today);

  select exists (
    select 1 from public.business_schedule_exceptions e
    where e.business_id = p_business_id and e.exception_date = v_today
  ) into v_today_has_exception;

  if found and v_today_rule.is_open then
    if (v_today_rule.opens_at < v_today_rule.closes_at
        and v_now_time >= v_today_rule.opens_at and v_now_time < v_today_rule.closes_at)
       or
       (v_today_rule.opens_at > v_today_rule.closes_at
        and v_now_time >= v_today_rule.opens_at) then
      return query select true, 'Cardápio aberto agora.', null::timestamptz;
      return;
    end if;
  end if;

  -- Uma exceção de hoje prevalece sobre um possível turno iniciado ontem.
  if not v_today_has_exception then
    select * into v_previous_rule
    from public.store_schedule_for_date(p_business_id, v_today - 1);

    if found and v_previous_rule.is_open
       and v_previous_rule.opens_at > v_previous_rule.closes_at
       and v_now_time < v_previous_rule.closes_at then
      return query select true, 'Cardápio aberto agora.', null::timestamptz;
      return;
    end if;
  end if;

  for v_offset in 0..14 loop
    v_candidate_date := v_today + v_offset;
    select * into v_candidate_rule
    from public.store_schedule_for_date(p_business_id, v_candidate_date);

    if found and v_candidate_rule.is_open then
      v_candidate_start := v_candidate_date + v_candidate_rule.opens_at;
      if v_candidate_start > v_now_local then
        v_next_opening := v_candidate_start;
        exit;
      end if;
    end if;
  end loop;

  if v_next_opening is null then
    return query select false, 'Cardápio fechado. Consulte a loja para o próximo horário.', null::timestamptz;
  elsif v_next_opening::date = v_today then
    return query select false, 'Fechado no momento. Abrimos hoje às ' || to_char(v_next_opening, 'HH24:MI') || '.', v_next_opening at time zone 'America/Fortaleza';
  elsif v_next_opening::date = v_today + 1 then
    return query select false, 'Fechado hoje. Abrimos amanhã às ' || to_char(v_next_opening, 'HH24:MI') || '.', v_next_opening at time zone 'America/Fortaleza';
  else
    return query select false, 'Fechado. Abrimos em ' || to_char(v_next_opening, 'DD/MM') || ' às ' || to_char(v_next_opening, 'HH24:MI') || '.', v_next_opening at time zone 'America/Fortaleza';
  end if;
end;
$$;

-- Endpoint público do status: POST /rest/v1/rpc/get_store_status
create or replace function public.get_store_status(p_slug text)
returns table (aberto boolean, mensagem text, proxima_abertura timestamptz)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select s.aberto, s.mensagem, s.proxima_abertura
  from public.businesses b
  cross join lateral public.store_status_at(b.id, now()) s
  where b.slug = trim(lower(p_slug));
$$;

revoke all on function public.store_schedule_for_date(uuid, date) from public;
revoke all on function public.store_status_at(uuid, timestamptz) from public;
revoke all on function public.get_store_status(text) from public;
grant execute on function public.store_status_at(uuid, timestamptz) to anon, authenticated;
grant execute on function public.get_store_status(text) to anon, authenticated;
