-- Canal client QR / réseaux sociaux : commandes publiques et confirmation du règlement en caisse
-- (migration 20261014230000_public_order_channel). Transaction annulée : la base reste vierge.
\set ON_ERROR_STOP 1
begin;
create function pg_temp.check(p_ok boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_ok is not true then raise exception 'FAIL %', p_label; end if;
  raise notice 'ok  %', p_label;
end $$;
create function pg_temp.fails(p_sql text, p_label text) returns void
language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    raise notice 'ok  %  [%]', p_label, sqlerrm;
    return;
  end;
  raise exception 'FAIL % : aurait dû échouer', p_label;
end $$;

\set shop '10000000-0000-0000-0000-0000000000f1'
\set other '10000000-0000-0000-0000-0000000000f2'
\set owner '00000000-0000-0000-0000-0000000000f1'
\set intruder '00000000-0000-0000-0000-0000000000f2'
\set jean '30000000-0000-0000-0000-0000000000f1'
\set robe '30000000-0000-0000-0000-0000000000f2'
\set piece '30000000-0000-0000-0000-0000000000f3'
\set testp '30000000-0000-0000-0000-0000000000f4'
\set foreign '30000000-0000-0000-0000-0000000000f5'
\set empty '30000000-0000-0000-0000-0000000000f6'
insert into auth.users(id) values (:'owner'), (:'intruder');
insert into public.shops(id, owner_id, name, city) values
  (:'shop', :'owner', 'Boutique QR', 'Brazzaville'),
  (:'other', :'intruder', 'Autre boutique', 'Pointe-Noire');
insert into public.products(id, shop_id, name, category, initial_sale_price, quantity_on_hand,
                            is_unique_piece, is_test) values
  (:'jean', :'shop', 'Jean bleu', 'Pantalons', 10000, 5, false, false),
  (:'robe', :'shop', 'Robe wax', 'Robes', 15000, 2, false, false),
  (:'piece', :'shop', 'Veste unique', 'Vestes', 30000, 1, true, false),
  (:'testp', :'shop', 'Article de test', null, 1000, 9, false, true),
  (:'empty', :'shop', 'Rupture', null, 5000, 0, false, false),
  (:'foreign', :'other', 'Article autre boutique', null, 2000, 4, false, false);

-- Droits ---------------------------------------------------------------------------------------
select pg_temp.check(
  not has_function_privilege('anon', 'public.submit_public_order(uuid,text,uuid,text,text,text,text,text,text,jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.submit_public_order(uuid,text,uuid,text,text,text,text,text,text,jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.get_public_order_catalog(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.get_public_order_catalog(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.get_public_order_status(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.consume_public_order_quota(text,text)', 'execute')
  and not has_function_privilege('anon', 'public.attach_public_order_reference(uuid,uuid,uuid)', 'execute'),
  'Visiteurs et comptes connectés : aucun accès direct aux fonctions publiques (passerelle seule)');
select pg_temp.check(
  has_function_privilege('service_role', 'public.submit_public_order(uuid,text,uuid,text,text,text,text,text,text,jsonb)', 'execute')
  and has_function_privilege('service_role', 'public.get_public_order_catalog(uuid)', 'execute'),
  'La passerelle (service_role) peut appeler les fonctions publiques');
select pg_temp.check(
  not has_function_privilege('anon', 'public.confirm_public_order_payment(uuid,text,text,boolean,jsonb,text)', 'execute')
  and has_function_privilege('authenticated', 'public.confirm_public_order_payment(uuid,text,text,boolean,jsonb,text)', 'execute'),
  'Confirmation du règlement fermée aux visiteurs');
select pg_temp.check(
  not has_table_privilege('anon', 'public.public_orders', 'select')
  and not has_table_privilege('anon', 'public.public_order_channels', 'select')
  and not has_table_privilege('authenticated', 'public.public_order_channels', 'select')
  and not has_table_privilege('authenticated', 'public.public_orders', 'insert')
  and not has_table_privilege('authenticated', 'public.public_orders', 'update')
  and not has_table_privilege('authenticated', 'public.public_order_quota', 'select'),
  'Tables : pas de lecture anonyme, pas d''écriture directe, jetons de canal invisibles');
select pg_temp.check(
  (select bool_and(p.prosecdef and p.proconfig = array['search_path=""'])
   from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('consume_public_order_quota', 'get_public_order_catalog',
       'submit_public_order', 'attach_public_order_reference', 'get_public_order_status',
       'get_public_order_channel', 'configure_public_order_channel', 'rotate_public_order_channel',
       'list_public_orders', 'accept_public_order', 'reject_public_order',
       'confirm_public_order_payment')),
  'Fonctions : SECURITY DEFINER avec search_path vide');

-- Administration du canal (propriétaire) ---------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', :'intruder', true);
select pg_temp.fails($$select public.configure_public_order_channel(
  '10000000-0000-0000-0000-0000000000f1', true, true, null)$$,
  'Un autre compte ne peut pas activer le canal de la boutique');
select set_config('request.jwt.claim.sub', :'owner', true);
select pg_temp.check(public.get_public_order_channel(:'shop') is null, 'Pas de canal par défaut');
select (public.configure_public_order_channel(:'shop', false, true, 'Retrait au marché Total'))->>'token' as token \gset
reset role;

-- Catalogue et dépôt (passerelle) ---------------------------------------------------------------
set local role service_role;
select pg_temp.check(public.get_public_order_catalog(:'token') is null, 'Canal désactivé : catalogue fermé');
select pg_temp.fails(format($$select public.submit_public_order(%L, 'qr', gen_random_uuid(), 'Awa',
  '+242 06 000 00 00', 'pickup', null, 'cash', null, '[{"description":"robe rouge","quantity":1}]')$$, :'token'),
  'Canal désactivé : aucune demande acceptée');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'owner', true);
