-- Agrégats calculés en base.
--
-- Le front calculait le tableau de bord, les statistiques et la rentabilité en téléchargeant
-- toutes les lignes (ventes, lignes de vente, produits). PostgREST plafonne une réponse à
-- 1 000 lignes : au-delà, les chiffres devenaient silencieusement faux. Ces fonctions renvoient
-- directement les totaux.
--
-- Règles communes :
--   - SECURITY INVOKER : la RLS de l'appelant s'applique ; un utilisateur ne voit que sa
--     boutique (les fonctions jsonb lèvent 'Shop not found' pour une autre boutique, les
--     fonctions table renvoient zéro ligne) ;
--   - STABLE, search_path vide, objets qualifiés ;
--   - p_tz (défaut 'Africa/Brazzaville') : fuseau IANA dans lequel sont calculés « aujourd'hui »
--     et les mois civils. Une vente le 1er à 00:30 heure de Brazzaville (30 du mois précédent à
--     23:30 UTC) compte pour le nouveau mois ;
--   - p_include_test (défaut false) : exclut les données marquées is_test ;
--   - p_at (défaut now()) : instant de référence, utile pour les tests et pour consulter une
--     période passée. Le front n'a pas à le passer.
--   - les montants sont en FCFA (XAF), sans conversion.

-- Index ----------------------------------------------------------------------------------------
-- Couvrant pour les sommes de ventes par période : parcours d'index seul, sans lire la table.
create index if not exists sales_shop_sold_cover_idx
  on public.sales (shop_id, sold_at) include (total_amount, is_test);
-- Couvrant pour joindre les lignes de vente à leurs ventes sans lire sale_items.
create index if not exists sale_items_sale_cover_idx
  on public.sale_items (sale_id) include (product_id, quantity, sold_unit_price);
-- L'index (sale_id) seul est désormais redondant avec le couvrant ci-dessus.
drop index if exists public.sale_items_sale_idx;

-- Tableau de bord -----------------------------------------------------------------------------
-- Mêmes définitions que dashboard() de src/lib/operations.ts, en heure locale p_tz :
--   todaySales / monthSales / saleCount : ventes du jour / du mois civil en cours ;
--   charges      : charges dont expense_date est dans le mois en cours (le front comptait aussi
--                  les charges datées des mois suivants : elles sont ici exclues) ;
--   arrivalCost  : coût des arrivages 'received' dont received_date est dans le mois en cours ;
--                  coût = global_cost, ou marchandise + transport + douane si global_cost = 0 ;
--   stock        : unités en stock des produits 'active' ;
--   profitBeforeCharges = monthSales - arrivalCost ; profit = profitBeforeCharges - charges ;
--   arrivalsInProgress / ordersInProgress / balloonsInProgress : arrivages en draft, ordered
--                  ou in_transit, au total et par type ; inProgressByStatus : détail par statut.
-- Les ventes « en attente » (file hors connexion) vivent dans le navigateur, pas en base : elles
-- ne peuvent pas apparaître ici.
create or replace function public.shop_dashboard(
  p_shop_id uuid,
  p_tz text default 'Africa/Brazzaville',
  p_include_test boolean default false,
  p_at timestamptz default now()
)
returns jsonb
language plpgsql
stable
security invoker
set search_path to ''
as $function$
declare
  v_local timestamp := p_at at time zone p_tz;
  v_today date := v_local::date;
  v_month date := pg_catalog.date_trunc('month', v_local)::date;
  v_next_month date := (v_month + interval '1 month')::date;
  v_today_start timestamptz := v_today::timestamp at time zone p_tz;
  v_tomorrow_start timestamptz := (v_today + 1)::timestamp at time zone p_tz;
  v_month_start timestamptz := v_month::timestamp at time zone p_tz;
  v_next_month_start timestamptz := v_next_month::timestamp at time zone p_tz;
  v_today_sales numeric;
  v_month_sales numeric;
  v_sale_count bigint;
  v_charges numeric;
  v_arrival_cost numeric;
  v_stock bigint;
  v_in_progress jsonb;
