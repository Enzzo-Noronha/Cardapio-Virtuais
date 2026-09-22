-- Execute este arquivo inteiro no SQL Editor do Supabase.
create extension if not exists pgcrypto;

create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null check (slug ~ '^[a-z0-9-]+$'),
  name text not null,
  contact text,
  whatsapp text not null,
  pix_key text,
  opening_hours text,
  auto_open_time time,
  auto_close_time time,
  is_open boolean not null default true,
  created_at timestamptz not null default now(),
  revenue_reset_at timestamptz
);

create table public.store_admins (
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  primary key (business_id, user_id)
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  position integer not null default 0,
  order_options jsonb not null default '{}'::jsonb,
  active boolean not null default true
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  name text not null,
  description text,
  price numeric(10,2) not null check (price >= 0),
  size_prices jsonb not null default '{}'::jsonb,
  image_url text,
  included_complements integer not null default 0 check (included_complements >= 0),
  includes_coverage boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.complements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  price numeric(10,2) not null default 0 check (price >= 0),
  kind text not null default 'complemento' check (kind in ('complemento','cobertura')),
  active boolean not null default true
);

create table public.localities (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  fee numeric(10,2) not null default 0 check (fee >= 0),
  active boolean not null default true
);

create table public.payment_methods (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  method text not null check (method in ('pix','cash','delivery')),
  active boolean not null default true,
  unique (business_id, method)
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  customer_name text,
  locality_name text not null,
  address_note text not null,
  payment_method text not null,
  cash_amount numeric(10,2),
  change_amount numeric(10,2),
  subtotal numeric(10,2) not null,
  delivery_fee numeric(10,2) not null,
  total numeric(10,2) not null,
  status text not null default 'novo' check (status in ('novo','em_preparo','saiu_para_entrega','concluido','cancelado')),
  created_at timestamptz not null default now()
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_name text not null,
  unit_price numeric(10,2) not null,
  quantity integer not null check (quantity > 0),
  complements jsonb not null default '[]'::jsonb
);

create or replace function public.is_store_admin(target_business uuid)
returns boolean language sql stable security invoker set search_path = pg_catalog, public as $$
  select exists (
    select 1 from public.store_admins
    where business_id = target_business and user_id = auth.uid()
  );
$$;

alter table public.businesses enable row level security;
alter table public.store_admins enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.complements enable row level security;
alter table public.localities enable row level security;
alter table public.payment_methods enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

create policy "menu publico" on public.businesses for select using (true);
create policy "admin ve vinculo" on public.store_admins for select using (user_id = auth.uid());
create policy "dados publicos categorias" on public.categories for select using (true);
create policy "dados publicos produtos" on public.products for select using (true);
create policy "dados publicos complementos" on public.complements for select using (true);
create policy "dados publicos localidades" on public.localities for select using (true);
create policy "dados publicos pagamentos" on public.payment_methods for select using (true);

create policy "admin altera loja" on public.businesses for update using (public.is_store_admin(id)) with check (public.is_store_admin(id));
create policy "admin categorias" on public.categories for all using (public.is_store_admin(business_id)) with check (public.is_store_admin(business_id));
create policy "admin produtos" on public.products for all using (public.is_store_admin(business_id)) with check (public.is_store_admin(business_id));
create policy "admin complementos" on public.complements for all using (public.is_store_admin(business_id)) with check (public.is_store_admin(business_id));
create policy "admin localidades" on public.localities for all using (public.is_store_admin(business_id)) with check (public.is_store_admin(business_id));
create policy "admin pagamentos" on public.payment_methods for all using (public.is_store_admin(business_id)) with check (public.is_store_admin(business_id));

create policy "admin ve pedidos" on public.orders for select using (public.is_store_admin(business_id));
create policy "admin atualiza pedidos" on public.orders for update using (public.is_store_admin(business_id)) with check (public.is_store_admin(business_id));
-- A criação de pedidos é configurada em supabase-order-rpc.sql; assim, não há
-- inserção pública direta em pedidos ou itens.
create policy "admin ve itens" on public.order_items for select using (exists (select 1 from public.orders o where o.id = order_id and public.is_store_admin(o.business_id)));

-- Expõe somente o necessário pela Data API; RLS continua controlando as linhas.
grant usage on schema public to anon, authenticated;
grant select on public.businesses, public.categories, public.products, public.complements, public.localities, public.payment_methods to anon, authenticated;
grant select, insert, update, delete on public.businesses, public.categories, public.products, public.complements, public.localities, public.payment_methods, public.orders, public.order_items to authenticated;

-- A função é usada exclusivamente pelas políticas RLS do administrador.
revoke all on function public.is_store_admin(uuid) from public;
grant execute on function public.is_store_admin(uuid) to authenticated;

-- Após criar o usuário do proprietário em Authentication > Users, crie a loja:
-- insert into public.businesses (slug, name, whatsapp, pix_key, opening_hours)
-- values ('thaisa-acai', 'Thaisa Açaí & Sorvetes', '5588999999999', 'sua-chave-pix', 'Todos os dias, 14h às 22h');
-- Depois associe o id do usuário criado:
-- insert into public.store_admins (business_id, user_id)
-- values ('ID_DA_LOJA', 'ID_DO_USUARIO_AUTH');
