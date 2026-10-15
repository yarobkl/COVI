-- Paiement Mobile Money via OpenPay (migration 20261015130000_openpay_mobile_money).
-- Transaction annulée : la base reste vierge.
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

\set shop '10000000-0000-0000-0000-0000000000e1'
\set other '10000000-0000-0000-0000-0000000000e2'
\set owner '00000000-0000-0000-0000-0000000000e1'
\set intruder '00000000-0000-0000-0000-0000000000e2'
\set jean '30000000-0000-0000-0000-0000000000e1'
insert into auth.users(id) values (:'owner'), (:'intruder');
insert into public.shops(id, owner_id, name, city) values
  (:'shop', :'owner', 'Boutique MoMo', 'Brazzaville'),
  (:'other', :'intruder', 'Autre boutique', 'Pointe-Noire');
insert into public.products(id, shop_id, name, initial_sale_price, quantity_on_hand, is_unique_piece, is_test)
values (:'jean', :'shop', 'Jean', 10000, 5, false, false);

-- Droits ---------------------------------------------------------------------------------------
select pg_temp.check(
  not has_function_privilege('anon', 'public.request_order_mobile_payment(uuid,text,text,numeric)', 'execute')
  and not has_function_privilege('anon', 'public.set_shop_openpay_key(uuid,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.openpay_payment_context(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.record_openpay_status(uuid,text,text,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.openpay_payment_by_reference(text)', 'execute')
  and has_function_privilege('service_role', 'public.openpay_payment_context(uuid)', 'execute')
  and has_function_privilege('service_role', 'public.record_openpay_status(uuid,text,text,text)', 'execute'),
  'Clé et statut OpenPay : réservés à la fonction serveur ; demandes réservées aux comptes');
select pg_temp.check(
  not has_table_privilege('authenticated', 'public.shop_openpay_settings', 'select')
  and not has_table_privilege('anon', 'public.shop_openpay_settings', 'select')
  and not has_table_privilege('authenticated', 'public.public_order_payments', 'insert')
  and not has_table_privilege('authenticated', 'public.public_order_payments', 'update')
  and not has_table_privilege('anon', 'public.public_order_payments', 'select'),
  'Tables : clés illisibles, paiements en lecture seule pour le propriétaire');

-- Commande de test ----------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', :'owner', true);
select (public.configure_public_order_channel(:'shop', true, true, null))->>'token' as token \gset
reset role;
set local role service_role;
select (public.submit_public_order(:'token', 'qr', gen_random_uuid(), 'Awa', '+242 06 000 00 00',
  'pickup', null, 'mobile_money', null, '[{"description":"Jean L","quantity":1}]')) ->> 'orderId'
  as order_id \gset
reset role;

-- Configuration de la clé ---------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', :'owner', true);
select pg_temp.check((public.get_shop_openpay(:'shop') ->> 'configured')::boolean = false,
  'Sans clé : OpenPay non configuré');
select pg_temp.fails(format($$select public.request_order_mobile_payment(%L, 'MTN', '242066000000', 10000)$$,
  :'order_id'), 'Demande refusée tant que la boutique n''a pas de clé OpenPay');
select pg_temp.fails($$select public.set_shop_openpay_key('10000000-0000-0000-0000-0000000000e1', 'court')$$,
  'Clé trop courte refusée');
select public.set_shop_openpay_key(:'shop', 'opk_live_ABCDEFGH12345678') as settings \gset
select pg_temp.check((:'settings'::jsonb ->> 'configured')::boolean
  and (:'settings'::jsonb ->> 'keyHint') = '5678'
  and :'settings' !~ 'ABCDEFGH',
  'Clé enregistrée : seuls les 4 derniers caractères sont renvoyés');
select set_config('request.jwt.claim.sub', :'intruder', true);
select pg_temp.fails(format($$select public.get_shop_openpay(%L)$$, :'shop'),
  'Une autre boutique ne voit pas la configuration');
select pg_temp.fails(format($$select public.set_shop_openpay_key(%L, 'opk_live_INTRUDER000000')$$, :'shop'),
  'Une autre boutique ne peut pas remplacer la clé');
select pg_temp.fails(format($$select public.request_order_mobile_payment(%L, 'MTN', '242066000000', 10000)$$,
  :'order_id'), 'Une autre boutique ne peut pas demander le paiement');
