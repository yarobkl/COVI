-- covi_my_subscription_state() (migration 20261010182000) : ce que voit le commerçant connecté.
-- Lancé par tests/sql/run.sh après toutes les migrations. Tout est annulé (ROLLBACK) à la fin.
-- Chaque cas compare le jsonb renvoyé à l'attendu ET `writable` à covi_shop_subscription_writable
-- (la règle du garde-fou) sur la boutique du compte, pour qu'elles ne divergent jamais.
\set ON_ERROR_STOP 1
begin;

create table pg_temp.res (who text primary key, state jsonb);
grant select, insert on pg_temp.res to authenticated, anon;
create table pg_temp.chk (ord serial, label text, ok boolean, observed text);

create function pg_temp.chk(p_label text, p_ok boolean, p_observed text) returns void
language plpgsql as $$
begin
  insert into pg_temp.chk(label, ok, observed) values (p_label, p_ok is true, coalesce(p_observed, 'NULL'));
  raise notice '% | % | %', case when p_ok is true then 'ok  ' else 'FAIL' end, p_label, coalesce(p_observed, 'NULL');
end $$;

-- ---------------------------------------------------------------------------------------------
-- Mise en place (rôle propriétaire = serveur).
-- ---------------------------------------------------------------------------------------------
\set V0 '00000000-0000-0000-0000-00000000b000'
\set V1 '00000000-0000-0000-0000-00000000b001'
\set A  '00000000-0000-0000-0000-00000000b00a'
\set Q  '00000000-0000-0000-0000-00000000b00b'
\set E  '00000000-0000-0000-0000-00000000b00e'
\set U  '00000000-0000-0000-0000-00000000b00f'
\set P  '00000000-0000-0000-0000-00000000b0a0'
\set G  '00000000-0000-0000-0000-00000000b0b0'
\set N  '00000000-0000-0000-0000-00000000b0c0'

insert into auth.users(id) values (:'V0'), (:'V1'), (:'A'), (:'Q'), (:'E'), (:'U'), (:'P'), (:'G'), (:'N');

-- Une boutique par compte (sauf V0), deux pour Q.
insert into public.shops(id, owner_id, name)
select ('20000000-0000-0000-0000-' || lpad(right(u::text, 4), 12, '0'))::uuid, u, 'Boutique ' || right(u::text, 4)
from unnest(array[:'V1', :'A', :'Q', :'E', :'U', :'P', :'G', :'N']::uuid[]) as u;
insert into public.shops(owner_id, name) values (:'Q', 'Boutique Q2');

insert into public.covi_owner_accounts(user_id)
select unnest(array[:'A', :'Q', :'E', :'U', :'P', :'G', :'N']::uuid[]);

insert into public.covi_subscriptions(owner_account_id, plan_id, status, shop_limit, period_start, period_end, grace_until)
select a.id, (select id from public.covi_subscription_plans where code = 'covi-monthly-v1'), v.status, v.lim,
       now() + v.ps, now() + v.pe, now() + v.gu
from (values
  (:'A'::uuid, 'active', 2, interval '-5 days', interval '25 days', null::interval),
  (:'Q'::uuid, 'active', 2, interval '-5 days', interval '25 days', null),
  (:'E'::uuid, 'active', 2, interval '-40 days', interval '-10 days', null),
  (:'U'::uuid, 'suspended', 3, interval '-5 days', interval '25 days', null),
  (:'G'::uuid, 'grace', 2, interval '-40 days', interval '-2 days', interval '5 days')
) as v(uid, status, lim, ps, pe, gu)
join public.covi_owner_accounts a on a.user_id = v.uid;
-- P : première facture jamais payée (period_start nul).
insert into public.covi_subscriptions(owner_account_id, plan_id, status, shop_limit)
select a.id, (select id from public.covi_subscription_plans where code = 'covi-monthly-v1'), 'pending_payment', 1
from public.covi_owner_accounts a where a.user_id = :'P';
-- N : compte SaaS sans aucun abonnement.

