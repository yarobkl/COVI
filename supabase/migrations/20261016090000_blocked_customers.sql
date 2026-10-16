-- Modération des commandes en ligne (App Store, règle 1.2 « contenu des utilisateurs ») : la
-- boutique peut bloquer le numéro d'un client abusif ; ses nouvelles commandes sont refusées sans
-- lui dire pourquoi (même message qu'un lien coupé). Le numéro est comparé sur ses 9 derniers
-- chiffres : « +242 06 123 45 67 » et « 061234567 » sont le même client.

create or replace function public.customer_phone_key(p_phone text)
returns text
language sql
immutable
set search_path to ''
as $$
  select nullif(pg_catalog.right(pg_catalog.regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 9), '')
$$;

create table if not exists public.shop_blocked_customers (
  shop_id uuid not null references public.shops(id) on delete cascade,
  phone_key text not null check (phone_key ~ '^[0-9]{1,9}$'),
  phone_display text not null check (char_length(phone_display) between 1 and 32),
  customer_name text check (customer_name is null or char_length(customer_name) <= 60),
  blocked_at timestamptz not null default now(),
  primary key (shop_id, phone_key)
);
alter table public.shop_blocked_customers enable row level security;
revoke all on public.shop_blocked_customers from anon, authenticated;

create or replace function public.public_orders_refuse_blocked()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if exists (select 1 from public.shop_blocked_customers b
             where b.shop_id = new.shop_id
               and b.phone_key = public.customer_phone_key(new.customer_phone)) then
    raise exception 'Order link unavailable' using errcode = '42501';
  end if;
  return new;
end;
$$;
drop trigger if exists public_orders_refuse_blocked on public.public_orders;
create trigger public_orders_refuse_blocked
  before insert on public.public_orders
  for each row execute function public.public_orders_refuse_blocked();

/** Bloque le client d'une commande ; la commande encore ouverte est refusée. */
create or replace function public.block_order_customer(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_order public.public_orders%rowtype;
  v_key text;
begin
  select * into v_order from public.public_orders where id = p_order_id for update;
  if not found then raise exception 'Order not found' using errcode = '42501'; end if;
  perform public.assert_shop_owner(v_order.shop_id);
  v_key := public.customer_phone_key(v_order.customer_phone);
  if v_key is null then raise exception 'Invalid customer phone'; end if;
  insert into public.shop_blocked_customers(shop_id, phone_key, phone_display, customer_name)
  values (v_order.shop_id, v_key, v_order.customer_phone, v_order.customer_name)
  on conflict (shop_id, phone_key) do nothing;
  if v_order.status in ('new', 'accepted') then
    update public.public_orders
    set status = 'rejected', reject_reason = 'Client bloqué par la boutique',
        decided_at = coalesce(decided_at, now())
    where id = v_order.id;
  end if;
  perform public.shop_audit(v_order.shop_id, 'customer_blocked', v_order.id::text,
    pg_catalog.jsonb_build_object('phone_key', v_key));
  return pg_catalog.jsonb_build_object('phoneKey', v_key);
end;
$$;

create or replace function public.list_blocked_customers(p_shop_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
begin
  perform public.assert_shop_owner(p_shop_id);
  return coalesce((
    select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'phoneKey', b.phone_key, 'phone', b.phone_display, 'name', b.customer_name,
      'blockedAt', b.blocked_at) order by b.blocked_at desc)
    from public.shop_blocked_customers b where b.shop_id = p_shop_id
  ), '[]'::jsonb);
end;
$$;

create or replace function public.unblock_customer(p_shop_id uuid, p_phone_key text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform public.assert_shop_owner(p_shop_id);
  delete from public.shop_blocked_customers where shop_id = p_shop_id and phone_key = p_phone_key;
  if found then
    perform public.shop_audit(p_shop_id, 'customer_unblocked', null,
      pg_catalog.jsonb_build_object('phone_key', p_phone_key));
  end if;
end;
$$;

revoke all on function public.customer_phone_key(text) from public, anon, authenticated;
revoke all on function public.public_orders_refuse_blocked() from public, anon, authenticated;
revoke all on function public.block_order_customer(uuid) from public, anon;
revoke all on function public.list_blocked_customers(uuid) from public, anon;
revoke all on function public.unblock_customer(uuid, text) from public, anon;
grant execute on function public.block_order_customer(uuid) to authenticated;
grant execute on function public.list_blocked_customers(uuid) to authenticated;
grant execute on function public.unblock_customer(uuid, text) to authenticated;
