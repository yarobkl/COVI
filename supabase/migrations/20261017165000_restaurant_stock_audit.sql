-- COVI — auditable restaurant drink inventory. STAGED / never applied live.
-- Stock quantity and reserved quantity are cashier-critical and must not be
-- writable through direct browser UPDATE. Description and price remain editable.
revoke update on public.restaurant_menu_items from authenticated;
grant update (name, category, price_xaf, available)
  on public.restaurant_menu_items to authenticated;

create table public.restaurant_drink_adjustments (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  menu_item_id uuid not null,
  quantity_delta integer not null check(quantity_delta<>0 and abs(quantity_delta)<=1000000),
  stock_after integer not null check(stock_after >= 0),
  reason text not null check(length(btrim(reason)) between 3 and 240),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key (shop_id,menu_item_id)
    references public.restaurant_menu_items(shop_id,id)
);
create index restaurant_adjustments_by_shop
  on public.restaurant_drink_adjustments(shop_id,created_at desc);

alter table public.restaurant_drink_adjustments enable row level security;
revoke all on public.restaurant_drink_adjustments from public,anon,authenticated;
grant select on public.restaurant_drink_adjustments to authenticated;
create policy drink_adjustments_owner_read
  on public.restaurant_drink_adjustments
  for select to authenticated
  using (
    exists(
      select 1 from public.shops s
      where s.id=shop_id and s.owner_id=(select auth.uid())
        and s.business_kind='restaurant'
    )
  );

create function public.restaurant_adjust_drink_stock(
  p_shop uuid, p_item uuid, p_delta integer, p_reason text
) returns integer
language plpgsql security definer set search_path=''
as $$
declare v_remaining integer;
begin
 if auth.uid() is null or not exists (
   select 1 from public.shops s
    where s.id=p_shop and s.owner_id=auth.uid() and s.business_kind='restaurant'
 ) then raise exception 'Access denied' using errcode='42501'; end if;
 if p_delta is null or p_delta=0 or abs(p_delta)>1000000 then
   raise exception 'Invalid stock adjustment'; end if;
 if length(btrim(coalesce(p_reason,''))) not between 3 and 240 then
   raise exception 'A reason is required for stock adjustment'; end if;
 update public.restaurant_menu_items m
   set drink_stock=m.drink_stock+p_delta
   where m.shop_id=p_shop and m.id=p_item and m.kind='drink'
     and m.drink_stock+p_delta between m.reserved_drink_stock and 1000000
   returning m.drink_stock into v_remaining;
 if not found then
   raise exception 'Insufficient unreserved stock or incompatible article';
 end if;
 insert into public.restaurant_drink_adjustments(
   shop_id,menu_item_id,quantity_delta,stock_after,reason,created_by
 ) values(p_shop,p_item,p_delta,v_remaining,btrim(p_reason),auth.uid());
 return v_remaining;
end;
$$;
revoke all on function public.restaurant_adjust_drink_stock(uuid,uuid,integer,text)
 from public,anon,authenticated;
grant execute on function public.restaurant_adjust_drink_stock(uuid,uuid,integer,text)
 to authenticated;

comment on table public.restaurant_drink_adjustments is
 'Owner adjustments and deliveries: stock movement audit, never an automated sale or a payment.';
