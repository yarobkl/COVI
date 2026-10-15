-- Corrections de stock (motif obligatoire, trace) et archivage depuis « Modifier le produit ».
-- Données de test uniquement ; tout est annulé.
\set ON_ERROR_STOP 1
begin;
create function pg_temp.check(p_ok boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_ok is not true then raise exception 'FAIL %', p_label; end if;
  raise notice 'ok %', p_label;
end $$;
create function pg_temp.fails(p_sql text, p_message text) returns boolean
language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  if sqlerrm not like '%' || p_message || '%' then
    raise exception 'expected "%", got "%"', p_message, sqlerrm;
  end if;
  return true;
end $$;

\set shop '10000000-0000-0000-0000-0000000000f1'
\set other_shop '10000000-0000-0000-0000-0000000000f2'
\set owner '00000000-0000-0000-0000-0000000000f1'
\set stranger '00000000-0000-0000-0000-0000000000f2'
\set robe '30000000-0000-0000-0000-0000000000f1'
\set veste '30000000-0000-0000-0000-0000000000f2'
insert into auth.users(id) values (:'owner'), (:'stranger');
insert into public.shops(id, owner_id, name) values
  (:'shop', :'owner', 'Boutique stock'), (:'other_shop', :'stranger', 'Autre boutique');
insert into public.products(id, shop_id, name, initial_sale_price, quantity_on_hand, is_unique_piece)
values (:'robe', :'shop', 'Robe wax', 15000, 3, false),
       (:'veste', :'shop', 'Veste unique', 18000, 1, true);

set local role authenticated;
select set_config('request.jwt.claim.sub', :'owner', true);

-- La quantité ne s'écrit toujours pas directement : seulement par vente ou par correction.
select pg_temp.check(not has_column_privilege('authenticated', 'public.products',
  'quantity_on_hand', 'update'), 'Quantity still not directly writable');
select pg_temp.check(not has_table_privilege('authenticated', 'public.stock_movements', 'insert'),
  'Stock movements cannot be forged');
select pg_temp.check(not has_function_privilege('anon',
  'public.adjust_product_stock(uuid,integer,text,text)', 'execute'), 'Anonymous cannot adjust');

-- Réassort
select public.adjust_product_stock(:'robe', 8, 'restock', 'Carton du 15 octobre');
select pg_temp.check((select quantity_on_hand = 8 and status = 'active' from public.products
  where id = :'robe'), 'Restock raises stock');
select pg_temp.check((select reason = 'restock' and quantity_before = 3 and quantity_after = 8
  and actor_id = :'owner' and note = 'Carton du 15 octobre' from public.stock_movements
  where product_id = :'robe'), 'Restock is traced with before/after, author and note');

-- Motif cohérent avec le sens du mouvement
select pg_temp.check(pg_temp.fails(
  $q$select public.adjust_product_stock('30000000-0000-0000-0000-0000000000f1', 5, 'restock')$q$,
  'Restock must increase stock'), 'Restock cannot lower stock');
select pg_temp.check(pg_temp.fails(
  $q$select public.adjust_product_stock('30000000-0000-0000-0000-0000000000f1', 9, 'loss')$q$,
  'Loss must decrease stock'), 'Loss cannot raise stock');
select pg_temp.check(pg_temp.fails(
  $q$select public.adjust_product_stock('30000000-0000-0000-0000-0000000000f1', 8, 'count_error')$q$,
  'Stock unchanged'), 'Same quantity refused');
select pg_temp.check(pg_temp.fails(
  $q$select public.adjust_product_stock('30000000-0000-0000-0000-0000000000f1', -1, 'count_error')$q$,
  'Invalid stock quantity'), 'Negative stock refused');
select pg_temp.check(pg_temp.fails(
  $q$select public.adjust_product_stock('30000000-0000-0000-0000-0000000000f1', 4, 'cadeau')$q$,
  'Invalid stock reason'), 'Unknown reason refused');

-- Perte, vol, erreur de comptage
select public.adjust_product_stock(:'robe', 6, 'loss', 'Tachée');
select public.adjust_product_stock(:'robe', 5, 'theft');
select public.adjust_product_stock(:'robe', 7, 'count_error', 'Inventaire');
select pg_temp.check((select quantity_on_hand = 7 from public.products where id = :'robe'),
  'Loss, theft and count error applied in order');
select pg_temp.check((select count(*) = 4 from public.stock_movements where product_id = :'robe'),
  'Every correction leaves one movement');
select pg_temp.check((select count(*) = 4 from public.shop_audit_log
  where shop_id = :'shop' and action = 'stock_adjusted'), 'Corrections appear in the shop log');

-- Pièce unique : 0 ou 1 ; 0 → épuisé, 1 → de nouveau en vente
select pg_temp.check(pg_temp.fails(
  $q$select public.adjust_product_stock('30000000-0000-0000-0000-0000000000f2', 2, 'restock')$q$,
  'Unique piece quantity must be 1'), 'Unique piece cannot exceed 1');
select public.adjust_product_stock(:'veste', 0, 'loss');
select pg_temp.check((select quantity_on_hand = 0 and status = 'sold' from public.products
  where id = :'veste'), 'Stock at zero marks the product sold out');
select public.adjust_product_stock(:'veste', 1, 'count_error', 'Retrouvée');
select pg_temp.check((select status = 'active' from public.products where id = :'veste'),
  'Stock back above zero puts the product on sale again');

-- Archivage : retiré de la vente, stock intact ; on peut le remettre
select public.set_product_archived(:'robe', true);
select pg_temp.check((select status = 'archived' and quantity_on_hand = 7 from public.products
  where id = :'robe'), 'Archived product keeps its stock');
select public.adjust_product_stock(:'robe', 9, 'restock');
select pg_temp.check((select status = 'archived' from public.products where id = :'robe'),
  'Restocking an archived product keeps it archived');
select public.set_product_archived(:'robe', false);
select pg_temp.check((select status = 'active' from public.products where id = :'robe'),
  'Unarchived product is on sale again');

-- Un autre compte ne touche pas au stock de la boutique
select set_config('request.jwt.claim.sub', :'stranger', true);
select pg_temp.check(pg_temp.fails(
  $q$select public.adjust_product_stock('30000000-0000-0000-0000-0000000000f1', 1, 'loss')$q$,
  'Shop not found'), 'Stranger cannot adjust another shop stock');
select pg_temp.check(pg_temp.fails(
  $q$select public.set_product_archived('30000000-0000-0000-0000-0000000000f1', true)$q$,
  'Shop not found'), 'Stranger cannot archive another shop product');
select pg_temp.check((select count(*) = 0 from public.stock_movements),
  'Stranger cannot read the shop movements');
rollback;