-- ---------------------------------------------------------------------------------------------
-- Appels en tant que chaque commerçant (rôle authenticated, sub = l'utilisateur).
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', :'V0', true);
set local role authenticated;
insert into pg_temp.res values ('V0', public.covi_my_subscription_state());
reset role;
select set_config('request.jwt.claim.sub', :'V1', true);
set local role authenticated;
insert into pg_temp.res values ('V1', public.covi_my_subscription_state());
reset role;
select set_config('request.jwt.claim.sub', :'A', true);
set local role authenticated;
insert into pg_temp.res values ('A', public.covi_my_subscription_state());
reset role;
select set_config('request.jwt.claim.sub', :'Q', true);
set local role authenticated;
insert into pg_temp.res values ('Q', public.covi_my_subscription_state());
reset role;
select set_config('request.jwt.claim.sub', :'E', true);
set local role authenticated;
insert into pg_temp.res values ('E', public.covi_my_subscription_state());
reset role;
select set_config('request.jwt.claim.sub', :'U', true);
set local role authenticated;
insert into pg_temp.res values ('U', public.covi_my_subscription_state());
reset role;
select set_config('request.jwt.claim.sub', :'P', true);
set local role authenticated;
insert into pg_temp.res values ('P', public.covi_my_subscription_state());
reset role;
select set_config('request.jwt.claim.sub', :'G', true);
set local role authenticated;
insert into pg_temp.res values ('G', public.covi_my_subscription_state());
reset role;
select set_config('request.jwt.claim.sub', :'N', true);
set local role authenticated;
insert into pg_temp.res values ('N', public.covi_my_subscription_state());
reset role;

-- Utilisateur sans JWT (rôle authenticated mais auth.uid() nul) : refusé.
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
do $$
begin
  perform public.covi_my_subscription_state();
  insert into pg_temp.res values ('nosub', '"OK"'::jsonb);
exception when others then
  insert into pg_temp.res values ('nosub', to_jsonb(sqlstate || ' ' || sqlerrm));
end $$;
reset role;

-- anon : aucun droit d'exécution.
select set_config('request.jwt.claim.sub', :'A', true);
set local role anon;
do $$
begin
  perform public.covi_my_subscription_state();
  insert into pg_temp.res values ('anon', '"OK"'::jsonb);
exception when others then
  insert into pg_temp.res values ('anon', to_jsonb(sqlstate || ' ' || sqlerrm));
end $$;
reset role;

-- ---------------------------------------------------------------------------------------------
-- Vérifications.
-- ---------------------------------------------------------------------------------------------
create function pg_temp.expect(p_who text, p_label text, p_expected jsonb) returns void
language plpgsql as $$
declare v jsonb;
begin
  select state into v from pg_temp.res where who = p_who;
  -- periodEnd dépend de now() : seule sa présence est comparée.
  perform pg_temp.chk(p_label,
    (v - 'periodEnd') = p_expected and (v ? 'periodEnd'),
    v::text);
end $$;

select pg_temp.expect('V0', 'V1 sans boutique : écriture permise, peut créer sa 1re boutique',
  '{"status":null,"writable":true,"shopLimit":1,"shopCount":0,"canAddShop":true,"isLegacyV1":true}');
select pg_temp.expect('V1', 'V1 avec 1 boutique : écriture permise, pas de 2e boutique',
  '{"status":null,"writable":true,"shopLimit":1,"shopCount":1,"canAddShop":false,"isLegacyV1":true}');
select pg_temp.expect('A', 'actif, quota 2, 1 boutique : écriture permise, ajout possible',
  '{"status":"active","writable":true,"shopLimit":2,"shopCount":1,"canAddShop":true,"isLegacyV1":false}');
select pg_temp.expect('Q', 'actif, quota atteint (2/2) : écriture permise, ajout impossible',
  '{"status":"active","writable":true,"shopLimit":2,"shopCount":2,"canAddShop":false,"isLegacyV1":false}');
select pg_temp.expect('E', 'actif mais échu : lecture seule, ajout impossible',
  '{"status":"active","writable":false,"shopLimit":2,"shopCount":1,"canAddShop":false,"isLegacyV1":false}');
select pg_temp.expect('U', 'suspendu : lecture seule, ajout impossible',
  '{"status":"suspended","writable":false,"shopLimit":3,"shopCount":1,"canAddShop":false,"isLegacyV1":false}');
select pg_temp.expect('P', 'première facture jamais payée : écriture permise, ajout impossible',
  '{"status":"pending_payment","writable":true,"shopLimit":1,"shopCount":1,"canAddShop":false,"isLegacyV1":false}');
select pg_temp.expect('G', 'grâce en cours : écriture permise, ajout impossible',
  '{"status":"grace","writable":true,"shopLimit":2,"shopCount":1,"canAddShop":false,"isLegacyV1":false}');
select pg_temp.expect('N', 'compte SaaS sans abonnement : lecture seule',
  '{"status":null,"writable":false,"shopLimit":null,"shopCount":1,"canAddShop":false,"isLegacyV1":false}');

-- Isolation : chacun ne voit que son compte (A voit 1 boutique et quota 2, pas les 2 de Q ni le 3 de U).
select pg_temp.chk('isolation : chaque appel ne décrit que le compte de auth.uid()',
  (select count(distinct state) from pg_temp.res where who in ('A', 'Q', 'U')) = 3
  and (select state->>'shopCount' from pg_temp.res where who = 'A') = '1',
  (select string_agg(who || '=' || (state->>'shopCount'), ' ' order by who) from pg_temp.res where who in ('A','Q','U')));

-- Même règle que le garde-fou, boutique par boutique.
select pg_temp.chk('writable = covi_shop_subscription_writable(boutique) pour chaque compte',
  bool_and(((r.state->>'writable')::boolean) = public.covi_shop_subscription_writable(sh.id)),
  string_agg(r.who || ':' || (r.state->>'writable') || '/' || public.covi_shop_subscription_writable(sh.id), ' ' order by r.who))
from pg_temp.res r
join public.shops sh on sh.owner_id = (case r.who
  when 'V1' then :'V1'::uuid when 'A' then :'A'::uuid when 'Q' then :'Q'::uuid when 'E' then :'E'::uuid
  when 'U' then :'U'::uuid when 'P' then :'P'::uuid when 'G' then :'G'::uuid when 'N' then :'N'::uuid end);

select pg_temp.chk('sans utilisateur (auth.uid() nul) : Authentication required',
  (select state #>> '{}' from pg_temp.res where who = 'nosub') like '42501 Authentication required%',
  (select state #>> '{}' from pg_temp.res where who = 'nosub'));
select pg_temp.chk('anon : permission refusée (42501)',
  (select state #>> '{}' from pg_temp.res where who = 'anon') like '42501 permission denied%',
  (select state #>> '{}' from pg_temp.res where who = 'anon'));

-- Statique : SECURITY DEFINER, search_path vide, STABLE, droits.
select pg_temp.chk('statique : SECURITY DEFINER, search_path="", STABLE',
  p.prosecdef and p.proconfig = array['search_path=""'] and p.provolatile = 's',
  p.prosecdef || ' ' || array_to_string(p.proconfig, ',') || ' ' || p.provolatile::text)
from pg_proc p where p.oid = 'public.covi_my_subscription_state()'::regprocedure;
select pg_temp.chk('droits : authenticated seul (ni anon, ni public)',
  has_function_privilege('authenticated', 'public.covi_my_subscription_state()', 'execute')
  and not has_function_privilege('anon', 'public.covi_my_subscription_state()', 'execute')
  and not exists (
    select 1 from pg_proc p, aclexplode(p.proacl) a
    where p.oid = 'public.covi_my_subscription_state()'::regprocedure and a.grantee = 0),
  'ok');

-- Lecture seule : aucune écriture faite pendant les appels.
select pg_temp.chk('lecture seule : aucun compte, abonnement ni boutique créé par les appels',
  (select count(*) from public.covi_owner_accounts where user_id in (:'V0', :'V1')) = 0
  and (select count(*) from public.shops where owner_id = :'V0') = 0, 'ok');

do $$
declare n integer;
begin
  select count(*) into n from pg_temp.chk where not ok;
  if n > 0 then
    raise exception 'FAIL saas_my_state : % échec(s) sur % vérifications', n, (select count(*) from pg_temp.chk);
  end if;
  raise notice 'PASS saas_my_state : % vérifications conformes', (select count(*) from pg_temp.chk);
end $$;

rollback;
