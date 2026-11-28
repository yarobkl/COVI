-- COVI Salon professionnel — tableau de bord, finances et statistiques (lots 5 et 6).
--
-- Définitions (affichées telles quelles dans l'application) :
--   * CA réalisé = montants nets (après remise) des lignes payées dans la période, hors lignes
--     remboursées. Une prestation non payée n'est JAMAIS du CA : elle reste « en attente ».
--   * Encaissements nets = paiements reçus dans la période − remboursements versés dans la période.
--   * Coûts directs = consommables réellement sortis du stock (au coût moyen) ou, à défaut de
--     consommables paramétrés, le coût direct estimé de la prestation ; coût d'achat des produits vendus.
--   * Commissions dues = commissions figées au paiement, hors lignes remboursées. Les commissions
--     sont comptées UNE fois : les charges saisies dont la catégorie contient « commission » sont
--     exclues des autres charges (elles sont affichées à part pour contrôle).
--   * Résultat de pilotage estimé = CA − coûts directs − commissions − autres charges saisies.
--     Ce n'est ni un résultat comptable ni un bénéfice fiscal.
--   * Flux de trésorerie estimé = encaissements nets − commissions versées − autres charges saisies
--     − achats de produits enregistrés.

create function public.salon_report(p_shop uuid, p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'reports');
  v_tz text := public.salon_tz(p_shop);
  v_from timestamptz;
  v_to timestamptz;
  v_services bigint; v_products bigint; v_service_cost bigint; v_product_cost bigint;
  v_commissions bigint; v_charges numeric; v_commission_charges numeric;
  v_payments bigint; v_refunds bigint; v_payouts bigint; v_purchases numeric;
  v_tickets integer; v_pending bigint; v_pending_count integer;
begin
  if p_from is null or p_to is null or p_to < p_from or p_to > p_from + 400 then
    raise exception 'Invalid period' using errcode = '22023';
  end if;
  v_from := p_from::timestamp at time zone v_tz;
  v_to := (p_to + 1)::timestamp at time zone v_tz;

  select coalesce(sum(l.net_xaf) filter (where l.kind = 'service'), 0),
         coalesce(sum(l.net_xaf) filter (where l.kind = 'product'), 0),
         coalesce(sum(l.direct_cost_xaf) filter (where l.kind = 'service'), 0),
         coalesce(sum(l.direct_cost_xaf) filter (where l.kind = 'product'), 0),
         coalesce(sum(l.commission_xaf), 0)
  into v_services, v_products, v_service_cost, v_product_cost, v_commissions
  from public.salon_ticket_lines l join public.salon_tickets t on t.id = l.ticket_id
  where t.shop_id = p_shop and t.paid_at >= v_from and t.paid_at < v_to and l.refunded_at is null;

  select count(*) into v_tickets from public.salon_tickets t
  where t.shop_id = p_shop and t.paid_at >= v_from and t.paid_at < v_to
    and exists (select 1 from public.salon_ticket_lines l where l.ticket_id = t.id and l.refunded_at is null);

  select coalesce(sum(amount_xaf) filter (where kind = 'payment'), 0),
         coalesce(sum(amount_xaf) filter (where kind = 'refund'), 0)
  into v_payments, v_refunds
  from public.salon_payments where shop_id = p_shop and recorded_at >= v_from and recorded_at < v_to;

  select coalesce(sum(amount_xaf), 0) into v_payouts from public.salon_commission_payouts
  where shop_id = p_shop and recorded_at >= v_from and recorded_at < v_to;

  select coalesce(sum(amount) filter (where category !~* 'commission'), 0),
         coalesce(sum(amount) filter (where category ~* 'commission'), 0)
  into v_charges, v_commission_charges
  from public.shop_expenses
  where shop_id = p_shop and not is_test and expense_date between p_from and p_to;

  select coalesce(sum(delta * unit_cost_xaf), 0) into v_purchases from public.salon_supply_movements
  where shop_id = p_shop and reason = 'purchase' and created_at >= v_from and created_at < v_to;

  select coalesce(sum(total_xaf), 0), count(*) into v_pending, v_pending_count
  from public.salon_tickets where shop_id = p_shop and status = 'open' and total_xaf > 0;

  return jsonb_build_object(
    'period', jsonb_build_object('from', p_from, 'to', p_to, 'time_zone', v_tz),
    'finance', jsonb_build_object(
      'services_revenue_xaf', v_services,
      'products_revenue_xaf', v_products,
      'revenue_xaf', v_services + v_products,
      'service_direct_costs_xaf', v_service_cost,
      'product_costs_xaf', v_product_cost,
      'gross_margin_xaf', v_services + v_products - v_service_cost - v_product_cost,
      'commissions_due_xaf', v_commissions,
      'other_charges_xaf', round(v_charges)::bigint,
      'commission_category_charges_xaf', round(v_commission_charges)::bigint,
      'estimated_result_xaf', v_services + v_products - v_service_cost - v_product_cost
                              - v_commissions - round(v_charges)::bigint,
      'payments_xaf', v_payments,
      'refunds_xaf', v_refunds,
      'net_collected_xaf', v_payments - v_refunds,
      'commissions_paid_xaf', v_payouts,
      'purchases_xaf', round(v_purchases)::bigint,
      'estimated_cash_flow_xaf', v_payments - v_refunds - v_payouts - round(v_charges)::bigint
                                 - round(v_purchases)::bigint,
      'pending_checkout_xaf', v_pending,
      'pending_checkout_count', v_pending_count,
      'paid_tickets', v_tickets,
      'average_ticket_xaf', case when v_tickets > 0 then round((v_services + v_products)::numeric / v_tickets)::bigint else 0 end),
    'payment_methods', coalesce((select jsonb_agg(jsonb_build_object('method', method,
        'payments_xaf', pay, 'refunds_xaf', ref, 'net_xaf', pay - ref) order by method)
      from (select method, coalesce(sum(amount_xaf) filter (where kind = 'payment'), 0) as pay,
                   coalesce(sum(amount_xaf) filter (where kind = 'refund'), 0) as ref
            from public.salon_payments where shop_id = p_shop and recorded_at >= v_from and recorded_at < v_to
            group by method) m), '[]'::jsonb),
    'activity', (select jsonb_build_object(
        'appointments', count(*),
        'completed', count(*) filter (where status = 'completed'),
        'cancelled', count(*) filter (where status = 'cancelled'),
        'no_show', count(*) filter (where status = 'no_show'),
        'upcoming', count(*) filter (where status in ('pending', 'confirmed', 'arrived', 'in_progress')),
        'walk_ins', count(*) filter (where source = 'walk_in'),
        'honoured_rate', case when count(*) filter (where status in ('completed', 'cancelled', 'no_show')) > 0
          then round(100.0 * count(*) filter (where status = 'completed')
               / count(*) filter (where status in ('completed', 'cancelled', 'no_show')), 1) end,
        'cancellation_rate', case when count(*) filter (where status in ('completed', 'cancelled', 'no_show')) > 0
          then round(100.0 * count(*) filter (where status in ('cancelled', 'no_show'))
               / count(*) filter (where status in ('completed', 'cancelled', 'no_show')), 1) end)
      from public.salon_appointments
      where shop_id = p_shop and starts_at >= v_from and starts_at < v_to),
    'clients', (select jsonb_build_object(
        'served', count(distinct coalesce(t.client_id::text, 'n:' || lower(coalesce(t.client_name, t.id::text)))),
        'identified', count(distinct t.client_id),
        'returning', (select count(*) from (select t2.client_id from public.salon_tickets t2
            where t2.shop_id = p_shop and t2.client_id is not null and t2.paid_at >= v_from and t2.paid_at < v_to
            group by t2.client_id having count(*) >= 2) r),
        'new_clients', (select count(*) from public.salon_clients c
            where c.shop_id = p_shop and c.created_at >= v_from and c.created_at < v_to))
      from public.salon_tickets t
      where t.shop_id = p_shop and t.paid_at >= v_from and t.paid_at < v_to),
    'services', coalesce((select jsonb_agg(row_to_json(s)::jsonb order by s.count desc, s.revenue_xaf desc) from (
        select l.service_id, max(l.label) as name, sum(l.quantity)::numeric as count,
               sum(l.net_xaf) as revenue_xaf,
               sum(l.net_xaf - l.direct_cost_xaf - l.commission_xaf) as margin_xaf
        from public.salon_ticket_lines l join public.salon_tickets t on t.id = l.ticket_id
        where t.shop_id = p_shop and l.kind = 'service' and l.refunded_at is null
          and t.paid_at >= v_from and t.paid_at < v_to
        group by l.service_id) s), '[]'::jsonb),
    'staff', coalesce((select jsonb_agg(row_to_json(x)::jsonb order by x.revenue_xaf desc) from (
        select e.id as employee_id, e.full_name,
               coalesce(sum(l.quantity) filter (where l.kind = 'service'), 0)::numeric as services,
               coalesce(sum(l.net_xaf), 0) as revenue_xaf,
               coalesce(sum(l.commission_xaf), 0) as commission_xaf
        from public.employees e
        join public.salon_staff_profiles p on p.employee_id = e.id
        left join (public.salon_ticket_lines l join public.salon_tickets t on t.id = l.ticket_id
                   and t.paid_at >= v_from and t.paid_at < v_to)
          on l.employee_id = e.id and l.refunded_at is null
        where e.shop_id = p_shop
        group by e.id, e.full_name) x), '[]'::jsonb),
    'weekdays', coalesce((select jsonb_agg(jsonb_build_object('weekday', d, 'appointments', n, 'revenue_xaf', r) order by d)
      from (select extract(isodow from (a.starts_at at time zone v_tz))::int as d,
                   count(*) as n,
                   coalesce(sum((select sum(l.net_xaf) from public.salon_tickets t
                     join public.salon_ticket_lines l on l.ticket_id = t.id and l.refunded_at is null
                     where t.appointment_id = a.id and t.paid_at is not null)), 0) as r
            from public.salon_appointments a
            where a.shop_id = p_shop and a.status = 'completed' and a.starts_at >= v_from and a.starts_at < v_to
            group by 1) w), '[]'::jsonb),
    'daily', coalesce((select jsonb_agg(jsonb_build_object('day', day, 'revenue_xaf', revenue) order by day)
      from (select (t.paid_at at time zone v_tz)::date as day, sum(l.net_xaf) as revenue
            from public.salon_tickets t join public.salon_ticket_lines l on l.ticket_id = t.id and l.refunded_at is null
            where t.shop_id = p_shop and t.paid_at >= v_from and t.paid_at < v_to
            group by 1) d), '[]'::jsonb),
    'consumables', coalesce((select jsonb_agg(jsonb_build_object('supply_id', supply_id, 'name', name,
        'unit', unit, 'quantity', qty, 'cost_xaf', cost) order by cost desc)
      from (select m.supply_id, s.name, s.unit, sum(-m.delta) as qty, round(sum(-m.delta * m.unit_cost_xaf)) as cost
            from public.salon_supply_movements m join public.salon_supplies s on s.id = m.supply_id
            where m.shop_id = p_shop and m.reason = 'consumption' and m.created_at >= v_from and m.created_at < v_to
            group by m.supply_id, s.name, s.unit) c), '[]'::jsonb)
  );
end;
$$;

-- Tableau de bord du jour : chiffres + alertes. Propriétaire et responsable.
create function public.salon_dashboard(p_shop uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'reports');
  v_tz text := public.salon_tz(p_shop);
  v_today date := (now() at time zone v_tz)::date;
  v_day smallint := extract(isodow from (now() at time zone v_tz))::smallint;
  v_end_of_day timestamptz := (v_today + 1)::timestamp at time zone v_tz;
begin
  return jsonb_build_object(
    'today', v_today,
    'time_zone', v_tz,
    'setup', jsonb_build_object(
      'configured', exists (select 1 from public.salon_settings where shop_id = p_shop),
      'services', (select count(*) from public.salon_services where shop_id = p_shop and active),
      'staff', (select count(*) from public.salon_staff_profiles p join public.employees e on e.id = p.employee_id
                where p.shop_id = p_shop and e.active),
      'appointments', (select count(*) from public.salon_appointments where shop_id = p_shop),
      'tickets', (select count(*) from public.salon_tickets where shop_id = p_shop and paid_at is not null)),
    'day', public.salon_report(p_shop, v_today, v_today),
    'month', public.salon_report(p_shop, date_trunc('month', v_today)::date, v_today) -> 'finance',
    'alerts', jsonb_build_object(
      'upcoming', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'client_name', a.client_name,
          'starts_at', a.starts_at, 'employee_name', e.full_name, 'status', a.status) order by a.starts_at)
        from public.salon_appointments a join public.employees e on e.id = a.employee_id
        where a.shop_id = p_shop and a.status in ('pending', 'confirmed')
          and a.starts_at >= now() and a.starts_at < now() + interval '3 hours'), '[]'::jsonb),
      'late', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'client_name', a.client_name,
          'starts_at', a.starts_at, 'employee_name', e.full_name) order by a.starts_at)
        from public.salon_appointments a join public.employees e on e.id = a.employee_id
        where a.shop_id = p_shop and a.status in ('pending', 'confirmed')
          and a.starts_at < now() - interval '10 minutes'
          and a.starts_at >= v_today::timestamp at time zone v_tz), '[]'::jsonb),
      'low_stock', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name,
          'quantity_on_hand', s.quantity_on_hand, 'unit', s.unit, 'alert_threshold', s.alert_threshold)
          order by s.quantity_on_hand)
        from public.salon_supplies s
        where s.shop_id = p_shop and s.active and s.quantity_on_hand <= s.alert_threshold), '[]'::jsonb),
      'stock_shortfalls', (select count(*) from public.salon_events ev
        where ev.shop_id = p_shop and ev.event_type = 'stock_shortfall' and ev.at > now() - interval '7 days'),
      'pending_requests', (select count(*) from public.salon_booking_requests r
        where r.shop_id = p_shop and r.status = 'pending' and r.requested_at > now()),
      'open_tickets', (select count(*) from public.salon_tickets t where t.shop_id = p_shop and t.status = 'open')),
    -- Collaborateurs présents aujourd'hui et minutes encore libres jusqu'à la fin de leur journée.
    'staff_today', coalesce((select jsonb_agg(jsonb_build_object('employee_id', e.id,
        'full_name', e.full_name, 'agenda_color', p.agenda_color,
        'starts_at', to_char(w.ws, 'HH24:MI'), 'ends_at', to_char(w.we, 'HH24:MI'),
        'appointments', (select count(*) from public.salon_appointments a where a.employee_id = e.id
            and a.status in ('pending', 'confirmed', 'arrived', 'in_progress', 'completed')
            and a.starts_at >= v_today::timestamp at time zone v_tz and a.starts_at < v_end_of_day),
        'free_minutes_left', greatest(0, round(extract(epoch from (
            greatest((v_today + w.we) at time zone v_tz, now())
            - greatest((v_today + w.ws) at time zone v_tz, now()))) / 60)
          - coalesce((select sum(extract(epoch from (a.ends_at - greatest(a.starts_at, now()))) / 60)
              from public.salon_appointments a where a.employee_id = e.id
              and a.status in ('pending', 'confirmed', 'arrived', 'in_progress')
              and a.ends_at > now() and a.starts_at < (v_today + w.we) at time zone v_tz), 0))::int)
        order by e.full_name)
      from public.employees e
      join public.salon_staff_profiles p on p.employee_id = e.id
      cross join lateral (select
          coalesce((select h.starts_at from public.salon_staff_hours h where h.employee_id = e.id and h.weekday = v_day),
                   (select o.opens_at from public.salon_opening_hours o where o.shop_id = p_shop and o.weekday = v_day)) as ws,
          coalesce((select h.ends_at from public.salon_staff_hours h where h.employee_id = e.id and h.weekday = v_day),
                   (select o.closes_at from public.salon_opening_hours o where o.shop_id = p_shop and o.weekday = v_day)) as we) w
      where e.shop_id = p_shop and e.active and w.ws is not null
        and (not exists (select 1 from public.salon_staff_hours h where h.employee_id = e.id)
             or exists (select 1 from public.salon_staff_hours h where h.employee_id = e.id and h.weekday = v_day))
        and not exists (select 1 from public.salon_staff_absences ab where ab.employee_id = e.id and ab.day = v_today)), '[]'::jsonb)
  );