begin
  if not exists (select 1 from public.shops s where s.id = p_shop_id) then
    raise exception 'Shop not found' using errcode = '42501';
  end if;

  select coalesce(sum(s.total_amount), 0),
         count(*),
         coalesce(sum(s.total_amount) filter (
           where s.sold_at >= v_today_start and s.sold_at < v_tomorrow_start), 0)
    into v_month_sales, v_sale_count, v_today_sales
  from public.sales s
  where s.shop_id = p_shop_id
    and s.sold_at >= v_month_start and s.sold_at < v_next_month_start
    and (p_include_test or not s.is_test);

  select coalesce(sum(e.amount), 0) into v_charges
  from public.shop_expenses e
  where e.shop_id = p_shop_id
    and e.expense_date >= v_month and e.expense_date < v_next_month
    and (p_include_test or not e.is_test);

  select coalesce(sum(coalesce(nullif(a.global_cost, 0),
                               a.merchandise_cost + a.transport_cost + a.customs_cost)), 0)
    into v_arrival_cost
  from public.arrivals a
  where a.shop_id = p_shop_id
    and a.status = 'received'
    and a.received_date >= v_month and a.received_date < v_next_month
    and (p_include_test or not a.is_test);

  select coalesce(sum(p.quantity_on_hand), 0) into v_stock
  from public.products p
  where p.shop_id = p_shop_id and p.status = 'active' and (p_include_test or not p.is_test);

  select jsonb_build_object(
           'total', count(*),
           'supplierOrders', count(*) filter (where a.kind = 'supplier_order'),
           'balloons', count(*) filter (where a.kind = 'balloon'),
           'byStatus', jsonb_build_object(
             'draft', count(*) filter (where a.status = 'draft'),
             'ordered', count(*) filter (where a.status = 'ordered'),
             'in_transit', count(*) filter (where a.status = 'in_transit')))
    into v_in_progress
  from public.arrivals a
  where a.shop_id = p_shop_id
    and a.status in ('draft', 'ordered', 'in_transit')
    and (p_include_test or not a.is_test);

  return jsonb_build_object(
    'timeZone', p_tz,
    'today', v_today,
    'monthStart', v_month,
    'todaySales', v_today_sales,
    'monthSales', v_month_sales,
    'saleCount', v_sale_count,
    'charges', v_charges,
    'arrivalCost', v_arrival_cost,
    'stock', v_stock,
    'profitBeforeCharges', v_month_sales - v_arrival_cost,
    'profit', v_month_sales - v_arrival_cost - v_charges,
    'arrivalsInProgress', (v_in_progress ->> 'total')::bigint,
    'ordersInProgress', (v_in_progress ->> 'supplierOrders')::bigint,
    'balloonsInProgress', (v_in_progress ->> 'balloons')::bigint,
    'inProgressByStatus', v_in_progress -> 'byStatus'
  );
end;
$function$;

-- Ventes mensuelles ---------------------------------------------------------------------------
-- Comme liveStatistics() de src/lib/operations.ts : les p_months mois civils COMPLETS qui
-- précèdent le mois en cours (heure locale p_tz), du plus ancien au plus récent, y compris les
-- mois sans vente (montant 0). Pour le mois en cours, utiliser shop_dashboard.
-- Catégories : classées par quantité vendue (puis montant), catégorie vide => 'Autre' ;
-- top 5 par mois (months[].topCategories) et sur toute la période (topCategories).
-- Résultat :
--   { timeZone, from, to,                     -- bornes locales [from, to)
--     months: [{ month: 'YYYY-MM', start, amount, saleCount, topCategories }],
--     topCategories: [{ category, quantity, amount }] }
create or replace function public.shop_monthly_sales(
  p_shop_id uuid,
  p_months integer default 3,
  p_tz text default 'Africa/Brazzaville',
  p_include_test boolean default false,
  p_at timestamptz default now()
)
returns jsonb
language plpgsql
stable
security invoker
set search_path to ''
as $function$
declare
  v_to date := pg_catalog.date_trunc('month', p_at at time zone p_tz)::date;
  v_from date;
  v_result jsonb;