select public.configure_public_order_channel(:'shop', true, true, 'Retrait au marché Total');
reset role;

set local role service_role;
select public.get_public_order_catalog(:'token') as catalog \gset
select pg_temp.check((:'catalog'::jsonb ->> 'shopName') = 'Boutique QR'
  and jsonb_array_length(:'catalog'::jsonb -> 'products') = 3,
  'Catalogue : seulement les articles réels en stock (ni test, ni rupture, ni autre boutique)');
select pg_temp.check(:'catalog' !~ 'quantity_on_hand|arrival|cost|Article de test|Rupture|autre boutique',
  'Catalogue : aucun coût, stock brut ou article caché');
select pg_temp.check(
  (select (e->>'maxQuantity')::int = 1 from jsonb_array_elements(:'catalog'::jsonb -> 'products') e
   where e->>'name' = 'Veste unique'),
  'Pièce unique : quantité commandable 1');
select pg_temp.check(public.get_public_order_catalog(gen_random_uuid()) is null, 'Jeton inconnu : rien');

select pg_temp.fails(format($$select public.submit_public_order(%L, 'qr', gen_random_uuid(), 'Awa',
  '+242 06 000 00 00', 'pickup', null, 'cash', null, %L)$$, :'token',
  format('[{"productId":"%s","quantity":1}]', :'foreign')),
  'Article d''une autre boutique refusé');
select pg_temp.fails(format($$select public.submit_public_order(%L, 'qr', gen_random_uuid(), 'Awa',
  '+242 06 000 00 00', 'pickup', null, 'cash', null, %L)$$, :'token',
  format('[{"productId":"%s","quantity":1}]', :'testp')),
  'Article de test refusé');
select pg_temp.fails(format($$select public.submit_public_order(%L, 'qr', gen_random_uuid(), 'Awa',
  '+242 06 000 00 00', 'pickup', null, 'cash', null, %L)$$, :'token',
  format('[{"productId":"%s","quantity":3}]', :'robe')),
  'Quantité supérieure au stock refusée');
select pg_temp.fails(format($$select public.submit_public_order(%L, 'qr', gen_random_uuid(), 'Awa',
  '+242 06 000 00 00', 'delivery', null, 'cash', null, '[{"description":"robe","quantity":1}]')$$, :'token'),
  'Livraison sans adresse refusée');
select pg_temp.fails(format($$select public.submit_public_order(%L, 'qr', gen_random_uuid(), 'Awa',
  '+242 06 000 00 00', 'pickup', null, 'bitcoin', null, '[{"description":"robe","quantity":1}]')$$, :'token'),
  'Moyen de paiement inconnu refusé');

\set op1 '40000000-0000-0000-0000-0000000000f1'
select public.submit_public_order(:'token', 'social', :'op1', 'Awa', '+242 06 000 00 00',
  'delivery', 'Moungali, rue 12', 'mobile_money', 'Vu sur TikTok',
  format('[{"productId":"%s","quantity":2,"proposedUnitPriceXaf":9500},{"productId":"%s","quantity":1},{"description":"ceinture noire","quantity":1}]',
         :'jean', :'robe')::jsonb) as order1 \gset
