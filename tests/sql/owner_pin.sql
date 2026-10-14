-- Code du responsable et mode comptoir (migration 20261014090200_owner_pin).
-- Données fictives uniquement. Tout se passe dans une transaction annulée à la fin.
--
-- Acteurs :
--   OA propriétaire de SA ; OB propriétaire de SB ;
--   C1 « Awa » caissière de SA (PIN 5937, remise max 10 %) ;
--   X  utilisateur connecté sans boutique.
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

\set sa '10000000-0000-0000-0000-0000000000a1'
\set sb '10000000-0000-0000-0000-0000000000b1'
\set as_pg 'reset role;'
\set as_oa 'reset role; do $$begin perform set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-0000000000a1'', true); end$$; set local role authenticated;'
\set as_ob 'reset role; do $$begin perform set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-0000000000b1'', true); end$$; set local role authenticated;'
\set as_c1 'reset role; do $$begin perform set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-0000000000a2'', true); end$$; set local role authenticated;'
\set as_x 'reset role; do $$begin perform set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-0000000000ff'', true); end$$; set local role authenticated;'
\set as_anon 'reset role; do $$begin perform set_config(''request.jwt.claim.sub'', '''', true); end$$; set local role anon;'

-- Fixtures --------------------------------------------------------------------------------------
insert into auth.users(id) values
  ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-0000000000a2'), ('00000000-0000-0000-0000-0000000000ff');
insert into public.shops(id, owner_id, name) values
  (:'sa', '00000000-0000-0000-0000-0000000000a1', 'Boutique SA'),
  (:'sb', '00000000-0000-0000-0000-0000000000b1', 'Boutique SB');
insert into public.shop_members(id, shop_id, user_id, display_name, max_discount_pct) values
  ('50000000-0000-0000-0000-0000000000a2', :'sa', '00000000-0000-0000-0000-0000000000a2',
   'Awa', 10);
insert into public.member_pins(member_id, pin_hash) values
  ('50000000-0000-0000-0000-0000000000a2', extensions.crypt('5937', extensions.gen_salt('bf', 10)));
insert into public.products(id, shop_id, name, initial_sale_price, quantity_on_hand) values
  ('30000000-0000-0000-0000-0000000000a1', :'sa', 'Jean bleu', 10000, 10);
\set m1 '50000000-0000-0000-0000-0000000000a2'

-- 0. Déclarations et privilèges --------------------------------------------------------------------
select pg_temp.check(c.relrowsecurity
    and not exists (select 1 from pg_policies where schemaname = 'public'
                    and tablename = 'owner_pins'),
  'owner_pins : RLS active, aucune politique')
from pg_class c where c.oid = 'public.owner_pins'::regclass;
select pg_temp.check(bool_and(not has_table_privilege(r, 'public.owner_pins', p)),
  'owner_pins : aucun privilège pour anon ni authenticated (pas même SELECT)')
from unnest(array['anon', 'authenticated']) r,
     unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'trigger',
                  'references']) p;
select pg_temp.check(bool_and(p.prosecdef and p.proconfig = array['search_path=""']),
  'fonctions du code du responsable : SECURITY DEFINER, search_path vide')
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in (
  'owner_pin_check', 'owner_pin_audit_failure', 'owner_pin_status', 'set_owner_pin',
  'reset_owner_pin', 'verify_owner_pin', 'leave_counter_mode', 'unlock_till_session',
  'open_till_session');
select pg_temp.check(bool_and(
    has_function_privilege('authenticated', p.oid, 'execute')
    and not has_function_privilege('anon', p.oid, 'execute')),
  'RPC du mode comptoir : EXECUTE pour authenticated seulement')
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in (
  'owner_pin_status', 'set_owner_pin', 'reset_owner_pin', 'verify_owner_pin',
  'leave_counter_mode', 'unlock_till_session', 'open_till_session');
select pg_temp.check(bool_and(not has_function_privilege('authenticated', p.oid, 'execute')
                              and not has_function_privilege('anon', p.oid, 'execute')),
  'outils internes (owner_pin_check, owner_pin_audit_failure) : non exécutables')
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('owner_pin_check', 'owner_pin_audit_failure');
select pg_temp.check(not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')),
  'anon : toujours aucune fonction de public exécutable');

-- 1. Pas encore de code : le mode comptoir ne s'ouvre pas ----------------------------------------
:as_oa
select pg_temp.check(public.owner_pin_status(:'sa') = '{"pin_set": false, "locked_until": null}',
  'owner_pin_status : pas de code au départ');
select pg_temp.expect_msg(format('select public.open_till_session(%L, %L, %L)', :'sa', :'m1',
    '5937'), 'Owner PIN required', 'open_till_session refusé sans code du responsable');
select pg_temp.check((public.verify_owner_pin(:'sa', '7391')) ->> 'status' = 'not_set',
  'verify_owner_pin sans code : not_set');
select pg_temp.check((public.leave_counter_mode(:'sa', '7391')) ->> 'status' = 'not_set',
  'leave_counter_mode sans code : not_set (le front fait choisir un code d''abord)');

-- 2. Format et codes triviaux (mêmes règles que les PIN des caissiers) ---------------------------
select pg_temp.expect_msg(format('select public.set_owner_pin(%L, %L)', :'sa', p), m,
  'code du responsable « ' || p || ' » refusé')
from (values ('123', 'Invalid PIN format'), ('1234567', 'Invalid PIN format'),
             ('12a4', 'Invalid PIN format'), ('', 'Invalid PIN format'),
             ('0000', 'PIN too simple'), ('1234', 'PIN too simple'), ('9876', 'PIN too simple'),
             ('1212', 'PIN too simple'), ('123123', 'PIN too simple'),
             ('2580', 'PIN too simple')) v(p, m);
select pg_temp.expect_error(format('select public.set_owner_pin(%L, %L)', :'sa', '1111'),
  '22023', 'code trivial : SQLSTATE 22023');
select pg_temp.check((public.owner_pin_status(:'sa')) ->> 'pin_set' = 'false',
  'aucun code enregistré après les refus');

-- 3. Choix du code : bcrypt, jamais en clair --------------------------------------------------------
select pg_temp.check((public.set_owner_pin(:'sa', '7391')) ->> 'status' = 'ok',
  'OA choisit son code');
select pg_temp.check((public.owner_pin_status(:'sa')) ->> 'pin_set' = 'true',
  'owner_pin_status : code défini');
select pg_temp.expect_error($$select * from public.owner_pins$$, '42501',
  'owner_pins illisible, même par le propriétaire');
:as_pg
select pg_temp.check((select pin_hash like '$2a$10$%' and length(pin_hash) = 60
                             and pin_hash <> '7391' and position('7391' in pin_hash) = 0
                             and extensions.crypt('7391', pin_hash) = pin_hash
                      from public.owner_pins where shop_id = :'sa'),
  'empreinte bcrypt (coût 10), le code n''est pas stocké en clair');

-- 4. Changement : l'ancien code est exigé -----------------------------------------------------------
:as_oa
select pg_temp.check((public.set_owner_pin(:'sa', '8462')) ->> 'status' = 'invalid',
  'changement sans l''ancien code : refusé (compte comme un essai)');
select pg_temp.check((public.set_owner_pin(:'sa', '8462', '0000')) ->> 'status' = 'invalid',
  'changement avec un mauvais ancien code : refusé');
select pg_temp.check((public.set_owner_pin(:'sa', '8462', '7391')) ->> 'status' = 'ok',
  'changement avec le bon ancien code');
select pg_temp.check((public.verify_owner_pin(:'sa', '7391')) ->> 'status' = 'invalid'
  and (public.verify_owner_pin(:'sa', '8462')) ->> 'status' = 'ok',
  'l''ancien code ne marche plus, le nouveau oui (compteur remis à zéro)');
:as_pg
select pg_temp.check((select failed_attempts = 0 and locked_until is null
                      from public.owner_pins where shop_id = :'sa'),
  'bon code : compteur remis à zéro');

-- 5. Autres utilisateurs : refusés ------------------------------------------------------------------
:as_c1
select pg_temp.expect_msg(format('select public.%s', f), 'Shop not found',
  'caissier C1 : ' || split_part(f, '(', 1) || ' refusé')
from unnest(array[
  format('owner_pin_status(%L)', :'sa'),
  format('set_owner_pin(%L, %L)', :'sa', '5173'),
  format('verify_owner_pin(%L, %L)', :'sa', '8462'),
  format('reset_owner_pin(%L)', :'sa'),
  format('leave_counter_mode(%L, %L)', :'sa', '8462'),
  format('unlock_till_session(%L, %L, %L)', :'sa', repeat('a', 64), '5937')]) f;
:as_x
select pg_temp.expect_msg(format('select public.verify_owner_pin(%L, %L)', :'sa', '8462'),
  'Shop not found', 'utilisateur sans boutique : verify_owner_pin refusé');
:as_ob
select pg_temp.expect_msg(format('select public.verify_owner_pin(%L, %L)', :'sa', '8462'),
  'Shop not found', 'autre propriétaire (OB) : verify_owner_pin de SA refusé');
select pg_temp.expect_msg(format('select public.set_owner_pin(%L, %L)', :'sa', '5173'),
  'Shop not found', 'autre propriétaire (OB) : set_owner_pin de SA refusé');
select pg_temp.check((public.owner_pin_status(:'sb')) ->> 'pin_set' = 'false',
  'OB : SA a un code, SB n''en a pas (un code par boutique)');
select pg_temp.check((public.verify_owner_pin(:'sb', '8462')) ->> 'status' = 'not_set',
  'le code de SA ne vaut rien dans SB');
:as_anon
select pg_temp.expect_error(format('select public.%s', f), '42501', 'anon : ' || f || ' refusé')
from unnest(array[
  format('owner_pin_status(%L)', :'sa'),
  format('verify_owner_pin(%L, %L)', :'sa', '8462'),
  format('leave_counter_mode(%L, %L)', :'sa', '8462')]) f;
:as_pg
select pg_temp.check((select failed_attempts from public.owner_pins where shop_id = :'sa') = 0,
  'les appels refusés (autres utilisateurs) ne touchent pas au compteur de OA');

-- 6. Mode comptoir : ouverture, verrouillage, déverrouillage, sortie --------------------------------
:as_oa
select r ->> 'token' as tok, r ->> 'status' as tok_status, r ->> 'user_id' as tok_user,
       r ->> 'can_view_shop_sales' as tok_view
from public.open_till_session(:'sa', :'m1', '5937') r \gset
select pg_temp.check(:'tok_status' = 'ok' and :'tok' ~ '^[0-9a-f]{64}$'
  and :'tok_user' = '00000000-0000-0000-0000-0000000000a2' and :'tok_view' = 'false',
  'session de caisse ouverte avec le code du responsable défini (user_id, can_view_shop_sales)');
select pg_temp.check((public.unlock_till_session(:'sa', :'tok', '0000')) ->> 'status' = 'invalid',
  'caisse verrouillée : mauvais PIN du caissier refusé');
select pg_temp.check((public.unlock_till_session(:'sa', :'tok', '5937')) ->> 'status' = 'ok',
  'caisse verrouillée : rouverte avec le PIN du caissier');
:as_ob
select pg_temp.expect_msg(format('select public.unlock_till_session(%L, %L, %L)', :'sb', :'tok',
    '5937'), 'Till session invalid', 'jeton de SA inutilisable dans SB');
:as_oa
select pg_temp.expect_msg(format('select public.unlock_till_session(%L, %L, %L)', :'sa',
    repeat('f', 64), '5937'), 'Till session invalid', 'jeton inconnu refusé');
-- Mauvais code du responsable : la session reste ouverte.
select pg_temp.check((public.leave_counter_mode(:'sa', '1590', :'tok')) ->> 'status' = 'invalid',
  'sortie du mode comptoir : mauvais code refusé');
select pg_temp.check(public.record_sale(:'sa', '30000000-0000-0000-0000-0000000000a1', 1, 9000,
  'cash', gen_random_uuid(), p_till_session => :'tok') is not null,
  'après un mauvais code, la caisse de C1 reste ouverte');
select pg_temp.check((public.leave_counter_mode(:'sa', '8462', :'tok')) ->> 'status' = 'ok',
  'sortie du mode comptoir avec le bon code');
select pg_temp.expect_msg(format($q$select public.record_sale(%L, %L, 1, 9000, 'cash',
  gen_random_uuid(), p_till_session => %L)$q$, :'sa', '30000000-0000-0000-0000-0000000000a1',
  :'tok'), 'Till session invalid', 'sortie : la session de caisse est fermée');
select pg_temp.check((public.leave_counter_mode(:'sa', '8462', :'tok')) ->> 'status' = 'ok',
  'sortie idempotente (session déjà fermée)');

-- 7. Verrouillage : 5 échecs → 15 minutes, même avec le bon code -------------------------------------
select pg_temp.check(array_agg((public.verify_owner_pin(:'sa', '1590')) ->> 'status' order by g)
                     = array['invalid', 'invalid', 'invalid', 'invalid', 'locked', 'locked'],
  '5 mauvais codes → verrouillage')
from generate_series(1, 6) g;
select pg_temp.check((public.verify_owner_pin(:'sa', '8462')) ->> 'status' = 'locked'
  and (public.leave_counter_mode(:'sa', '8462')) ->> 'status' = 'locked',
  'verrouillé : même le bon code est refusé (verify et leave_counter_mode)');
select pg_temp.check((public.set_owner_pin(:'sa', '5173', '8462')) ->> 'status' = 'locked',
  'verrouillé : changement de code refusé aussi');
select pg_temp.check((public.owner_pin_status(:'sa')) ->> 'locked_until' is not null,
  'owner_pin_status signale le verrouillage');
:as_pg
select pg_temp.check((select locked_until between now() + interval '14 minutes'
                                              and now() + interval '15 minutes 1 second'
                      from public.owner_pins where shop_id = :'sa'),
  'verrouillage de 15 minutes');
update public.owner_pins set locked_until = now() - interval '1 second' where shop_id = :'sa';
:as_oa
select pg_temp.check((public.verify_owner_pin(:'sa', '1590')) = '{"status": "invalid", "attempts_left": 4}',
  'après le verrouillage, le compteur repart de zéro');
select pg_temp.check((public.verify_owner_pin(:'sa', '8462')) ->> 'status' = 'ok',
  'puis le bon code passe');

-- 8. Code oublié : réinitialisation par le propriétaire -------------------------------------------
select (public.open_till_session(:'sa', :'m1', '5937')) ->> 'token' as tok2 \gset
select pg_temp.check(public.reset_owner_pin(:'sa'), 'reset_owner_pin efface le code');
select pg_temp.check(not public.reset_owner_pin(:'sa'), 'reset_owner_pin idempotent');
select pg_temp.expect_msg(format($q$select public.record_sale(%L, %L, 1, 9000, 'cash',
  gen_random_uuid(), p_till_session => %L)$q$, :'sa', '30000000-0000-0000-0000-0000000000a1',
  :'tok2'), 'Till session invalid', 'réinitialisation : sessions de caisse fermées');
select pg_temp.expect_msg(format('select public.open_till_session(%L, %L, %L)', :'sa', :'m1',
    '5937'), 'Owner PIN required', 'sans code : plus de nouvelle session de caisse');
select pg_temp.check((public.set_owner_pin(:'sa', '5173')) ->> 'status' = 'ok',
  'nouveau code choisi sans l''ancien après réinitialisation');

-- 9. Journal : actions tracées, jamais le code ---------------------------------------------------------
select pg_temp.check((select count(distinct action) from public.shop_audit_log
                      where shop_id = :'sa' and action in (
                        'owner_pin_set', 'owner_pin_changed', 'owner_pin_failed',
                        'owner_pin_reset', 'counter_mode_left', 'till_session_opened',
                        'till_session_closed', 'till_session_pin_failed')) = 8,
  'journal : code choisi, changé, échoué, réinitialisé ; sortie du mode comptoir ; sessions');
select pg_temp.check((select count(*) from public.shop_audit_log
                      where action = 'owner_pin_failed' and details ->> 'result' = 'locked') >= 1,
  'journal : verrouillage du code tracé');
select pg_temp.check(not exists (
    select 1 from public.shop_audit_log l
    where l::text ~ '"(7391|8462|1590|5173|5937)"'
       or l::text like '%$2a$%'
       or l::text like '%' || :'tok' || '%'
       or l.details ?| array['pin', 'new_pin', 'current_pin', 'pin_hash', 'token']),
  'journal : jamais de code, d''empreinte ni de jeton');

reset role;
rollback;