end;
$$;

-- Faits vérifiés transmis à l'assistant (lecture seule, aucun téléphone ni e-mail de client).
create function public.salon_ai_facts(p_shop uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'reports');
  v_tz text := public.salon_tz(p_shop);
  v_today date := (now() at time zone v_tz)::date;
  v_month jsonb := public.salon_report(p_shop, date_trunc('month', v_today)::date, v_today);
  v_day jsonb := public.salon_report(p_shop, v_today, v_today);
begin
  return jsonb_build_object(
    'sector', 'salon',
    'date', v_today,
    'time_zone', v_tz,
    'today', jsonb_build_object('finance', v_day -> 'finance', 'activity', v_day -> 'activity'),
    'month_to_date', jsonb_build_object('finance', v_month -> 'finance', 'activity', v_month -> 'activity',
      'top_services', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select jsonb_build_object('name', s ->> 'name', 'count', s -> 'count',
            'revenue_xaf', s -> 'revenue_xaf', 'margin_xaf', s -> 'margin_xaf') as x
          from jsonb_array_elements(v_month -> 'services') s limit 8) t),
      'staff', (select coalesce(jsonb_agg(jsonb_build_object('name', s ->> 'full_name',
          'services', s -> 'services', 'revenue_xaf', s -> 'revenue_xaf')), '[]'::jsonb)
        from jsonb_array_elements(v_month -> 'staff') s),
      'weekdays', v_month -> 'weekdays'),
    'tomorrow_appointments', coalesce((select jsonb_agg(jsonb_build_object(
        'time', to_char(a.starts_at at time zone v_tz, 'HH24:MI'), 'employee', e.full_name,
        'services', (select string_agg(s.name, ', ' order by s.position)
                     from public.salon_appointment_services s where s.appointment_id = a.id),
        'status', a.status) order by a.starts_at)
      from public.salon_appointments a join public.employees e on e.id = a.employee_id
      where a.shop_id = p_shop and a.status in ('pending', 'confirmed')
        and a.starts_at >= (v_today + 1)::timestamp at time zone v_tz
        and a.starts_at < (v_today + 2)::timestamp at time zone v_tz), '[]'::jsonb),
    'low_stock', coalesce((select jsonb_agg(jsonb_build_object('name', s.name,
        'quantity', s.quantity_on_hand, 'unit', s.unit, 'alert_threshold', s.alert_threshold))
      from public.salon_supplies s
      where s.shop_id = p_shop and s.active and s.quantity_on_hand <= s.alert_threshold), '[]'::jsonb),
    'definitions', 'revenue_xaf = CA réalisé payé (hors remboursements). estimated_result_xaf = CA − coûts directs − commissions − autres charges saisies : résultat de pilotage estimé, ni comptable ni fiscal. pending_checkout_xaf n''est pas encaissé.'
  );
end;
$$;

revoke all on function public.salon_report(uuid, date, date), public.salon_dashboard(uuid),
  public.salon_ai_facts(uuid) from public, anon;
grant execute on function public.salon_report(uuid, date, date), public.salon_dashboard(uuid),
  public.salon_ai_facts(uuid) to authenticated;