select (:'order1'::jsonb ->> 'orderId') as order_id, (:'order1'::jsonb ->> 'trackingToken') as tracking \gset
select pg_temp.check((:'order1'::jsonb ->> 'reference') ~ '^C-[0-9A-Z]{6}$'
  and (:'order1'::jsonb ->> 'status') = 'new'
  and (:'order1'::jsonb ->> 'amountXaf')::numeric = 34000,
  'Demande enregistrée : référence, statut « new », total indicatif');
select pg_temp.check(
  (select quantity_on_hand from public.products where id = :'jean') = 5
  and (select quantity_on_hand from public.products where id = :'robe') = 2
  and not exists (select 1 from public.sales where shop_id = :'shop'),
  'Une demande ne touche ni au stock ni aux ventes');
select pg_temp.check(
  (public.submit_public_order(:'token', 'social', :'op1', 'Awa', '+242 06 000 00 00',
    'delivery', 'Moungali, rue 12', 'mobile_money', 'Vu sur TikTok',
    format('[{"productId":"%s","quantity":2}]', :'jean')::jsonb) ->> 'orderId') = :'order_id',
  'Même operation_id renvoyé deux fois : une seule commande');

select public.get_public_order_status(:'tracking') as status1 \gset
select pg_temp.check((:'status1'::jsonb ->> 'status') = 'new' and (:'status1'::jsonb -> 'receipt') = 'null'::jsonb
  and :'status1' !~ '06 000|Moungali',
  'Suivi client : statut sans reçu ni coordonnées');
select pg_temp.check(public.get_public_order_status(gen_random_uuid()) is null, 'Jeton de suivi inconnu : rien');

select pg_temp.check(public.consume_public_order_quota(repeat('a', 32), 'order_source_minute')
  and public.consume_public_order_quota(repeat('a', 32), 'order_source_minute')
  and public.consume_public_order_quota(repeat('a', 32), 'order_source_minute')
  and not public.consume_public_order_quota(repeat('a', 32), 'order_source_minute'),
  'Quota : 3 demandes par minute et par source, la 4e est refusée');
select pg_temp.fails($$select public.consume_public_order_quota('xyz', 'order_source_minute')$$,
  'Quota : empreinte invalide refusée');
reset role;

-- Commandes reçues et confirmation en caisse ------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', :'intruder', true);
select pg_temp.check((select count(*) from public.public_orders) = 0,
  'RLS : un autre compte ne voit pas les commandes de la boutique');
select pg_temp.fails(format($$select public.list_public_orders(%L)$$, :'shop'),
  'Un autre compte ne peut pas lister les commandes');
select pg_temp.fails(format($$select public.accept_public_order(%L)$$, :'order_id'),
  'Un autre compte ne peut pas accepter la commande');

select set_config('request.jwt.claim.sub', :'owner', true);
select pg_temp.check((select count(*) from public.public_orders) = 1,
  'RLS : le propriétaire voit sa commande (temps réel)');
select public.list_public_orders(:'shop') as inbox \gset
select pg_temp.check(jsonb_array_length(:'inbox'::jsonb) = 1
  and jsonb_array_length(:'inbox'::jsonb -> 0 -> 'lines') = 3,
  'Commandes reçues : la demande et ses trois lignes');
select pg_temp.check(public.accept_public_order(:'order_id') = 'accepted', 'Commande acceptée');

-- Caissiers PIN : le compte partagé ne peut pas encaisser sans PIN.
select public.set_owner_pin(:'shop', '4876');
select public.create_shared_cashier(:'shop', 'Awa caisse', '5937', 10, false) ->> 'id' as cashier \gset
select (public.open_shared_cashier_till(:'shop', :'cashier', '5937')) ->> 'token' as till \gset
select l.id as line_jean from public.public_order_lines l where l.order_id = :'order_id' and l.product_id = :'jean' \gset
select l.id as line_robe from public.public_order_lines l where l.order_id = :'order_id' and l.product_id = :'robe' \gset
select l.id as line_free from public.public_order_lines l where l.order_id = :'order_id' and l.product_id is null \gset

\set lines_ok '[{"lineId":"' :line_jean '","productId":"' :jean '","unitPriceXaf":9500},{"lineId":"' :line_robe '","productId":"' :robe '","unitPriceXaf":15000},{"lineId":"' :line_free '","productId":"' :piece '","unitPriceXaf":30000}]'
select pg_temp.fails(format($$select public.confirm_public_order_payment(%L, 'mobile_money', 'MP241014.1234', true, %L, null)$$,
  :'order_id', :'lines_ok'), 'Sans PIN de caissier : confirmation refusée');
select pg_temp.fails(format($$select public.confirm_public_order_payment(%L, 'mobile_money', null, false, %L, %L)$$,
  :'order_id', :'lines_ok', :'till'), 'Règlement non vérifié : confirmation refusée');
