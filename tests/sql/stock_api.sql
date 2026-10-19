-- Verifications atomiques de l'API Stock. Toutes les donnees sont annulees.
\set ON_ERROR_STOP 1
begin;
create function pg_temp.check(p_ok boolean, p_label text) returns void language plpgsql as $$
begin
  if p_ok is not true then raise exception 'FAIL %', p_label; end if;
  raise notice 'ok %', p_label;
end $$;
create function pg_temp.fails(p_sql text, p_message text) returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  if sqlerrm not like '%' || p_message || '%' then
    raise exception 'expected %, got %', p_message, sqlerrm;
  end if;
  return true;
end $$;
insert into auth.users(id) values
  ('b1000000-0000-0000-0000-000000000001'),
  ('b1000000-0000-0000-0000-000000000002');
insert into public.shops(id, owner_id, name) values
  ('b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'API stock');
insert into public.products(id,shop_id,name,quantity_on_hand,initial_sale_price) values
  ('b3000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001',
   'Test API stock', 3, 5000);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000001', true);
select pg_temp.check(not has_function_privilege('anon',
  'public.adjust_product_stock_if_unchanged(uuid,integer,integer,text,text)', 'execute'),
  'Anonymous forbidden');
select public.adjust_product_stock_if_unchanged(
  'b3000000-0000-0000-0000-000000000001', 3, 5, 'restock', 'Reception');
select pg_temp.check((select quantity_on_hand=5 from public.products
  where id='b3000000-0000-0000-0000-000000000001'), 'Atomic write updated the stock');
select pg_temp.check((select count(*)=1 from public.stock_movements
  where product_id='b3000000-0000-0000-0000-000000000001'), 'Stock movement audit retained');
select pg_temp.check(pg_temp.fails(
  $q$select public.adjust_product_stock_if_unchanged(
   'b3000000-0000-0000-0000-000000000001',3,8,'restock')$q$, 'STOCK_CONFLICT'),
  'Stale updates rejected');
select pg_temp.check((select quantity_on_hand=5 from public.products
  where id='b3000000-0000-0000-0000-000000000001'), 'Conflict does not write');
select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000002', true);
select pg_temp.check(pg_temp.fails(
  $q$select public.adjust_product_stock_if_unchanged(
   'b3000000-0000-0000-0000-000000000001',5,2,'loss')$q$, 'Shop not found'),
  'Another shop user cannot adjust');
rollback;
