-- Suppression de compte : demande (mot + code du responsable), 30 jours d'annulation, purge.
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

\set shop '10000000-0000-0000-0000-0000000000d1'
\set kept_shop '10000000-0000-0000-0000-0000000000d2'
\set owner '00000000-0000-0000-0000-0000000000d1'
\set neighbour '00000000-0000-0000-0000-0000000000d2'
\set product '30000000-0000-0000-0000-0000000000d1'
insert into auth.users(id) values (:'owner'), (:'neighbour');
insert into public.shops(id, owner_id, name) values
  (:'shop', :'owner', 'Boutique à supprimer'), (:'kept_shop', :'neighbour', 'Boutique voisine');
insert into public.products(id, shop_id, name, initial_sale_price, quantity_on_hand)
values (:'product', :'shop', 'Robe', 10000, 5),
       (gen_random_uuid(), :'kept_shop', 'Jean voisin', 8000, 2);
insert into public.public_order_channels(shop_id, token, enabled)
values (:'shop', gen_random_uuid(), true);

set local role authenticated;
select set_config('request.jwt.claim.sub', :'owner', true);
select public.set_owner_pin(:'shop', '4876');
-- Une vraie journée : un caissier, sa caisse, une vente, une correction de stock.
select public.create_shared_cashier(:'shop', 'Awa', '5937', 0, false) ->> 'id' as awa \gset
select (public.open_shared_cashier_till(:'shop', :'awa', '5937')) ->> 'token' as till \gset
select public.record_sale(:'shop', :'product', 1, 10000, 'cash',
  '40000000-0000-0000-0000-0000000000d1', :'till');
select public.adjust_product_stock(:'product', 6, 'restock');
reset role;
-- Une commande en ligne payée, liée à la vente et au produit (les liens qui bloquent une cascade).
insert into public.public_orders(id, shop_id, reference, operation_id, channel, customer_name,
  customer_phone, fulfillment, payment_method, status, sale_id, confirmed_by, cashier_profile_id,
  confirmed_at, paid_method)
select '50000000-0000-0000-0000-0000000000d1', :'shop', 'C-D3K0A1', gen_random_uuid(), 'qr',
  'Cliente', '+242060000000', 'pickup', 'cash', 'paid', v.id, :'owner', :'awa', now(), 'cash'
from public.sales v where v.shop_id = :'shop' limit 1;
insert into public.public_order_lines(order_id, shop_id, position, quantity, product_id)
values ('50000000-0000-0000-0000-0000000000d1', :'shop', 1, 1, :'product');
set local role authenticated;

select pg_temp.check(not has_function_privilege('anon', 'public.request_account_deletion(text,text)',
  'execute'), 'Anonymous cannot request a deletion');
select pg_temp.check(not has_function_privilege('authenticated', 'public.account_purge_due(text)',
  'execute'), 'Only the purge function lists accounts to purge');
select pg_temp.check((public.my_account_deletion() ->> 'pending')::boolean = false,
  'No deletion pending at first');

-- Confirmation et code du responsable
select pg_temp.check(public.request_account_deletion('oui', '4876') ->> 'status' = 'confirm',
  'The word SUPPRIMER is required');
select pg_temp.check(public.request_account_deletion('SUPPRIMER', '0000') ->> 'status' = 'invalid',
  'A wrong owner code is refused');
select pg_temp.check((public.my_account_deletion() ->> 'pending')::boolean = false,
  'Nothing scheduled after a refusal');
select pg_temp.check(public.request_account_deletion('supprimer ', '4876') ->> 'status' = 'ok',
  'Deletion scheduled with the word and the owner code');
select pg_temp.check((public.my_account_deletion() ->> 'pending')::boolean,
  'Deletion pending');
select pg_temp.check((public.my_account_deletion() ->> 'purge_after')::timestamptz
  between now() + interval '29 days' and now() + interval '31 days', 'Purge in 30 days');
reset role;
select pg_temp.check((select not enabled from public.public_order_channels where shop_id = :'shop'),
  'Online orders closed at once');
set local role authenticated;
select pg_temp.check(public.request_account_deletion('SUPPRIMER', '4876') ->> 'status' = 'ok',
  'Asking twice keeps the first date');

-- Annulation : tout revient
select public.cancel_account_deletion();
select pg_temp.check((public.my_account_deletion() ->> 'pending')::boolean = false,
  'Cancelled');
reset role;
select pg_temp.check((select enabled from public.public_order_channels where shop_id = :'shop'),
  'Cancelling reopens online orders');
set local role authenticated;
select pg_temp.check(public.request_account_deletion('SUPPRIMER', '4876') ->> 'status' = 'ok',
  'Deletion scheduled again');

-- La purge : jeton obligatoire, rien avant 30 jours
reset role;
select decrypted_secret as purge_token from vault.decrypted_secrets
where name = 'covi_account_purge_token' \gset
set local role service_role;
select pg_temp.check(pg_temp.fails($q$select public.account_purge_due('faux')$q$,
  'Invalid purge token'), 'Wrong purge token refused');
select pg_temp.check(public.account_purge_due(:'purge_token') = '[]'::jsonb,
  'Nothing to purge before 30 days');
reset role;
update public.account_deletion_requests set purge_after = now() - interval '1 minute';
set local role service_role;
select pg_temp.check(public.account_purge_due(:'purge_token') @> pg_catalog.jsonb_build_array(
  pg_catalog.jsonb_build_object('user_id', :'owner', 'shop_ids', pg_catalog.jsonb_build_array(:'shop'))),
  'The due account is listed with its shop');
reset role;

-- Ce que fait la fonction Edge à la fin : effacer les boutiques, puis supprimer le compte.
set local role service_role;
select pg_temp.check(pg_temp.fails(format($q$select public.account_purge_shops('faux', %L)$q$,
  :'owner'), 'Invalid purge token'), 'Shop purge needs the token');
select pg_temp.check(pg_temp.fails(format($q$select public.account_purge_shops(%L, %L)$q$,
  :'purge_token', :'neighbour'), 'Account not due'), 'Only a due account can be purged');
select pg_temp.check(public.account_purge_shops(:'purge_token', :'owner') = 1, 'One shop erased');
reset role;
delete from auth.users where id = :'owner';
select pg_temp.check(not exists (select 1 from public.shops where id = :'shop')
  and not exists (select 1 from public.products where shop_id = :'shop')
  and not exists (select 1 from public.sales where shop_id = :'shop')
  and not exists (select 1 from public.stock_movements where shop_id = :'shop')
  and not exists (select 1 from public.shop_cashier_profiles where shop_id = :'shop')
  and not exists (select 1 from public.public_orders where shop_id = :'shop')
  and not exists (select 1 from public.account_deletion_requests where user_id = :'owner'),
  'Shop, stock, sales, cashiers and the request are erased');
select pg_temp.check((select count(*) = 1 from public.products where shop_id = :'kept_shop')
  and exists (select 1 from public.shops where id = :'kept_shop'),
  'The neighbouring shop is untouched');
rollback;