select pg_temp.fails(format($$select public.confirm_public_order_payment(%L, 'mobile_money', null, true, %L, %L)$$,
  :'order_id', format('[{"lineId":"%s","productId":"%s","unitPriceXaf":9500}]', :'line_jean', :'jean'), :'till'),
  'Toutes les lignes doivent être confirmées');
select pg_temp.fails(format($$select public.confirm_public_order_payment(%L, 'mobile_money', null, true, %L, %L)$$,
  :'order_id', replace(:'lines_ok', '"unitPriceXaf":9500', '"unitPriceXaf":5000'), :'till'),
  'Prix sous la remise maximale du caissier refusé');
select pg_temp.fails(format($$select public.confirm_public_order_payment(%L, 'mobile_money', null, true, %L, %L)$$,
  :'order_id', replace(:'lines_ok', format('"productId":"%s","unitPriceXaf":15000', :'robe'),
                       format('"productId":"%s","unitPriceXaf":15000', :'foreign')), :'till'),
  'Ligne d''article remplacée par un autre article : refusée');
select pg_temp.check(not exists (select 1 from public.sales where shop_id = :'shop')
  and (select quantity_on_hand from public.products where id = :'jean') = 5,
  'Les refus n''ont créé aucune vente ni mouvement de stock');

select public.confirm_public_order_payment(:'order_id', 'mobile_money', 'MP241014.1234', true,
  :'lines_ok', :'till') as confirmed \gset
select (:'confirmed'::jsonb ->> 'saleId') as sale_id \gset
select pg_temp.check(
  (select status = 'paid' and paid_method = 'mobile_money' and payment_reference = 'MP241014.1234'
     and cashier_profile_id = :'cashier' and sale_id = :'sale_id'
   from public.public_orders where id = :'order_id'),
  'Règlement confirmé : commande payée, attribuée au caissier, référence saisie par le caissier');
select pg_temp.check(
  (select cashier_profile_id = :'cashier' and total_amount = 64000 and payment_method = 'mobile_money'
   from public.sales where id = :'sale_id')
  and (select quantity_on_hand from public.products where id = :'jean') = 3
  and (select quantity_on_hand from public.products where id = :'robe') = 1
  and (select quantity_on_hand = 0 and status = 'sold' from public.products where id = :'piece'),
  'Vente enregistrée une fois, stock décrémenté à la confirmation seulement');
select pg_temp.check(
  (public.confirm_public_order_payment(:'order_id', 'mobile_money', 'MP241014.1234', true, :'lines_ok', :'till')
    ->> 'alreadyConfirmed')::boolean
  and (select count(*) from public.sales where shop_id = :'shop') = 1
  and (select quantity_on_hand from public.products where id = :'jean') = 3,
  'Double confirmation : aucune seconde vente, aucun second décrément');
select pg_temp.fails(format($$select public.reject_public_order(%L, 'trop tard')$$, :'order_id'),
  'Une commande payée ne peut plus être refusée');
reset role;

set local role service_role;
select public.get_public_order_status(:'tracking') as status2 \gset
select pg_temp.check((:'status2'::jsonb ->> 'status') = 'paid'
  and (:'status2'::jsonb -> 'receipt' ->> 'totalXaf')::numeric = 64000
  and (:'status2'::jsonb -> 'receipt' ->> 'cashierName') = 'Awa caisse'
  and (:'status2'::jsonb -> 'receipt' ->> 'method') = 'mobile_money',
  'Suivi client : reçu après confirmation en caisse');

-- Refus et renouvellement du lien ------------------------------------------------------------------
select (public.submit_public_order(:'token', 'qr', gen_random_uuid(), 'Bema', '066000000', 'pickup',
  null, 'cash', null, '[{"description":"chemise","quantity":1}]')) ->> 'orderId' as order2 \gset
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'owner', true);
select pg_temp.check(public.reject_public_order(:'order2', 'Article épuisé') = 'rejected', 'Commande refusée');
select pg_temp.fails(format($$select public.confirm_public_order_payment(%L, 'cash', null, true, '[]', %L)$$,
  :'order2', :'till'), 'Commande refusée : encaissement impossible');
select (public.rotate_public_order_channel(:'shop')) ->> 'token' as token2 \gset
select pg_temp.check(:'token2' <> :'token', 'Nouveau lien généré');
reset role;
set local role service_role;
select pg_temp.check(public.get_public_order_catalog(:'token') is null
  and public.get_public_order_catalog(:'token2') is not null,
  'L''ancien QR ne fonctionne plus, le nouveau oui');
reset role;
rollback;
