-- Vérification de la préproduction après chargement des données fictives (lecture seule).
-- Attendu : 3 établissements, 2 ventes = 51 000, robe 4, 6 tables, 5 plats, 10 rendez-vous,
-- 0 table sans RLS, 0 appel vers la production, et chaque propriétaire ne voit que son établissement.
\pset format unaligned
\pset tuples_only on
select 'shops='||count(*) from public.shops;
select 'ventes='||count(*)||' total='||coalesce(sum(total_amount),0) from public.sales where shop_id='10000000-0000-0000-0000-0000000000a1';
select 'stock robe='||quantity_on_hand from public.products where id='20000000-0000-0000-0000-0000000000a1';
select 'tables='||count(*) from public.restaurant_tables;
select 'plats/boissons='||count(*) from public.restaurant_menu_items;
select 'rdv salon='||count(*) from public.salon_appointments;
select 'employes salon='||count(*) from public.employees where shop_id='10000000-0000-0000-0000-00000000f001';
select 'clients salon='||count(*) from public.salon_clients;
select 'notes salon='||count(*)||' payees='||count(*) filter (where paid_at is not null) from public.salon_tickets;
select 'depenses='||count(*) from public.shop_expenses;
select 'tables public sans RLS='||count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and not c.relrowsecurity;
select 'tables public='||count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r';
select 'fonctions SECURITY DEFINER sans search_path='||count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and not exists (select 1 from unnest(coalesce(p.proconfig,'{}')) x where x like 'search_path=%');
select 'cron vers prod='||count(*) from pg_proc where prosrc like '%bmbwmwgfzrijglzcgjut%';
select 'anon SELECT autorisé sur tables public='||count(*) filter (where has_table_privilege('anon', c.oid, 'select'))||'/'||count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r';
-- Chaque utilisateur fictif compte ce qu'il voit par table (refusé = privilège retiré : lecture via RPC uniquement)
do $$
declare u text; tb text; n bigint; r text;
begin
  foreach u in array array['00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-00000000f001','00000000-0000-0000-0000-00000000f002','00000000-0000-0000-0000-0000000000ff'] loop
    r := '';
    foreach tb in array array['shops','products','sales','restaurant_tables','restaurant_menu_items','salon_clients','salon_appointments','salon_tickets','employees','shop_expenses'] loop
      begin
        perform set_config('request.jwt.claim.sub', u, true);
        perform set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true);
        execute 'set local role authenticated';
        execute format('select count(*) from public.%I', tb) into n;
        execute 'reset role';
        r := r || tb || '=' || n || ' ';
      exception when insufficient_privilege then
        r := r || tb || '=refusé ';
      end;
    end loop;
    raise notice 'VOIT % : %', right(u, 4), r;
  end loop;
end $$;