reset role;
select pg_temp.check((select count(*) from vault.secrets) = 1
  and (select decrypted_secret from vault.decrypted_secrets) = 'opk_live_ABCDEFGH12345678',
  'Clé stockée dans le coffre (Vault), une seule fois');

-- Demande de paiement -------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', :'owner', true);
select pg_temp.fails(format($$select public.request_order_mobile_payment(%L, 'ORANGE', '242066000000', 10000)$$,
  :'order_id'), 'Opérateur inconnu refusé');
select pg_temp.fails(format($$select public.request_order_mobile_payment(%L, 'MTN', '066000000', 10000)$$,
  :'order_id'), 'Numéro hors format 242XXXXXXXXX refusé');
select pg_temp.fails(format($$select public.request_order_mobile_payment(%L, 'MTN', '242066000000', 10.5)$$,
  :'order_id'), 'Montant non entier refusé');
select public.request_order_mobile_payment(:'order_id', 'MTN', '242066000000', 10000) as pay1 \gset
select pg_temp.fails(format($$select public.request_order_mobile_payment(%L, 'MTN', '242066000000', 10000)$$,
  :'order_id'), 'Une seule demande en cours à la fois');
select pg_temp.check((select count(*) = 1 from public.public_order_payments where order_id = :'order_id'),
  'Le propriétaire lit ses paiements');
select pg_temp.check(public.assert_order_payment_owner(:'pay1'), 'Le propriétaire vérifie son paiement');
select set_config('request.jwt.claim.sub', :'intruder', true);
select pg_temp.check((select count(*) = 0 from public.public_order_payments),
  'Une autre boutique ne lit aucun paiement');
select pg_temp.fails(format($$select public.assert_order_payment_owner(%L)$$, :'pay1'),
  'Une autre boutique ne relit pas le statut');
reset role;

-- Fonction serveur : contexte, statut relu chez OpenPay ---------------------------------------
set local role service_role;
select public.openpay_payment_context(:'pay1') as ctx \gset
select pg_temp.check((:'ctx'::jsonb ->> 'apiKey') = 'opk_live_ABCDEFGH12345678'
  and (:'ctx'::jsonb ->> 'amount')::numeric = 10000
  and (:'ctx'::jsonb ->> 'status') = 'requested',
  'La fonction serveur lit la clé et le montant');
select pg_temp.check(public.record_openpay_status(:'pay1', 'OP-REF-1', 'pending', 'Demande envoyée') = 'pending',
  'Paiement en attente');
select pg_temp.check(public.openpay_payment_by_reference('OP-REF-1') = :'pay1',
  'Référence OpenPay enregistrée et retrouvable');
select pg_temp.fails(format($$select public.record_openpay_status(%L, 'OP-AUTRE', 'success', null)$$, :'pay1'),
  'Une autre référence ne peut pas valider ce paiement');
select pg_temp.check(public.record_openpay_status(:'pay1', 'OP-REF-1', 'SUCCESS', 'Paiement effectué') = 'success',
  'Statut relu « success » : paiement reçu');
select pg_temp.check(public.record_openpay_status(:'pay1', 'OP-REF-1', 'failed', null) = 'success',
  'Un paiement reçu ne redevient jamais échoué');
select pg_temp.check(
  (select status = 'new' and sale_id is null from public.public_orders where id = :'order_id')
  and (select quantity_on_hand from public.products where id = :'jean') = 5
  and not exists (select 1 from public.sales where shop_id = :'shop'),
  'Paiement reçu : aucune vente ni mouvement de stock avant la confirmation en caisse');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', :'owner', true);
select pg_temp.fails(format($$select public.request_order_mobile_payment(%L, 'MTN', '242066000000', 10000)$$,
  :'order_id'), 'Plus de demande après un paiement reçu');
select public.set_shop_openpay_enabled(:'shop', false) as off \gset
select pg_temp.check((:'off'::jsonb ->> 'enabled')::boolean = false, 'OpenPay coupé par la boutique');
reset role;
set local role service_role;
select pg_temp.check(public.openpay_payment_context(:'pay1') is null,
  'OpenPay coupé : la fonction serveur ne lit plus la clé');
reset role;
rollback;
