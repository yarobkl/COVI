-- Test COVI IA sans PIN : contrôle du JWT et des caisses partagées.
-- Données fictives uniquement ; ROLLBACK intégral.
\set ON_ERROR_STOP 1
begin;
create function pg_temp.check(p_ok boolean, p_label text) returns void
language plpgsql as $$
begin
 if p_ok is not true then raise exception 'FAIL %',p_label; end if;
 raise notice 'ok %',p_label;
end $$;

\set owner '00000000-0000-0000-0000-000000000f11'
\set another '00000000-0000-0000-0000-000000000f12'
\set shop '10000000-0000-0000-0000-000000000f11'
\set member '50000000-0000-0000-0000-000000000f11'
\set cashier '60000000-0000-0000-0000-000000000f11'
\set sid_a '70000000-0000-4000-8000-000000000f11'
\set sid_b '70000000-0000-4000-8000-000000000f12'

insert into auth.users(id) values (:'owner'), (:'another');
insert into public.shops(id, owner_id,name) values (:'shop',:'owner','Boutique PIN-free');
insert into public.shop_members(id,shop_id,user_id,display_name)
 values (:'member',:'shop',:'another','Caissier');
insert into public.shop_cashier_profiles(id,shop_id,display_name,pin_hash,created_by)
 values (:'cashier',:'shop','Équipe',extensions.crypt('5937',extensions.gen_salt('bf',10)),:'owner');

select pg_temp.check(
  not has_function_privilege('anon','public.covi_ai_owner_session_allowed(uuid)','execute'),
  'Anonymous cannot check management session');
select pg_temp.check(
  not has_table_privilege('authenticated','public.shop_cashier_tills','select'),
  'Shared cashier sessions stay private');

set local role authenticated;
select set_config('request.jwt.claim.sub',:'owner',true);
select set_config('request.jwt.claim.session_id',:'sid_a',true);
select pg_temp.check(public.covi_ai_owner_session_allowed(:'shop'),
 'Owner can chat from a fresh personal session without PIN');

reset role;
insert into public.till_sessions(shop_id,member_id,token_hash,opened_by,expires_at)
 values (:'shop',:'member',decode(repeat('ab',32),'hex'),:'owner',now()+interval '2 hours');
select pg_temp.check(
  (select owner_auth_session_id=:'sid_a' from public.till_sessions
    where shop_id=:'shop'),
 'Legacy till session tagged with JWT session identifier');

set local role authenticated;
select pg_temp.check(not public.covi_ai_owner_session_allowed(:'shop'),
 'Chatbot denied on shared legacy till session');
select set_config('request.jwt.claim.session_id',:'sid_b',true);
select pg_temp.check(public.covi_ai_owner_session_allowed(:'shop'),
 'Different personal session remains available');
reset role;
update public.till_sessions set owner_auth_session_id=null where shop_id=:'shop';

set local role authenticated;
select pg_temp.check(not public.covi_ai_owner_session_allowed(:'shop'),
 'Untyped legacy till is fail closed even on a different device');
reset role;
update public.till_sessions set closed_at=now() where shop_id=:'shop';

set local role authenticated;
select set_config('request.jwt.claim.session_id',:'sid_a',true);
reset role;
insert into public.shop_cashier_tills(shop_id,cashier_id,token_hash,opened_by,expires_at)
 values (:'shop',:'cashier',decode(repeat('cd',32),'hex'),:'owner',now()+interval '2 hours');
select pg_temp.check(
  (select owner_auth_session_id=:'sid_a' from public.shop_cashier_tills
   where shop_id=:'shop'), 'Shared profile till tagged with JWT session');

set local role authenticated;
select pg_temp.check(not public.covi_ai_owner_session_allowed(:'shop'),
 'Shared profile cashier session blocks chatbot too');
reset role;
update public.shop_cashier_tills set closed_at=now() where shop_id=:'shop';

set local role authenticated;
select pg_temp.check(public.covi_ai_owner_session_allowed(:'shop'),
 'Closing till restores chatbot on personal session');
select set_config('request.jwt.claim.session_id','',true);
select pg_temp.check(not public.covi_ai_owner_session_allowed(:'shop'),
 'Session without signed session_id is denied');
select set_config('request.jwt.claim.sub',:'another',true);
select set_config('request.jwt.claim.session_id',:'sid_b',true);
select pg_temp.check(not public.covi_ai_owner_session_allowed(:'shop'),
 'Different user cannot access owner assistant');
rollback;
