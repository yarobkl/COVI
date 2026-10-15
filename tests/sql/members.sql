-- Caisse multi-caissiers : équipe, invitations, PIN personnel, sessions de caisse, ventes par
-- caissier, RLS des membres (migrations 20261014090000, 20261014090050, 20261014090100).
-- Données fictives uniquement. Tout se passe dans une transaction annulée à la fin.
--
-- Acteurs :
--   OA propriétaire de la boutique SA ; OB propriétaire de SB ;
--   C1 « Awa »     caissière de SA, remise max 10 %, ne voit que ses ventes ;
--   C2 « Bema »    caissier de SA, remise max 0 % ;
--   C3 « Chantal » caissière de SA, voit toutes les ventes (puis désactivée) ;
--   CB             caissier de SB ;
--   X              utilisateur connecté sans boutique.
\set ON_ERROR_STOP 1
begin;

create function pg_temp.expect_error(p_sql text, p_state text, p_label text) returns void
language plpgsql as $$
declare v_state text; v_message text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_message = message_text;
    if v_state <> p_state then
      raise exception 'FAIL %: SQLSTATE % (%) au lieu de %', p_label, v_state, v_message, p_state;
    end if;
    raise notice 'ok  %  [% %]', p_label, v_state, v_message;
    return;
  end;
  raise exception 'FAIL %: la requête aurait dû échouer (%)', p_label, p_state;
end $$;

-- Assertion : la requête doit échouer avec exactement ce message (messages stables du contrat).
create function pg_temp.expect_msg(p_sql text, p_message text, p_label text) returns void
language plpgsql as $$
declare v_state text; v_message text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_message = message_text;
    if v_message <> p_message then
      raise exception 'FAIL %: « % » (%) au lieu de « % »', p_label, v_message, v_state, p_message;
    end if;
    raise notice 'ok  %  [% %]', p_label, v_state, v_message;
    return;
  end;
  raise exception 'FAIL %: la requête aurait dû échouer (« % »)', p_label, p_message;
end $$;

