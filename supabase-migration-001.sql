-- Use este arquivo somente se você JÁ executou uma versão anterior
-- do supabase-schema.sql antes desta atualização.
alter table public.products
  add column if not exists included_complements integer not null default 0
  check (included_complements >= 0);

alter table public.products
  add column if not exists includes_coverage boolean not null default false;

alter table public.complements
  add column if not exists kind text not null default 'complemento'
  check (kind in ('complemento','cobertura'));