begin
  if p_months is null or p_months < 1 or p_months > 120 then
    raise exception 'p_months must be between 1 and 120';
  end if;
  if not exists (select 1 from public.shops s where s.id = p_shop_id) then
    raise exception 'Shop not found' using errcode = '42501';
  end if;
  v_from := (v_to - pg_catalog.make_interval(months => p_months))::date;

  with months as (
    select g::date as month_start
    from pg_catalog.generate_series(v_from::timestamp, (v_to - interval '1 month')::timestamp,
                                    interval '1 month') as g
  ),
  period_sales as (
    select s.id, s.total_amount,
           pg_catalog.date_trunc('month', s.sold_at at time zone p_tz)::date as month_start
    from public.sales s
    where s.shop_id = p_shop_id
      and s.sold_at >= (v_from::timestamp at time zone p_tz)
      and s.sold_at < (v_to::timestamp at time zone p_tz)
      and (p_include_test or not s.is_test)
  ),
  per_month as (
    select ps.month_start, sum(ps.total_amount) as amount, count(*) as sale_count
    from period_sales ps
    group by ps.month_start
  ),
  per_category as (
    select ps.month_start,
           coalesce(nullif(pg_catalog.btrim(p.category), ''), 'Autre') as category,
           sum(i.quantity) as quantity,
           sum(i.quantity * i.sold_unit_price) as amount
    from period_sales ps
    join public.sale_items i on i.sale_id = ps.id
    join public.products p on p.id = i.product_id
    group by 1, 2
  ),
  month_rows as (
    select m.month_start,
           jsonb_build_object(
             'month', pg_catalog.to_char(m.month_start, 'YYYY-MM'),
             'start', m.month_start,
             'amount', coalesce(pm.amount, 0),
             'saleCount', coalesce(pm.sale_count, 0),
             'topCategories', coalesce((
               select jsonb_agg(jsonb_build_object('category', c.category, 'quantity', c.quantity,
                                                   'amount', c.amount)
                                order by c.quantity desc, c.amount desc, c.category)
               from (select * from per_category pc where pc.month_start = m.month_start
                     order by pc.quantity desc, pc.amount desc, pc.category limit 5) c
             ), '[]'::jsonb)) as row_json
    from months m
    left join per_month pm on pm.month_start = m.month_start
  )
  select jsonb_build_object(
    'timeZone', p_tz,
    'from', v_from,
    'to', v_to,
    'months', (select jsonb_agg(mr.row_json order by mr.month_start) from month_rows mr),
    'topCategories', coalesce((
      select jsonb_agg(jsonb_build_object('category', t.category, 'quantity', t.quantity,
                                          'amount', t.amount)
                       order by t.quantity desc, t.amount desc, t.category)
      from (select pc.category, sum(pc.quantity) as quantity, sum(pc.amount) as amount
            from per_category pc group by pc.category
            order by 2 desc, 3 desc, 1 limit 5) t
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$;

-- Rentabilité par arrivage --------------------------------------------------------------------
-- Comme arrivalProfitability() de src/lib/operations.ts (sans la liste des produits), une ligne
-- par arrivage, du plus récent au plus ancien :
--   cost              : global_cost, ou marchandise + transport + douane si global_cost = 0 ;
--   revenue           : somme quantité × prix réellement vendu des lignes de vente de ses
--                       produits ; sold_units : unités vendues ;
--   remaining_units   : unités encore en stock ; product_count : produits enregistrés ;
--   profit            : revenue - cost ;
--   recovery_percent  : arrondi(revenue / cost × 100), 0 si coût nul ;
--   remaining_to_recover : max(cost - revenue, 0), le « reste à récupérer » affiché pour les
--                       ballons (renseigné pour tous les types).
create or replace function public.arrival_profitability(
  p_shop_id uuid,
  p_include_test boolean default false
)
returns table (
  arrival_id uuid,
  code text,
  kind text,
  status text,
  origin_country text,
  supplier_name text,
  order_date date,
  received_date date,
  is_test boolean,
  cost numeric,
  revenue numeric,
  profit numeric,
  recovery_percent integer,
  remaining_to_recover numeric,
  sold_units bigint,
  remaining_units bigint,
  product_count bigint
)
language sql
stable
security invoker
set search_path to ''
as $function$
  with arrival_rows as (
    select a.*, coalesce(nullif(a.global_cost, 0),
                         a.merchandise_cost + a.transport_cost + a.customs_cost) as total_cost
    from public.arrivals a
    where a.shop_id = p_shop_id and (p_include_test or not a.is_test)
  ),
  stock as (
    select p.arrival_id, count(*) as product_count, sum(p.quantity_on_hand) as remaining
    from public.products p
    where p.shop_id = p_shop_id and p.arrival_id is not null
      and (p_include_test or not p.is_test)
    group by p.arrival_id
  ),
  sold as (
    select p.arrival_id, sum(i.quantity) as units, sum(i.quantity * i.sold_unit_price) as revenue
    from public.sales s
    join public.sale_items i on i.sale_id = s.id
    join public.products p on p.id = i.product_id
    where s.shop_id = p_shop_id and p.arrival_id is not null
      and (p_include_test or not s.is_test)
    group by p.arrival_id
  )
  select a.id, a.code, a.kind, a.status, a.origin_country, a.supplier_name, a.order_date,
         a.received_date, a.is_test,
         a.total_cost,
         coalesce(so.revenue, 0),
         coalesce(so.revenue, 0) - a.total_cost,
         case when a.total_cost > 0
              then pg_catalog.round(coalesce(so.revenue, 0) / a.total_cost * 100)::integer
              else 0 end,
         greatest(a.total_cost - coalesce(so.revenue, 0), 0),
         coalesce(so.units, 0)::bigint,
         coalesce(st.remaining, 0)::bigint,
         coalesce(st.product_count, 0)::bigint
  from arrival_rows a
  left join stock st on st.arrival_id = a.id
  left join sold so on so.arrival_id = a.id
  order by a.created_at desc, a.id
$function$;

-- Répartition du coût des arrivages -----------------------------------------------------------
-- MÉTHODE (coût de revient estimé d'un article)
--   Unités enregistrées d'un produit  u = quantity_on_hand + unités déjà vendues
--   (le stock ne fait que baisser, par record_sale : u est la quantité saisie à la création).
--   Coût d'un arrivage C = global_cost, ou marchandise + transport + douane si global_cost = 0.
--   * Commande fournisseur ('price_weighted') : C est réparti au prorata de la valeur au prix
--     initial. Coût unitaire du produit p = C × prix_initial(p) / Σ(u × prix_initial) sur les
--     produits de l'arrivage. Si tous les prix initiaux sont nuls : C / Σ u ('per_unit').
--   * Ballon ('per_piece') : C / nombre de pièces enregistrées (Σ u). Le contenu d'un ballon se
--     découvre au déballage : à chaque nouvelle pièce ajoutée, le coût par pièce baisse et le
--     coût des pièces DÉJÀ vendues est recalculé. Le bénéfice des mois passés peut donc évoluer
--     tant que le ballon n'est pas entièrement enregistré : c'est voulu, l'estimation converge
--     vers le coût réel à mesure que les pièces sont saisies.
--   * Produit sans arrivage ('none') : coût inconnu, unit_cost NULL. Ses ventes sont comptées
--     dans le chiffre d'affaires mais pas dans le coût des ventes ; elles sont signalées à part
--     (revenueWithoutCost dans shop_estimated_profit).
--   * Un arrivage sans aucun produit enregistré n'est réparti sur rien : son coût n'entre pas
--     dans le coût des ventes (signalé dans unallocatedArrivalCost).
--   Tous les produits d'un arrivage partagent son coût, quels que soient leurs drapeaux is_test
--   et statut (y compris archivés). Les coûts unitaires ne sont pas arrondis ; seuls les totaux
--   de shop_estimated_profit le sont (2 décimales).
-- Une ligne par produit de la boutique :
create or replace function public.arrival_cost_allocation(
  p_shop_id uuid,
  p_include_test boolean default false
)
returns table (
  product_id uuid,
  arrival_id uuid,
  arrival_kind text,
  method text,
  initial_sale_price numeric,
  registered_units bigint,
  sold_units bigint,
  remaining_units bigint,
  unit_cost numeric,
  sold_cost numeric,
  remaining_cost numeric
)
language sql
stable
security invoker
set search_path to ''
as $function$
  with product_units as (
    select p.id, p.arrival_id, p.is_test, p.initial_sale_price,
           p.quantity_on_hand::bigint as remaining,
           coalesce((select sum(i.quantity) from public.sale_items i where i.product_id = p.id),
                    0)::bigint as sold
    from public.products p
    where p.shop_id = p_shop_id
  ),
  arrival_basis as (
    select a.id, a.kind,
           coalesce(nullif(a.global_cost, 0),
                    a.merchandise_cost + a.transport_cost + a.customs_cost) as total_cost,
           sum(pu.remaining + pu.sold) as units,
           sum((pu.remaining + pu.sold) * pu.initial_sale_price) as weight
    from public.arrivals a
    join product_units pu on pu.arrival_id = a.id
    where a.shop_id = p_shop_id
    group by a.id
  ),
  allocated as (
    select pu.*, ab.kind,
           case
             when ab.id is null then 'none'
             when ab.kind = 'balloon' then 'per_piece'
             when ab.weight > 0 then 'price_weighted'
             else 'per_unit'
           end as method,
           case
             when ab.id is null then null
             when ab.units = 0 then 0
             when ab.kind = 'balloon' then ab.total_cost / ab.units
             when ab.weight > 0 then ab.total_cost * pu.initial_sale_price / ab.weight
             else ab.total_cost / ab.units
           end as unit_cost
    from product_units pu
    left join arrival_basis ab on ab.id = pu.arrival_id
  )
  select al.id, al.arrival_id, al.kind, al.method, al.initial_sale_price,
         al.remaining + al.sold, al.sold, al.remaining,
         al.unit_cost, al.unit_cost * al.sold, al.unit_cost * al.remaining
  from allocated al
  where p_include_test or not al.is_test
  order by al.arrival_id nulls last, al.id
$function$;

-- Bénéfice estimé réel --------------------------------------------------------------------------
-- Sur la période locale [p_from, p_to) (bornes NULL = sans limite), en heure p_tz :
--   revenue       : ventes (quantité × prix vendu) ;
--   costOfGoodsSold : Σ quantité vendue × coût unitaire de arrival_cost_allocation ;
--   grossProfit   : revenue - costOfGoodsSold ;
--   charges       : charges de la boutique dont expense_date est dans la période ;
--   netProfit     : grossProfit - charges ;
--   revenueWithoutCost : part des ventes de produits sans arrivage (coût inconnu, compté 0) ;
--   unsoldStockCost : coût réparti des unités encore en stock (aujourd'hui, hors période) ;
--   unallocatedArrivalCost : coût des arrivages sans aucun produit enregistré.
-- Contrairement à « ventes - coût des arrivages reçus » (shop_dashboard.profit), le coût d'un
-- arrivage n'est compté qu'au fur et à mesure de la vente de ses articles.
create or replace function public.shop_estimated_profit(
  p_shop_id uuid,
  p_from date default null,
  p_to date default null,
  p_tz text default 'Africa/Brazzaville',
  p_include_test boolean default false
)
returns jsonb
language plpgsql
stable
security invoker
set search_path to ''
as $function$
declare
  v_from timestamptz := p_from::timestamp at time zone p_tz;
  v_to timestamptz := p_to::timestamp at time zone p_tz;
  v_revenue numeric;
  v_cogs numeric;
  v_revenue_without_cost numeric;
  v_charges numeric;
  v_unsold numeric;
  v_unallocated numeric;
begin
  if not exists (select 1 from public.shops s where s.id = p_shop_id) then
    raise exception 'Shop not found' using errcode = '42501';
  end if;

  select coalesce(sum(i.quantity * i.sold_unit_price), 0),
         coalesce(sum(i.quantity * al.unit_cost), 0),
         coalesce(sum(i.quantity * i.sold_unit_price) filter (where al.unit_cost is null), 0)
    into v_revenue, v_cogs, v_revenue_without_cost
  from public.sales s
  join public.sale_items i on i.sale_id = s.id
  join public.arrival_cost_allocation(p_shop_id, true) al on al.product_id = i.product_id
  where s.shop_id = p_shop_id
    and (v_from is null or s.sold_at >= v_from)
    and (v_to is null or s.sold_at < v_to)
    and (p_include_test or not s.is_test);

  select coalesce(sum(e.amount), 0) into v_charges
  from public.shop_expenses e
  where e.shop_id = p_shop_id
    and (p_from is null or e.expense_date >= p_from)
    and (p_to is null or e.expense_date < p_to)
    and (p_include_test or not e.is_test);

  select coalesce(sum(al.remaining_cost), 0) into v_unsold
  from public.arrival_cost_allocation(p_shop_id, p_include_test) al;

  select coalesce(sum(coalesce(nullif(a.global_cost, 0),
                               a.merchandise_cost + a.transport_cost + a.customs_cost)), 0)
    into v_unallocated
  from public.arrivals a
  where a.shop_id = p_shop_id
    and (p_include_test or not a.is_test)
    and not exists (select 1 from public.products p where p.arrival_id = a.id);

  return jsonb_build_object(
    'timeZone', p_tz,
    'from', p_from,
    'to', p_to,
    'revenue', pg_catalog.round(v_revenue, 2),
    'costOfGoodsSold', pg_catalog.round(v_cogs, 2),
    'grossProfit', pg_catalog.round(v_revenue - v_cogs, 2),
    'charges', pg_catalog.round(v_charges, 2),
    'netProfit', pg_catalog.round(v_revenue - v_cogs - v_charges, 2),
    'revenueWithoutCost', pg_catalog.round(v_revenue_without_cost, 2),
    'unsoldStockCost', pg_catalog.round(v_unsold, 2),
    'unallocatedArrivalCost', pg_catalog.round(v_unallocated, 2)
  );
end;
$function$;

-- Droits : utilisateurs connectés uniquement ---------------------------------------------------
revoke execute on function public.shop_dashboard(uuid, text, boolean, timestamptz)
  from public, anon;
revoke execute on function public.shop_monthly_sales(uuid, integer, text, boolean, timestamptz)
  from public, anon;
revoke execute on function public.arrival_profitability(uuid, boolean) from public, anon;
revoke execute on function public.arrival_cost_allocation(uuid, boolean) from public, anon;
revoke execute on function public.shop_estimated_profit(uuid, date, date, text, boolean)
  from public, anon;
grant execute on function public.shop_dashboard(uuid, text, boolean, timestamptz) to authenticated;
grant execute on function public.shop_monthly_sales(uuid, integer, text, boolean, timestamptz)
  to authenticated;
grant execute on function public.arrival_profitability(uuid, boolean) to authenticated;
grant execute on function public.arrival_cost_allocation(uuid, boolean) to authenticated;
grant execute on function public.shop_estimated_profit(uuid, date, date, text, boolean)
  to authenticated;
