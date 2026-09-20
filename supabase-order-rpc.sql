-- Pedido público controlado. O cliente só pode criar um pedido; a função
-- recalcula preços e taxas no servidor. A RLS permite INSERT apenas durante
-- esta função (através de parâmetros locais que não vêm da requisição HTTP).
revoke insert on public.orders, public.order_items from anon, authenticated;
drop policy if exists "cliente cria pedido" on public.orders;
drop policy if exists "cliente cria itens" on public.order_items;
drop policy if exists "cliente cria pedido via RPC" on public.orders;
drop policy if exists "cliente cria itens via RPC" on public.order_items;

create policy "cliente cria pedido via RPC" on public.orders for insert to anon, authenticated
with check (business_id::text = current_setting('app.customer_order_business_id', true));
create policy "cliente cria itens via RPC" on public.order_items for insert to anon, authenticated
with check (order_id::text = current_setting('app.customer_order_id', true));
grant insert on public.orders, public.order_items to anon, authenticated;

create or replace function public.create_customer_order(
  p_business_id uuid,
  p_customer_name text,
  p_locality_id uuid,
  p_address_note text,
  p_payment_method text,
  p_cash_amount numeric,
  p_items jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_order_id uuid;
  v_item jsonb;
  v_product record;
  v_complement record;
  v_locality record;
  v_qty integer;
  v_regular_count integer;
  v_coverage_count integer;
  v_additional numeric(10,2);
  v_unit_price numeric(10,2);
  v_subtotal numeric(10,2) := 0;
  v_total numeric(10,2);
  v_complement_id uuid;
  v_note text;
  v_item_complements jsonb;
begin
  if p_business_id is null or p_locality_id is null
     or coalesce(trim(p_address_note), '') = ''
     or length(p_address_note) > 500
     or p_items is null
     or jsonb_typeof(p_items) <> 'array' then
    raise exception 'Dados do pedido inválidos.';
  end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'O pedido não pode estar vazio.'; end if;

  if not exists (
    select 1
    from public.businesses b
    where b.id = p_business_id
      and (
        (
          (b.auto_open_time is null or b.auto_close_time is null or b.auto_open_time = b.auto_close_time)
          and b.is_open
        )
        or (
          b.auto_open_time is not null
          and b.auto_close_time is not null
          and b.auto_open_time <> b.auto_close_time
          and (
            (b.auto_open_time < b.auto_close_time and (now() at time zone 'America/Fortaleza')::time >= b.auto_open_time and (now() at time zone 'America/Fortaleza')::time < b.auto_close_time)
            or
            (b.auto_open_time > b.auto_close_time and ((now() at time zone 'America/Fortaleza')::time >= b.auto_open_time or (now() at time zone 'America/Fortaleza')::time < b.auto_close_time))
          )
        )
      )
  ) then
    raise exception 'A loja não está aceitando pedidos.';
  end if;

  select l.name, l.fee into v_locality
  from public.localities l
  where l.id = p_locality_id and l.business_id = p_business_id and l.active;
  if not found then raise exception 'Localidade inválida.'; end if;

  if not exists (
    select 1 from public.payment_methods m
    where m.business_id = p_business_id and m.method = p_payment_method and m.active
  ) then raise exception 'Forma de pagamento indisponível.'; end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_qty := coalesce((v_item ->> 'quantity')::integer, 0);
    if v_qty < 1 or v_qty > 50 or not (v_item ? 'product_id') then
      raise exception 'Item inválido.';
    end if;
    select p.id, p.name, p.price, p.included_complements, p.includes_coverage into v_product
    from public.products p
    where p.id = (v_item ->> 'product_id')::uuid and p.business_id = p_business_id and p.active;
    if not found then raise exception 'Produto indisponível.'; end if;

    if jsonb_typeof(coalesce(v_item -> 'complement_ids', '[]'::jsonb)) <> 'array' then
      raise exception 'Complementos inválidos.';
    end if;
    v_regular_count := 0; v_coverage_count := 0; v_additional := 0; v_item_complements := '[]'::jsonb;
    for v_complement_id in select value::uuid from jsonb_array_elements_text(coalesce(v_item -> 'complement_ids', '[]'::jsonb))
    loop
      select c.id, c.name, c.price, c.kind into v_complement
      from public.complements c
      where c.id = v_complement_id and c.business_id = p_business_id and c.active;
      if not found then raise exception 'Complemento indisponível.'; end if;
      if v_complement.kind = 'cobertura' then
        v_coverage_count := v_coverage_count + 1;
        if not v_product.includes_coverage or v_coverage_count > 1 then raise exception 'Cobertura inválida.'; end if;
        v_additional := v_additional + v_complement.price;
      else
        v_regular_count := v_regular_count + 1;
        if v_regular_count > 30 then raise exception 'Limite de complementos excedido.'; end if;
        if v_regular_count > v_product.included_complements then v_additional := v_additional + v_complement.price; end if;
      end if;
      v_item_complements := v_item_complements || jsonb_build_array(jsonb_build_object('name', v_complement.name, 'price', case when v_complement.kind = 'complemento' and v_regular_count <= v_product.included_complements then 0 else v_complement.price end));
    end loop;
    v_note := nullif(trim(coalesce(v_item ->> 'note', '')), '');
    if v_note is not null then
      if length(v_note) > 200 then raise exception 'Observação muito longa.'; end if;
      v_item_complements := v_item_complements || jsonb_build_array(jsonb_build_object('name', 'Observação: ' || v_note, 'price', 0));
    end if;
    v_unit_price := v_product.price + v_additional;
    v_subtotal := v_subtotal + (v_unit_price * v_qty);
  end loop;

  v_total := v_subtotal + v_locality.fee;
  if p_payment_method = 'cash' and coalesce(p_cash_amount, 0) < v_total then
    raise exception 'O valor em dinheiro não cobre o total.';
  end if;

  v_order_id := gen_random_uuid();
  perform set_config('app.customer_order_business_id', p_business_id::text, true);
  perform set_config('app.customer_order_id', v_order_id::text, true);
  insert into public.orders (id, business_id, customer_name, locality_name, address_note, payment_method, cash_amount, change_amount, subtotal, delivery_fee, total)
  values (v_order_id, p_business_id, nullif(trim(coalesce(p_customer_name, '')), ''), v_locality.name, trim(p_address_note), p_payment_method,
    case when p_payment_method = 'cash' then p_cash_amount else null end,
    case when p_payment_method = 'cash' then p_cash_amount - v_total else null end,
    v_subtotal, v_locality.fee, v_total);

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    select p.name, p.price, p.included_complements into v_product
    from public.products p where p.id = (v_item ->> 'product_id')::uuid;
    v_regular_count := 0; v_additional := 0; v_item_complements := '[]'::jsonb;
    for v_complement_id in select value::uuid from jsonb_array_elements_text(coalesce(v_item -> 'complement_ids', '[]'::jsonb))
    loop
      select c.name, c.price, c.kind into v_complement from public.complements c where c.id = v_complement_id;
      if v_complement.kind = 'complemento' then
        v_regular_count := v_regular_count + 1;
        if v_regular_count > v_product.included_complements then v_additional := v_additional + v_complement.price; end if;
      else
        v_additional := v_additional + v_complement.price;
      end if;
      v_item_complements := v_item_complements || jsonb_build_array(jsonb_build_object('name', v_complement.name, 'price', case when v_complement.kind = 'complemento' and v_regular_count <= v_product.included_complements then 0 else v_complement.price end));
    end loop;
    v_note := nullif(trim(coalesce(v_item ->> 'note', '')), '');
    if v_note is not null then v_item_complements := v_item_complements || jsonb_build_array(jsonb_build_object('name', 'Observação: ' || v_note, 'price', 0)); end if;
    insert into public.order_items (order_id, product_name, unit_price, quantity, complements)
    values (v_order_id, v_product.name, v_product.price + v_additional, (v_item ->> 'quantity')::integer, v_item_complements);
  end loop;
  return v_order_id;
end;
$$;

revoke all on function public.create_customer_order(uuid, text, uuid, text, text, numeric, jsonb) from public;
grant execute on function public.create_customer_order(uuid, text, uuid, text, text, numeric, jsonb) to anon, authenticated;