create function pg_temp.check(p_ok boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_ok is not true then raise exception 'FAIL %', p_label; end if;
  raise notice 'ok  %', p_label;
end $$;

-- Nombre de lignes touchées par un UPDATE/DELETE (0 attendu quand la RLS filtre).
create function pg_temp.affected(p_sql text) returns bigint
language plpgsql as $$
declare v_count bigint;
begin
  execute p_sql;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

\set as_pg 'reset role;'
\set as_oa 'reset role; do $$begin perform set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-0000000000a1'', true); perform set_config(''request.jwt.claim.session_id'', ''00000000-0000-0000-0000-0000000000a1'', true); end$$; set local role authenticated;'
\set as_ob 'reset role; do $$begin perform set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-0000000000b1'', true); perform set_config(''request.jwt.claim.session_id'', ''00000000-0000-0000-0000-0000000000b1'', true); end$$; set local role authenticated;'
\set as_c1 'reset role; do $$begin perform set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-0000000000a2'', true); perform set_config(''request.jwt.claim.session_id'', ''00000000-0000-0000-0000-0000000000a2'', true); end$$; set local role authenticated;'
\set as_c2 'reset role; do $$begin perform set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-0000000000a3'', true); perform set_config(''request.jwt.claim.session_id'', ''00000000-0000-0000-0000-0000000000a3'', true); end$$; set local role authenticated;'
\set as_c3 'reset role; do $$begin perform set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-0000000000a4'', true); perform set_config(''request.jwt.claim.session_id'', ''00000000-0000-0000-0000-0000000000a4'', true); end$$; set local role authenticated;'
\set as_cb 'reset role; do $$begin perform set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-0000000000b2'', true); perform set_config(''request.jwt.claim.session_id'', ''00000000-0000-0000-0000-0000000000b2'', true); end$$; set local role authenticated;'
\set as_x 'reset role; do $$begin perform set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-0000000000ff'', true); perform set_config(''request.jwt.claim.session_id'', ''00000000-0000-0000-0000-0000000000ff'', true); end$$; set local role authenticated;'
\set as_anon 'reset role; do $$begin perform set_config(''request.jwt.claim.sub'', '''', true); end$$; set local role anon;'

-- Fixtures --------------------------------------------------------------------------------------
insert into auth.users(id) values
  ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-0000000000a2'), ('00000000-0000-0000-0000-0000000000a3'),
  ('00000000-0000-0000-0000-0000000000a4'), ('00000000-0000-0000-0000-0000000000b2'),
  ('00000000-0000-0000-0000-0000000000ff');
insert into public.shops(id, owner_id, name, latitude, longitude) values
  ('10000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a1', 'Boutique SA',
   -4.26, 15.28),
  ('10000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b1', 'Boutique SB',
   null, null);
insert into public.arrivals(id, shop_id, code, kind, global_cost, status) values
  ('20000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-0000000000a1', 'BAL-A',
   'balloon', 250000, 'received');
insert into public.shop_expenses(shop_id, category, label, amount) values
  ('10000000-0000-0000-0000-0000000000a1', 'loyer', 'Loyer', 50000);
-- PA1 10 000 FCFA ×10 ; PA2 pièce unique 15 000 ; PA3 999,60 ×5 ; PA4 5 000 ×5 ; PB1 (SB).
insert into public.products(id, shop_id, arrival_id, name, initial_sale_price, quantity_on_hand,
                            is_unique_piece) values
  ('30000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-0000000000a1',
   '20000000-0000-0000-0000-0000000000a1', 'Jean bleu', 10000, 10, false),
  ('30000000-0000-0000-0000-0000000000a2', '10000000-0000-0000-0000-0000000000a1',
   '20000000-0000-0000-0000-0000000000a1', 'Veste unique', 15000, 1, true),
  ('30000000-0000-0000-0000-0000000000a3', '10000000-0000-0000-0000-0000000000a1',
   null, 'Chaussettes', 999.60, 5, false),
  ('30000000-0000-0000-0000-0000000000a4', '10000000-0000-0000-0000-0000000000a1',
   null, 'Tee-shirt', 5000, 5, false),
  ('30000000-0000-0000-0000-0000000000b1', '10000000-0000-0000-0000-0000000000b1',
   null, 'Robe SB', 8000, 5, false);

insert into storage.buckets(id, name) values ('covi-product-images', 'covi-product-images')
  on conflict do nothing;
insert into storage.objects(bucket_id, name) values
  ('covi-product-images', '10000000-0000-0000-0000-0000000000a1/jean.webp'),
  ('covi-product-images', '10000000-0000-0000-0000-0000000000b1/robe.webp');

-- 0. Déclarations et privilèges ----------------------------------------------------------------
select pg_temp.check(not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')),
  'anon : aucune fonction de public exécutable');
select pg_temp.check((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                      where n.nspname = 'public' and p.proname = 'record_sale') = 1
  and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'record_cart_sale') = 1,
  'une seule surcharge de record_sale et de record_cart_sale (appel PostgREST non ambigu)');
select pg_temp.check(bool_and(p.prosecdef and p.proconfig = array['search_path=""']),
  'fonctions de la caisse : SECURITY DEFINER, search_path vide')
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in (
  'shop_role', 'has_shop_permission', 'member_shop_ids', 'create_member_invite',
  'list_member_invites', 'revoke_member_invite', 'list_shop_members', 'set_member_active',
  'set_member_permissions', 'redeem_member_invite', 'my_member_shops', 'set_my_pin',
  'verify_my_pin', 'owner_reset_member_pin', 'open_till_session', 'close_till_session',
  'record_sale', 'record_cart_sale', 'member_pin_check', 'till_session_member', 'sale_seller',
  'assert_can_sell', 'assert_active_member', 'assert_shop_owner', 'shop_audit');
select pg_temp.check(bool_and(p.provolatile = 's'),
  'shop_role / has_shop_permission : STABLE')
from pg_proc p where p.oid in ('public.shop_role(uuid)'::regprocedure,
                               'public.has_shop_permission(uuid,text)'::regprocedure);
select pg_temp.check(bool_and(
    has_function_privilege('authenticated', p.oid, 'execute')
    and not has_function_privilege('anon', p.oid, 'execute')),
  'RPC de la caisse : EXECUTE pour authenticated seulement')
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in (
  'create_member_invite', 'list_member_invites', 'revoke_member_invite', 'list_shop_members',
  'set_member_active', 'set_member_permissions', 'redeem_member_invite', 'my_member_shops',
  'set_my_pin', 'verify_my_pin', 'owner_reset_member_pin', 'open_till_session',
  'close_till_session', 'record_sale', 'record_cart_sale');
select pg_temp.check(bool_and(not has_function_privilege('authenticated', p.oid, 'execute')),
  'fonctions internes : non exécutables par authenticated')
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in (
  'member_pin_check', 'member_pin_assert_strength', 'till_session_member', 'sale_seller',
  'assert_can_sell', 'assert_active_member', 'assert_shop_owner', 'shop_audit',
  'member_invite_hash', 'member_invite_normalize', 'shop_members_check_not_owner',
  'shop_members_close_till_sessions');
select pg_temp.check(bool_and(
    not has_table_privilege(r, t, 'insert') and not has_table_privilege(r, t, 'update')
    and not has_table_privilege(r, t, 'delete') and not has_table_privilege(r, t, 'truncate')
    and not has_table_privilege(r, t, 'trigger') and not has_table_privilege(r, t, 'references')),
  'nouvelles tables : aucune écriture, TRUNCATE, TRIGGER ni REFERENCES pour les rôles d''API')
from unnest(array['anon', 'authenticated']) r,
     unnest(array['public.shop_members', 'public.shop_member_invites',
                  'public.shop_member_invite_attempts', 'public.shop_audit_log',
                  'public.member_pins', 'public.till_sessions']) t;
select pg_temp.check(bool_and(not has_table_privilege('authenticated', t, 'select')
                              and not has_table_privilege('anon', t, 'select')),
  'invitations, tentatives, PIN, sessions de caisse : aucune lecture directe')
from unnest(array['public.shop_member_invites', 'public.shop_member_invite_attempts',
                  'public.member_pins', 'public.till_sessions']) t;
select pg_temp.check(not has_table_privilege('anon', 'public.shop_members', 'select')
  and not has_table_privilege('anon', 'public.shop_audit_log', 'select'),
  'anon : ni membres ni journal');
select pg_temp.check(bool_and(c.relrowsecurity), 'RLS active sur toutes les nouvelles tables')
from pg_class c where c.oid in ('public.shop_members'::regclass,
  'public.shop_member_invites'::regclass, 'public.shop_member_invite_attempts'::regclass,
  'public.shop_audit_log'::regclass, 'public.member_pins'::regclass,
  'public.till_sessions'::regclass);
select pg_temp.check(not exists (
    select 1 from pg_policies
    where schemaname = 'public' and cmd = 'ALL'
      and tablename in ('shop_members', 'shop_member_invites', 'shop_member_invite_attempts',
                        'shop_audit_log', 'member_pins', 'till_sessions')),
  'aucune politique FOR ALL sur les nouvelles tables');
select pg_temp.check(not exists (
    select 1 from pg_policies
    where schemaname = 'public' and qual like '%member_shop_ids%' and cmd <> 'SELECT'
      and tablename in ('products', 'sales', 'sale_items')),
  'politiques membres sur products/sales/sale_items : SELECT seulement');
select pg_temp.check((select is_nullable = 'YES' from information_schema.columns
                      where table_schema = 'public' and table_name = 'sales'
                        and column_name = 'seller_id'),
  'sales.seller_id ajoutée nullable');
select pg_temp.check(not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'products'
      and column_name ~ '(cost|purchase|margin|buy)'),
  'products : aucune colonne de coût lisible par les membres');

-- 1. Invitations (propriétaire OA) ------------------------------------------------------------
:as_oa
select (public.create_member_invite('10000000-0000-0000-0000-0000000000a1', '  Awa ', false, 10))
  ->> 'code' as code1 \gset
select (public.create_member_invite('10000000-0000-0000-0000-0000000000a1', 'Bema')) ->> 'code'
  as code2 \gset
select (public.create_member_invite('10000000-0000-0000-0000-0000000000a1', 'Chantal', true, 0))
  ->> 'code' as code3 \gset
select i ->> 'code' as code4, i ->> 'invite_id' as invite4
from public.create_member_invite('10000000-0000-0000-0000-0000000000a1', 'Révoqué') i \gset
select i ->> 'code' as code5, i ->> 'invite_id' as invite5
from public.create_member_invite('10000000-0000-0000-0000-0000000000a1', 'Expiré') i \gset
select pg_temp.check(:'code1' ~ '^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$'
  and :'code1' <> :'code2', 'code d''invitation : 12 caractères, format XXXX-XXXX-XXXX, uniques');
select pg_temp.check((select count(*) from public.list_member_invites(
    '10000000-0000-0000-0000-0000000000a1')) = 5, 'list_member_invites : 5 invitations en attente');
select pg_temp.expect_error($$select public.create_member_invite(
  '10000000-0000-0000-0000-0000000000b1', 'Intrus')$$, '42501',
  'create_member_invite sur la boutique d''un autre refusé');
select pg_temp.expect_msg($$select public.create_member_invite(
  '10000000-0000-0000-0000-0000000000a1', 'Trop', false, 101)$$, 'Invalid discount',
  'remise > 100 % refusée');
select pg_temp.expect_error($$select * from public.shop_member_invites$$, '42501',
  'table des invitations illisible, même par le propriétaire');
select pg_temp.expect_msg(format('select public.redeem_member_invite(%L)', :'code1'),
  'Owner cannot join own shop', 'le propriétaire ne peut pas rejoindre sa propre boutique');

:as_pg
select pg_temp.check((select count(*) from public.shop_member_invites
                      where shop_id = '10000000-0000-0000-0000-0000000000a1'
                        and code_hash = sha256(convert_to('covi-invite:'
                              || replace(:'code1', '-', ''), 'UTF8'))) = 1
  and not exists (select 1 from public.shop_member_invites i
                  where i::text like '%' || replace(:'code1', '-', '') || '%'
                     or i::text like '%' || :'code1' || '%')
  and (select bool_and(expires_at = created_at + interval '48 hours')
       from public.shop_member_invites),
  'invitation : seule l''empreinte SHA-256 est stockée, validité 48 h');
select pg_temp.expect_error($$insert into public.shop_members(shop_id, user_id, display_name)
  values ('10000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a1', 'OA')$$,
  '23514', 'le propriétaire ne peut pas être membre de sa boutique (même en écriture directe)');

-- 2. Utilisation des codes ------------------------------------------------------------------------
:as_c1
select pg_temp.check((select count(*) from public.my_member_shops()) = 0
  and (select count(*) from public.products) = 0, 'C1 avant invitation : aucune boutique, aucun produit');
select pg_temp.check((public.redeem_member_invite(lower(replace(:'code1', '-', ' ')))) ->> 'status'
  = 'joined', 'C1 rejoint SA (code saisi en minuscules avec espaces)');
select pg_temp.check((select count(*) = 1 and bool_and(shop_name = 'Boutique SA'
                       and display_name = 'Awa' and max_discount_pct = 10
                       and not can_view_shop_sales and not pin_set)
                      from public.my_member_shops()),
  'my_member_shops : boutique, nom, remise 10 %, PIN non défini');
:as_c2
select pg_temp.check((public.redeem_member_invite(:'code1')) ->> 'status' = 'invalid',
  'code déjà utilisé : refusé (usage unique)');
select pg_temp.check((public.redeem_member_invite(:'code2')) ->> 'status' = 'joined', 'C2 rejoint SA');
:as_c3
select pg_temp.check((public.redeem_member_invite(:'code3')) ->> 'status' = 'joined', 'C3 rejoint SA');

-- Révocation
:as_ob
select pg_temp.expect_msg(format('select public.revoke_member_invite(%L)', :'invite4'),
  'Invite not found', 'révocation par le propriétaire d''une autre boutique refusée');
:as_oa
select pg_temp.check(public.revoke_member_invite(:'invite4'), 'OA révoque l''invitation 4');
select pg_temp.expect_msg(format(
  'select public.revoke_member_invite((select id from public.list_member_invites(%L) limit 0))',
  '10000000-0000-0000-0000-0000000000a1'), 'Invite not found', 'révocation d''un id NULL refusée');

-- Limitation des essais : X fait 5 essais faux, puis même un bon code est refusé (verrou).
:as_x
select pg_temp.check(bool_and((public.redeem_member_invite('AAAA-BBBB-CCC' || g)) ->> 'status'
                              = 'invalid'), 'X : 5 codes faux refusés')
from generate_series(1, 5) g;
select pg_temp.check((public.redeem_member_invite(:'code5')) ->> 'status' = 'locked',
  'X : 6e essai verrouillé, même avec un code valide');
:as_pg
update public.shop_member_invite_attempts set attempted_at = attempted_at - interval '16 minutes'
where user_id = '00000000-0000-0000-0000-0000000000ff';
select pg_temp.check((select count(*) from public.shop_members
                      where user_id = '00000000-0000-0000-0000-0000000000ff') = 0,
  'X : le code valide n''a pas été consommé pendant le verrou');
update public.shop_member_invites set created_at = now() - interval '49 hours',
  expires_at = now() - interval '1 hour' where id = :'invite5';
:as_x
select pg_temp.check((public.redeem_member_invite(:'code4')) ->> 'status' = 'invalid',
  'code révoqué : refusé');
select pg_temp.check((public.redeem_member_invite(:'code5')) ->> 'status' = 'invalid',
  'code expiré (> 48 h) : refusé');
select pg_temp.check((select count(*) from public.my_member_shops()) = 0, 'X : toujours sans boutique');

-- Boutique SB et son caissier CB
:as_ob
select (public.create_member_invite('10000000-0000-0000-0000-0000000000b1', 'Caissier B'))
  ->> 'code' as codeb \gset
:as_cb
select pg_temp.check((public.redeem_member_invite(:'codeb')) ->> 'status' = 'joined', 'CB rejoint SB');

:as_pg
select id as m1 from public.shop_members where user_id = '00000000-0000-0000-0000-0000000000a2' \gset
select id as m2 from public.shop_members where user_id = '00000000-0000-0000-0000-0000000000a3' \gset
select id as m3 from public.shop_members where user_id = '00000000-0000-0000-0000-0000000000a4' \gset
select id as mb from public.shop_members where user_id = '00000000-0000-0000-0000-0000000000b2' \gset

-- 3. PIN personnel -------------------------------------------------------------------------------
:as_c1
select pg_temp.check(public.has_shop_permission('10000000-0000-0000-0000-0000000000a1', 'view_products')
  and not public.has_shop_permission('10000000-0000-0000-0000-0000000000a1', 'sell')
  and not public.has_shop_permission('10000000-0000-0000-0000-0000000000a1', 'manage')
  and not public.has_shop_permission('10000000-0000-0000-0000-0000000000a1', 'view_shop_sales')
  and public.shop_role('10000000-0000-0000-0000-0000000000a1') = 'cashier'
  and public.shop_role('10000000-0000-0000-0000-0000000000b1') is null,
  'C1 sans PIN : voit les produits, ne peut pas vendre ni gérer');
select pg_temp.expect_msg($$select public.record_sale('10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a1', 1, 10000, 'cash', gen_random_uuid())$$,
  'PIN required', 'caissier sans PIN : record_sale refusé');
select pg_temp.expect_msg($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000a1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000a1","quantity":1,"sold_unit_price":10000}]',
  'cash', gen_random_uuid())$$, 'PIN required', 'caissier sans PIN : record_cart_sale refusé');
select pg_temp.check((public.verify_my_pin('10000000-0000-0000-0000-0000000000a1', '4826'))
  ->> 'status' = 'not_set', 'verify_my_pin sans PIN : not_set');
select pg_temp.expect_msg(format('select public.set_my_pin(%L, %L)',
    '10000000-0000-0000-0000-0000000000a1', pin), 'PIN too simple',
  'PIN trivial refusé : ' || pin)
from unnest(array['0000', '1111', '1234', '123456', '4321', '987654', '012345', '1212',
                  '121212', '123123', '999999']) pin;
select pg_temp.expect_msg(format('select public.set_my_pin(%L, %L)',
    '10000000-0000-0000-0000-0000000000a1', pin), 'Invalid PIN format',
  'PIN mal formé refusé : ' || coalesce(pin, 'NULL'))
from unnest(array['123', '1234567', '12a4', ' 4826', null]) pin;
select pg_temp.check((public.set_my_pin('10000000-0000-0000-0000-0000000000a1', '4826'))
  ->> 'status' = 'ok', 'C1 choisit son PIN');
select pg_temp.check(public.has_shop_permission('10000000-0000-0000-0000-0000000000a1', 'sell'),
  'C1 avec PIN : session JWT déverrouillée après création du code');
:as_pg
delete from public.member_pin_unlocks where member_id = :'m1';
:as_c1
select pg_temp.check(not public.has_shop_permission('10000000-0000-0000-0000-0000000000a1', 'sell'),
  'C1 : PIN défini sans session déverrouillée ne donne pas le droit de vente');
select pg_temp.expect_msg($sql$select public.record_sale('10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a1', 1, 10000, 'cash', gen_random_uuid())$sql$,
  'PIN unlock required', 'appel RPC direct sans PIN déverrouillé refusé');
select pg_temp.expect_msg($sql$select public.record_cart_sale('10000000-0000-0000-0000-0000000000a1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000a1","quantity":1,"sold_unit_price":10000}]',
  'cash', gen_random_uuid())$sql$, 'PIN unlock required',
  'panier RPC direct sans déverrouillage refusé');
select pg_temp.check((public.verify_my_pin('10000000-0000-0000-0000-0000000000a1', '4826'))
  ->> 'status' = 'ok', 'vérification PIN crée une preuve liée à la session JWT');
select pg_temp.check(public.has_shop_permission('10000000-0000-0000-0000-0000000000a1', 'sell'),
  'C1 : le droit de vente n’est restauré qu’après code PIN correct');
select set_config('request.jwt.claim.session_id', '00000000-0000-0000-0000-000000009999', true);
select pg_temp.expect_msg($sql$select public.record_sale('10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a1', 1, 10000, 'cash', gen_random_uuid())$sql$,
  'PIN unlock required', 'un autre JWT du même utilisateur ne réutilise pas le PIN');
select set_config('request.jwt.claim.session_id', '00000000-0000-0000-0000-0000000000a2', true);
:as_pg
update public.member_pin_unlocks set unlocked_until = now() - interval '1 second'
where member_id = :'m1';
:as_c1
select pg_temp.expect_msg($sql$select public.record_sale('10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a1', 1, 10000, 'cash', gen_random_uuid())$sql$,
  'PIN unlock required', 'l’autorisation périmée est refusée côté base');
select pg_temp.check((public.verify_my_pin('10000000-0000-0000-0000-0000000000a1', '4826'))
  ->> 'status' = 'ok', 'réouverture après expiration autorise à nouveau');

select pg_temp.expect_error($$select * from public.member_pins$$, '42501',
  'C1 ne lit pas la table des PIN');
:as_pg
select pg_temp.check((select pin_hash like '$2a$10$%' and pin_hash <> '4826'
                        and pin_hash = extensions.crypt('4826', pin_hash)
                        and not must_change
                      from public.member_pins where member_id = :'m1'),
  'PIN stocké en bcrypt (coût 10), jamais en clair');
:as_c1
select pg_temp.check((public.set_my_pin('10000000-0000-0000-0000-0000000000a1', '7391'))
  ->> 'status' = 'invalid', 'changement de PIN sans l''ancien : refusé et compté');
select pg_temp.check((public.set_my_pin('10000000-0000-0000-0000-0000000000a1', '7391', '0001'))
  ->> 'status' = 'invalid', 'changement de PIN avec un mauvais ancien PIN : refusé');
select pg_temp.check((public.set_my_pin('10000000-0000-0000-0000-0000000000a1', '7391', '4826'))
  ->> 'status' = 'ok', 'changement de PIN avec le bon ancien PIN');
select pg_temp.check((public.verify_my_pin('10000000-0000-0000-0000-0000000000a1', '7391'))
  ->> 'status' = 'ok', 'verify_my_pin : bon PIN accepté, compteur remis à zéro');
select pg_temp.check(array_agg((public.verify_my_pin('10000000-0000-0000-0000-0000000000a1',
                       '5555')) ->> 'status' order by g)
                     = array['invalid', 'invalid', 'invalid', 'invalid', 'locked'],
  '5 mauvais PIN : verrouillage au 5e')
from generate_series(1, 5) g;
select pg_temp.check((public.verify_my_pin('10000000-0000-0000-0000-0000000000a1', '7391'))
  ->> 'status' = 'locked', 'verrouillé : même le bon PIN est refusé pendant 15 minutes');
:as_pg
select pg_temp.check((select failed_attempts = 5
                        and locked_until between now() + interval '14 minutes'
                                             and now() + interval '15 minutes'
                      from public.member_pins where member_id = :'m1'),
  'verrouillage de 15 minutes enregistré');
update public.member_pins set locked_until = now() - interval '1 second' where member_id = :'m1';
:as_c1
select pg_temp.check((public.verify_my_pin('10000000-0000-0000-0000-0000000000a1', '7391'))
  ->> 'status' = 'ok', 'après 15 minutes : bon PIN accepté');
:as_pg
select pg_temp.check((select failed_attempts = 0 and locked_until is null
                      from public.member_pins where member_id = :'m1'), 'compteur remis à zéro');

-- Réinitialisation par le propriétaire
:as_c1
select pg_temp.expect_msg(format('select public.owner_reset_member_pin(%L)', :'m1'),
  'Member not found', 'un caissier ne peut pas réinitialiser un PIN');
:as_ob
select pg_temp.expect_msg(format('select public.owner_reset_member_pin(%L)', :'m1'),
  'Member not found', 'le propriétaire d''une autre boutique ne peut pas réinitialiser');
:as_oa
select pg_temp.expect_error($$select * from public.member_pins$$, '42501',
  'le propriétaire ne lit pas la table des PIN');
-- Never inspect a full row for a short PIN substring: a random UUID could coincidentally
-- contain those digits. Check instead that the RPC schema exposes no sensitive keys.
select pg_temp.check(not exists (
    select 1 from public.list_shop_members('10000000-0000-0000-0000-0000000000a1') l
    where to_jsonb(l) ?| array['pin', 'pin_hash', 'token_hash', 'password', 'secret']),
  'list_shop_members : ni PIN ni empreinte');
select pg_temp.check((select pin_set from public.list_shop_members(
    '10000000-0000-0000-0000-0000000000a1') where id = :'m1'), 'list_shop_members : C1 a un PIN');
select pg_temp.check((public.owner_reset_member_pin(:'m1')) ->> 'pin_must_change' = 'true',
  'OA réinitialise le PIN de C1');
:as_pg
select pg_temp.check((select pin_hash is null and must_change from public.member_pins
                      where member_id = :'m1'), 'réinitialisation : PIN effacé, changement imposé');
:as_c1
select pg_temp.check((select pin_must_change and not pin_set from public.my_member_shops()),
  'my_member_shops : C1 doit choisir un nouveau PIN');
select pg_temp.expect_msg($$select public.record_sale('10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a1', 1, 10000, 'cash', gen_random_uuid())$$,
  'PIN required', 'après réinitialisation : vente refusée tant que le PIN n''est pas choisi');
select pg_temp.check((public.set_my_pin('10000000-0000-0000-0000-0000000000a1', '5937'))
  ->> 'status' = 'ok', 'C1 choisit un nouveau PIN sans l''ancien');
:as_c2
select pg_temp.check((public.set_my_pin('10000000-0000-0000-0000-0000000000a1', '6284'))
  ->> 'status' = 'ok', 'C2 choisit son PIN');
:as_c3
select pg_temp.check((public.set_my_pin('10000000-0000-0000-0000-0000000000a1', '3917'))
  ->> 'status' = 'ok', 'C3 choisit son PIN');
:as_cb
select pg_temp.check((public.set_my_pin('10000000-0000-0000-0000-0000000000b1', '8152'))
  ->> 'status' = 'ok', 'CB choisit son PIN');
select pg_temp.expect_msg($$select public.set_my_pin('10000000-0000-0000-0000-0000000000a1', '8152')$$,
  'Shop not found', 'CB ne peut pas définir de PIN dans SA');

-- 4. Vente du propriétaire (référence pour la visibilité) ---------------------------------------
:as_oa
select public.record_sale('10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a4', 1, 1, 'cash',
  '40000000-0000-0000-0000-0000000000a0') as owner_sale \gset
select pg_temp.check((select seller_id = '00000000-0000-0000-0000-0000000000a1'
                      from public.sales where id = :'owner_sale'),
  'propriétaire : vente à 1 FCFA sans minimum, seller_id = propriétaire');

-- 5. Caissier C1 sur son propre compte (remise max 10 %) ----------------------------------------
:as_c1
select pg_temp.check((select count(*) from public.products
                      where name ilike '%jean%') = 1
  and (select count(*) from public.products) = 4,
  'C1 recherche les produits de SA (4 produits, rien de SB)');
select pg_temp.check((select count(*) from public.shops) = 0, 'C1 ne lit pas la table shops (GPS, owner_id)');
select pg_temp.check((select count(*) from public.arrivals) = 0, 'C1 ne lit pas les arrivages (coûts)');
select pg_temp.check((select count(*) from public.shop_expenses) = 0, 'C1 ne lit pas les charges');
select pg_temp.check((select count(*) from public.shop_members) = 0, 'C1 ne lit pas l''équipe');
select pg_temp.check((select count(*) from public.shop_audit_log) = 0, 'C1 ne lit pas le journal');
select pg_temp.expect_error($$select * from public.till_sessions$$, '42501',
  'C1 ne lit pas les sessions de caisse');
select pg_temp.expect_error($$select * from public.shop_member_invite_attempts$$, '42501',
  'C1 ne lit pas les tentatives');
select pg_temp.expect_msg($$select public.list_shop_members('10000000-0000-0000-0000-0000000000a1')$$,
  'Shop not found', 'C1 : list_shop_members refusé');
select pg_temp.expect_msg($$select public.list_member_invites('10000000-0000-0000-0000-0000000000a1')$$,
  'Shop not found', 'C1 : list_member_invites refusé');
select pg_temp.expect_msg($$select public.create_member_invite('10000000-0000-0000-0000-0000000000a1', 'Ami')$$,
  'Shop not found', 'C1 : create_member_invite refusé');
select pg_temp.expect_msg(format('select public.set_member_permissions(%L, true, 100)', :'m1'),
  'Member not found', 'C1 ne peut pas s''accorder de remise');
select pg_temp.expect_msg(format('select public.set_member_active(%L, false)', :'m2'),
  'Member not found', 'C1 ne peut pas désactiver un collègue');
select pg_temp.expect_msg($$select public.shop_dashboard('10000000-0000-0000-0000-0000000000a1')$$,
  'Shop not found', 'C1 : tableau de bord (chiffres du propriétaire) refusé');
select pg_temp.check((select count(*) from public.sales) = 0,
  'C1 ne voit pas la vente du propriétaire');

-- Plus de remise maximale (décision de la boutique) : aucun prix minimum, même pour C1 (10 %).
select pg_temp.check(public.min_unit_price(10000, 10) is null
  and public.min_unit_price(999.60, 0) is null,
  'Remise maximale supprimée : aucun prix minimum pour les caissiers');
select public.record_sale('10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a1', 1, 9000, 'mobile_money',
  '40000000-0000-0000-0000-0000000000a1') as c1_sale \gset
select pg_temp.check((select seller_id = '00000000-0000-0000-0000-0000000000a2'
                        and total_amount = 9000
                      from public.sales where id = :'c1_sale')
  and (select quantity_on_hand from public.products
       where id = '30000000-0000-0000-0000-0000000000a1') = 9,
  'C1 : record_sale à 9 000 accepté, seller_id = C1, stock 10 → 9');
select pg_temp.check((select quantity_on_hand from public.products
                      where id = '30000000-0000-0000-0000-0000000000a4') = 4,
  'panier refusé : aucune ligne écrite (stock PA4 inchangé)');
select public.record_cart_sale('10000000-0000-0000-0000-0000000000a1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000a1","quantity":2,"sold_unit_price":9500},
    {"product_id":"30000000-0000-0000-0000-0000000000a2","quantity":1,"sold_unit_price":13500}]',
  'cash', '40000000-0000-0000-0000-0000000000a2') as c1_cart \gset
select pg_temp.check((select seller_id = '00000000-0000-0000-0000-0000000000a2'
                        and total_amount = 32500
                      from public.sales where id = :'c1_cart')
  and (select count(*) from public.sale_items where sale_id = :'c1_cart') = 2
  and (select quantity_on_hand from public.products
       where id = '30000000-0000-0000-0000-0000000000a1') = 7,
  'C1 : record_cart_sale (2 lignes, dont 13 500 = minimum de la pièce à 15 000) : seller_id, stock 9 → 7');
select pg_temp.check(public.record_cart_sale('10000000-0000-0000-0000-0000000000a1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000a1","quantity":2,"sold_unit_price":9500}]',
  'cash', '40000000-0000-0000-0000-0000000000a2') = :'c1_cart'
  and public.record_sale('10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a1', 1, 9000, 'mobile_money',
  '40000000-0000-0000-0000-0000000000a1') = :'c1_sale'
  and (select quantity_on_hand from public.products
       where id = '30000000-0000-0000-0000-0000000000a1') = 7,
  'rejeu avec le même client_operation_id : même vente, pas de second décrément');
select pg_temp.check((select count(*) from public.sales) = 2
  and (select count(*) from public.sale_items) = 3, 'C1 voit ses 2 ventes et leurs 3 lignes');
select pg_temp.check((select status = 'sold' and quantity_on_hand = 0 from public.products
                      where id = '30000000-0000-0000-0000-0000000000a2')
  and exists (select 1 from public.sale_items where product_id = '30000000-0000-0000-0000-0000000000a2'
              and initial_unit_price = 15000 and sold_unit_price = 13500),
  'pièce unique : statut sold, historique conservé (prix initial et prix vendu)');
select pg_temp.expect_msg($$select public.record_sale('10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a2', 1, 15000, 'cash', gen_random_uuid())$$,
  'Product unavailable', 'pièce unique vendue : ne se revend pas');
select pg_temp.expect_msg($$select public.record_sale('10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a4', 5, 5000, 'cash', gen_random_uuid())$$,
  'Insufficient stock', 'stock jamais négatif');

-- Écritures directes : toutes refusées
select pg_temp.expect_error($$insert into public.products(shop_id, name, initial_sale_price,
  quantity_on_hand) values ('10000000-0000-0000-0000-0000000000a1', 'Faux', 1, 100)$$, '42501',
  'C1 : INSERT products refusé');
select pg_temp.check(pg_temp.affected($$update public.products set name = 'X', initial_sale_price = 1
  where shop_id = '10000000-0000-0000-0000-0000000000a1'$$) = 0, 'C1 : UPDATE products sans effet');
select pg_temp.check(pg_temp.affected($$delete from public.products
  where shop_id = '10000000-0000-0000-0000-0000000000a1'$$) = 0, 'C1 : DELETE products sans effet');
select pg_temp.expect_error($$update public.products set quantity_on_hand = 99$$, '42501',
  'C1 : UPDATE du stock refusé');
select pg_temp.expect_error($$insert into public.sales(shop_id, payment_method, total_amount)
  values ('10000000-0000-0000-0000-0000000000a1', 'cash', 1)$$, '42501', 'C1 : INSERT sales refusé');
select pg_temp.expect_error($$update public.sales set seller_id = null$$, '42501',
  'C1 : UPDATE sales refusé');
select pg_temp.expect_error($$delete from public.sale_items$$, '42501', 'C1 : DELETE sale_items refusé');
select pg_temp.expect_error($$insert into public.arrivals(shop_id, code, kind)
  values ('10000000-0000-0000-0000-0000000000a1', 'X', 'balloon')$$, '42501',
  'C1 : INSERT arrivals refusé');
select pg_temp.expect_error($$insert into public.shop_expenses(shop_id, category, label, amount)
  values ('10000000-0000-0000-0000-0000000000a1', 'x', 'x', 1)$$, '42501',
  'C1 : INSERT shop_expenses refusé');
select pg_temp.expect_error($$update public.shop_members set max_discount_pct = 100$$, '42501',
  'C1 : UPDATE shop_members refusé');
select pg_temp.expect_error($$insert into public.shop_members(shop_id, user_id, display_name)
  values ('10000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a2', 'x')$$,
  '42501', 'C1 : INSERT shop_members refusé');
select pg_temp.expect_error($$update public.member_pins set pin_hash = null$$, '42501',
  'C1 : UPDATE member_pins refusé');
select pg_temp.expect_error($$insert into public.shop_audit_log(shop_id, action)
  values ('10000000-0000-0000-0000-0000000000a1', 'faux')$$, '42501',
  'C1 : INSERT shop_audit_log refusé');
select pg_temp.expect_error($$truncate public.sales$$, '42501', 'C1 : TRUNCATE refusé');
select pg_temp.expect_error($$select public.member_pin_check(
  '00000000-0000-0000-0000-000000000000', '1111')$$, '42501', 'C1 : fonction interne refusée');

select pg_temp.check((select count(*) from storage.objects) = 1
  and (select name from storage.objects) like '10000000-0000-0000-0000-0000000000a1/%',
  'C1 lit les photos des produits de SA seulement');
select pg_temp.expect_error($$insert into storage.objects(bucket_id, name) values
  ('covi-product-images', '10000000-0000-0000-0000-0000000000a1/faux.webp')$$, '42501',
  'C1 ne dépose pas de photo');

-- Isolation : SB
select pg_temp.expect_msg($$select public.record_sale('10000000-0000-0000-0000-0000000000b1',
  '30000000-0000-0000-0000-0000000000b1', 1, 8000, 'cash', gen_random_uuid())$$,
  'Shop not found', 'C1 ne vend pas dans SB');
select pg_temp.expect_msg($$select public.record_sale('10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000b1', 1, 8000, 'cash', gen_random_uuid())$$,
  'Product unavailable', 'C1 ne vend pas un produit de SB via SA');
select pg_temp.expect_msg($$select public.record_sale('10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a4', 1, 5000, 'cash', gen_random_uuid(),
  p_till_session => repeat('a', 64))$$, 'Till session invalid',
  'un caissier ne peut pas utiliser p_till_session');

-- C2 (0 %) : prix au centime, minimum = prix affiché
:as_c2
select pg_temp.check(public.record_sale('10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a3', 1, 999.60, 'cash', gen_random_uuid()) is not null,
  'C2 (0 %) : prix affiché 999,60 accepté (minimum plafonné au prix affiché)');
select pg_temp.check((select count(*) from public.sales) = 1,
  'C2 ne voit que sa vente (ni celles de C1 ni celle du propriétaire)');
select pg_temp.check((select count(*) from public.sale_items) = 1, 'C2 : une seule ligne visible');

-- C3 (voit toutes les ventes)
:as_c3
select pg_temp.check(public.has_shop_permission('10000000-0000-0000-0000-0000000000a1', 'view_shop_sales')
  and (select count(*) from public.sales) = 4 and (select count(*) from public.sale_items) = 5,
  'C3 (can_view_shop_sales) voit toutes les ventes de SA et leurs lignes');

-- CB : isolation inverse
:as_cb
select pg_temp.check((select count(*) from public.products) = 1
  and (select count(*) from public.sales) = 0, 'CB ne voit que les produits de SB, aucune vente de SA');

-- Utilisateur sans boutique
:as_x
select pg_temp.check((select count(*) from public.products) = 0
  and (select count(*) from public.sales) = 0, 'X : aucune donnée');
select pg_temp.expect_msg($$select public.record_sale('10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a4', 1, 5000, 'cash', gen_random_uuid())$$,
  'Shop not found', 'X : vente refusée');

-- 6. Permissions modifiées par le propriétaire ----------------------------------------------------
:as_oa
select pg_temp.check(((public.set_member_permissions(:'m2', true, 20)) ->> 'max_discount_pct')::numeric = 20,
  'OA donne 20 % et la vue des ventes à C2');
select pg_temp.expect_msg(format('select public.set_member_permissions(%L, true, -1)', :'m2'),
  'Invalid discount', 'remise négative refusée');
:as_ob
select pg_temp.expect_msg(format('select public.set_member_permissions(%L, true, 50)', :'m2'),
  'Member not found', 'OB ne modifie pas un membre de SA');
:as_c2
select pg_temp.check((select count(*) from public.sales) = 4,
  'C2 voit maintenant toutes les ventes');
select pg_temp.check(public.record_sale('10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a4', 1, 4000, 'cash', gen_random_uuid()) is not null,
  'C2 : 4 000 = 5 000 − 20 % accepté');

-- 7. Sessions de caisse sur l'appareil du propriétaire -----------------------------------------
:as_oa
select pg_temp.check((select count(*) = 3 and bool_and(pin_set)
                      from public.list_shop_members('10000000-0000-0000-0000-0000000000a1')),
  'OA voit son équipe (3 membres, PIN définis)');
select pg_temp.check((select count(*) from public.shop_members) = 3,
  'OA lit la table shop_members de sa boutique seulement');
-- Le mode comptoir exige le code du responsable (migration 20261014090200, tests/sql/owner_pin.sql).
select pg_temp.expect_msg(format('select public.open_till_session(%L, %L, %L)',
    '10000000-0000-0000-0000-0000000000a1', :'m1', '5937'), 'Owner PIN required',
  'session de caisse refusée tant que le responsable n''a pas de code');
select pg_temp.check((public.set_owner_pin('10000000-0000-0000-0000-0000000000a1', '7391'))
  ->> 'status' = 'ok', 'OA choisit son code de responsable');
select pg_temp.check((public.open_till_session('10000000-0000-0000-0000-0000000000a1', :'m1', '0000'))
  ->> 'status' = 'invalid', 'session de caisse : mauvais PIN refusé');
:as_pg
select pg_temp.check((select failed_attempts from public.member_pins where member_id = :'m1') = 1,
  'mauvais PIN de session : compté');
:as_oa
select pg_temp.expect_msg(format('select public.open_till_session(%L, %L, %L)',
    '10000000-0000-0000-0000-0000000000a1', :'mb', '8152'), 'Member not found',
  'session pour un membre d''une autre boutique refusée');
select r ->> 'token' as tok1, r ->> 'status' as tok1_status
from public.open_till_session('10000000-0000-0000-0000-0000000000a1', :'m1', '5937') r \gset
select pg_temp.check(:'tok1_status' = 'ok' and :'tok1' ~ '^[0-9a-f]{64}$',
  'session de caisse ouverte pour C1 : jeton aléatoire de 256 bits');
:as_pg
select pg_temp.check((select count(*) from public.till_sessions
                      where token_hash = sha256(convert_to('covi-till:' || :'tok1', 'UTF8'))
                        and expires_at = opened_at + interval '12 hours') = 1
  and not exists (select 1 from public.till_sessions t where t::text like '%' || :'tok1' || '%')
  and (select failed_attempts from public.member_pins where member_id = :'m1') = 0,
  'jeton stocké haché seulement, expiration 12 h ; bon PIN remet le compteur à zéro');
:as_oa
select public.record_sale('10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a1', 1, 9000, 'card', '40000000-0000-0000-0000-0000000000a3',
  p_till_session => :'tok1') as till_sale \gset
select public.record_cart_sale('10000000-0000-0000-0000-0000000000a1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000a4","quantity":1,"sold_unit_price":4500}]',
  'cash', '40000000-0000-0000-0000-0000000000a4', p_till_session => :'tok1') as till_cart \gset
select pg_temp.check((select bool_and(seller_id = '00000000-0000-0000-0000-0000000000a2')
                      from public.sales where id in (:'till_sale', :'till_cart'))
  and (select quantity_on_hand from public.products
       where id = '30000000-0000-0000-0000-0000000000a1') = 6,
  'session C1 : ventes (record_sale et record_cart_sale) attribuées à C1');
select pg_temp.check((select count(*) from public.sales
                      where seller_id = '00000000-0000-0000-0000-0000000000a2') = 4,
  'OA filtre ses ventes par caissier (4 ventes de C1)');
:as_c1
select pg_temp.check((select count(*) from public.sales) = 4,
  'C1 voit aussi les ventes passées en son nom sur l''appareil partagé');
select pg_temp.expect_msg(format($q$select public.record_sale(%L, %L, 1, 9000, 'cash',
  gen_random_uuid(), p_till_session => %L)$q$, '10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a1', :'tok1'), 'Till session invalid',
  'C1 ne peut pas utiliser le jeton (réservé au propriétaire)');
:as_ob
select pg_temp.expect_msg(format($q$select public.record_sale(%L, %L, 1, 8000, 'cash',
  gen_random_uuid(), p_till_session => %L)$q$, '10000000-0000-0000-0000-0000000000b1',
  '30000000-0000-0000-0000-0000000000b1', :'tok1'), 'Till session invalid',
  'jeton de SA inutilisable dans SB');
select pg_temp.expect_msg(format($q$select public.record_sale(%L, %L, 1, 9000, 'cash',
  gen_random_uuid(), p_till_session => %L)$q$, '10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a1', :'tok1'), 'Shop not found',
  'jeton de SA inutilisable par un autre propriétaire');
select pg_temp.check(not public.close_till_session('10000000-0000-0000-0000-0000000000b1', :'tok1'),
  'OB ne peut pas fermer la session de SA');
:as_x
select pg_temp.expect_msg(format('select public.open_till_session(%L, %L, %L)',
    '10000000-0000-0000-0000-0000000000a1', :'m1', '5937'), 'Shop not found',
  'open_till_session réservé au propriétaire');
:as_c2
select pg_temp.expect_msg(format('select public.open_till_session(%L, %L, %L)',
    '10000000-0000-0000-0000-0000000000a1', :'m1', '5937'), 'Shop not found',
  'un caissier ne peut pas ouvrir de session de caisse');

-- Fermeture
:as_oa
select pg_temp.check(public.close_till_session('10000000-0000-0000-0000-0000000000a1', :'tok1'),
  'OA ferme la session');
select pg_temp.check(not public.close_till_session('10000000-0000-0000-0000-0000000000a1', :'tok1'),
  'fermeture idempotente');
select pg_temp.expect_msg(format($q$select public.record_sale(%L, %L, 1, 9000, 'cash',
  gen_random_uuid(), p_till_session => %L)$q$, '10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a1', :'tok1'), 'Till session invalid',
  'session fermée : refusée');
select pg_temp.check(public.record_sale('10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a1', 1, 9000, 'card', '40000000-0000-0000-0000-0000000000a3',
  p_till_session => :'tok1') = :'till_sale',
  'session fermée : le rejeu d''une vente déjà enregistrée renvoie encore son id');
-- Expiration
select (public.open_till_session('10000000-0000-0000-0000-0000000000a1', :'m1', '5937'))
  ->> 'token' as tok2 \gset
:as_pg
update public.till_sessions set opened_at = now() - interval '13 hours',
  expires_at = now() - interval '1 hour'
where token_hash = sha256(convert_to('covi-till:' || :'tok2', 'UTF8'));
:as_oa
select pg_temp.expect_msg(format($q$select public.record_cart_sale(%L,
  '[{"product_id":"30000000-0000-0000-0000-0000000000a1","quantity":1,"sold_unit_price":9000}]',
  'cash', gen_random_uuid(), p_till_session => %L)$q$, '10000000-0000-0000-0000-0000000000a1',
  :'tok2'), 'Till session invalid', 'session expirée (> 12 h) : refusée');
-- Réinitialisation du PIN : ferme les sessions du membre
select (public.open_till_session('10000000-0000-0000-0000-0000000000a1', :'m2', '6284'))
  ->> 'token' as tok3 \gset
select public.owner_reset_member_pin(:'m2');
select pg_temp.expect_msg(format($q$select public.record_sale(%L, %L, 1, 5000, 'cash',
  gen_random_uuid(), p_till_session => %L)$q$, '10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a4', :'tok3'), 'Till session invalid',
  'PIN réinitialisé : sessions du membre fermées');
select pg_temp.check((public.open_till_session('10000000-0000-0000-0000-0000000000a1', :'m2', '6284'))
  ->> 'status' = 'not_set', 'PIN réinitialisé : pas de nouvelle session avant le nouveau PIN');
-- Verrouillage par les sessions (compteur commun avec verify_my_pin)
select pg_temp.check(array_agg((public.open_till_session('10000000-0000-0000-0000-0000000000a1',
                       :'m3', '1590')) ->> 'status' order by g)
                     = array['invalid', 'invalid', 'invalid', 'invalid', 'locked', 'locked'],
  'session de caisse : 5 mauvais PIN → verrouillage')
from generate_series(1, 6) g;
:as_c3
select pg_temp.check((public.verify_my_pin('10000000-0000-0000-0000-0000000000a1', '3917'))
  ->> 'status' = 'locked', 'verrou commun : C3 bloqué aussi sur son propre appareil');
:as_pg
update public.member_pins set locked_until = now() - interval '1 second' where member_id = :'m3';

-- 8. Désactivation ---------------------------------------------------------------------------------
:as_oa
select (public.open_till_session('10000000-0000-0000-0000-0000000000a1', :'m3', '3917'))
  ->> 'token' as tok4 \gset
select pg_temp.check((public.set_member_active(:'m3', false)) ->> 'active' = 'false',
  'OA désactive C3');
select pg_temp.expect_msg(format($q$select public.record_sale(%L, %L, 1, 5000, 'cash',
  gen_random_uuid(), p_till_session => %L)$q$, '10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a4', :'tok4'), 'Till session invalid',
  'membre désactivé : sa session de caisse est refusée');
select pg_temp.expect_msg(format('select public.open_till_session(%L, %L, %L)',
    '10000000-0000-0000-0000-0000000000a1', :'m3', '3917'), 'Member not found',
  'membre désactivé : nouvelle session refusée');
:as_c3
select pg_temp.check((select count(*) from public.products) = 0
  and (select count(*) from public.sales) = 0 and (select count(*) from public.sale_items) = 0
  and (select count(*) from public.my_member_shops()) = 0
  and (select count(*) from storage.objects) = 0,
  'membre désactivé : plus aucune lecture (produits, photos, ventes, boutiques)');
select pg_temp.expect_msg($$select public.record_sale('10000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a4', 1, 5000, 'cash', gen_random_uuid())$$,
  'Shop not found', 'membre désactivé : vente refusée');
select pg_temp.expect_msg($$select public.verify_my_pin('10000000-0000-0000-0000-0000000000a1', '3917')$$,
  'Shop not found', 'membre désactivé : verify_my_pin refusé');
:as_oa
select public.set_member_active(:'m3', true);
:as_pg
select pg_temp.check((select closed_at is not null from public.till_sessions
                      where token_hash = sha256(convert_to('covi-till:' || :'tok4', 'UTF8'))),
  'réactivation : l''ancienne session reste fermée');

-- 9. Journal d'audit ----------------------------------------------------------------------------
:as_oa
select pg_temp.check((select count(distinct action) from public.shop_audit_log
                      where action in ('invite_created', 'invite_revoked', 'member_joined',
                        'member_permissions_changed', 'member_deactivated', 'member_reactivated',
                        'pin_set', 'pin_changed', 'pin_reset', 'till_session_opened',
                        'till_session_closed', 'till_session_pin_failed')) = 12,
  'journal : invitations, membres, permissions, PIN, sessions de caisse');
select pg_temp.check(not exists (
    select 1 from public.shop_audit_log l
    where l.details ?| array['pin', 'new_pin', 'current_pin', 'pin_hash', 'token', 'code',
                             'code_hash', 'token_hash']
       or l::text like '%$2a$%'
       or l::text like '%' || :'tok1' || '%'
       or l::text like '%' || replace(:'code1', '-', '') || '%'),
  'journal : jamais de PIN, d''empreinte, de jeton ni de code d''invitation');
select pg_temp.check(not exists (select 1 from public.shop_audit_log
                                 where shop_id <> '10000000-0000-0000-0000-0000000000a1'),
  'journal : OA ne voit que sa boutique');
select pg_temp.expect_error($$delete from public.shop_audit_log$$, '42501',
  'journal : pas d''effacement par le propriétaire');

-- 10. anon ------------------------------------------------------------------------------------------
:as_anon
select pg_temp.expect_error(format('select %s', f), '42501', 'anon : ' || f || ' refusé')
from unnest(array[
  $$public.my_member_shops()$$,
  $$public.redeem_member_invite('AAAA-BBBB-CCCC')$$,
  $$public.verify_my_pin('10000000-0000-0000-0000-0000000000a1', '1111')$$,
  $$public.set_my_pin('10000000-0000-0000-0000-0000000000a1', '4826')$$,
  $$public.open_till_session('10000000-0000-0000-0000-0000000000a1', gen_random_uuid(), '1111')$$,
  $$public.record_sale('10000000-0000-0000-0000-0000000000a1', '30000000-0000-0000-0000-0000000000a4', 1, 5000, 'cash', gen_random_uuid())$$,
  $$public.record_cart_sale('10000000-0000-0000-0000-0000000000a1', '[]', 'cash', gen_random_uuid())$$,
  $$public.shop_role('10000000-0000-0000-0000-0000000000a1')$$,
  $$public.has_shop_permission('10000000-0000-0000-0000-0000000000a1', 'sell')$$
]) f;
select pg_temp.expect_error($$select * from public.shop_members$$, '42501', 'anon : shop_members refusé');
select pg_temp.expect_error($$select * from public.products$$, '42501', 'anon : products refusé');

reset role;
rollback;
