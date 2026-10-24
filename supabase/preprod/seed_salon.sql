-- Données fictives du Salon pour la préproduction (aucune donnée réelle). Nécessite les migrations Salon pro (PR #64).
insert into auth.users(id) values ('00000000-0000-0000-0000-00000000f001'), ('00000000-0000-0000-0000-00000000f002') on conflict do nothing;
insert into public.shops(id, owner_id, name, city, country, neighborhood, address_line, currency, business_kind)
values ('10000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000f001', 'Salon Beauté Divine', 'Brazzaville',
        'République du Congo', 'Poto-Poto', 'Avenue de la Paix, face à la pharmacie', 'XAF', 'salon')
on conflict do nothing;
do $$
declare
  s uuid := '10000000-0000-0000-0000-00000000f001';
  tz text := 'Africa/Brazzaville';
  today date := (now() at time zone 'Africa/Brazzaville')::date;
  paul uuid; awa uuid; junior uuid; coupe uuid; barbe uuid; tresses uuid; color uuid; brushing uuid; locks uuid;
  creme uuid; huile uuid; shamp uuid; c1 uuid; c2 uuid; c3 uuid; tk uuid; i int;
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000f001', true);
  perform public.salon_settings_save(s, 'mixed', 'Mme Nadège Mabiala', '+242 06 444 55 66', 4, tz,
    (select jsonb_agg(jsonb_build_object('weekday', d, 'opens_at', '08:00',
       'closes_at', '20:00')) from generate_series(1, 7) d));
  paul := public.salon_staff_save(s, null, 'Paul Mabiala', 'Coiffeur', '061111111', 'percent', 25, 0, '#17408b', true, null);
  awa := public.salon_staff_save(s, null, 'Awa Nkounkou', 'Coloriste', '062222222', 'percent', 20, 0, '#0a7a43', true, null);
  junior := public.salon_staff_save(s, null, 'Junior Mbemba', 'Barbier', null, 'fixed', 0, 1000, '#b45309', true, null);
  coupe := public.salon_service_save(s, null, 'Coupe homme', 'Coupe', null, 3000, 30, 0, true, array[paul, junior]);
  barbe := public.salon_service_save(s, null, 'Barbe', 'Coupe', null, 2000, 20, 0, true, array[junior]);
  tresses := public.salon_service_save(s, null, 'Tresses', 'Coiffure', 'Tresses longues, mèches fournies', 25000, 180, 4000, true, array[paul, awa]);
  color := public.salon_service_save(s, null, 'Coloration', 'Couleur', null, 15000, 90, 0, true, array[awa]);
  brushing := public.salon_service_save(s, null, 'Brushing', 'Coiffure', null, 5000, 45, 0, true, null);
  locks := public.salon_service_save(s, null, 'Locks', 'Coiffure', null, 20000, 150, 0, true, array[paul]);
  creme := public.salon_supply_save(s, null, 'Crème colorante', 'Couleur', 'ml', 'consumption', 200, 0, null, true);
  huile := public.salon_supply_save(s, null, 'Huile capillaire', 'Soin', 'piece', 'both', 2, 0, 6000, true);
  shamp := public.salon_supply_save(s, null, 'Shampoing professionnel', 'Soin', 'ml', 'consumption', 500, 0, null, true);
  perform public.salon_supply_adjust(s, creme, 'purchase', 1000, 60, null, 'seed-creme-0001');
  perform public.salon_supply_adjust(s, huile, 'purchase', 3, 3500, null, 'seed-huile-0001');
  perform public.salon_supply_adjust(s, shamp, 'purchase', 400, 8, null, 'seed-shamp-0001');
  perform public.salon_service_consumables_set(s, color, jsonb_build_array(jsonb_build_object('supply_id', creme, 'quantity', 80)));
  perform public.salon_service_consumables_set(s, brushing, jsonb_build_array(jsonb_build_object('supply_id', shamp, 'quantity', 30)));
  c1 := (public.salon_client_save(s, null, 'Mireille', 'Kounkou', '+242 06 555 12 34', null, 'Tresses fines, pas de mèches synthétiques', true, true, false) ->> 'id')::uuid;
  c2 := (public.salon_client_save(s, null, 'Prisca', 'Ngoma', '066543210', null, null, false, true, false) ->> 'id')::uuid;
  c3 := (public.salon_client_save(s, null, 'Jean-Baptiste', 'Moukoko', '067778899', null, null, false, false, false) ->> 'id')::uuid;
  -- Rendez-vous de demain (par la fonction, contrôles compris).
  perform public.salon_appointment_save(s, null, c1, null, null, awa, ((today + 1) + time '09:00') at time zone tz, array[tresses], null, 'Apporte ses mèches');
  perform public.salon_appointment_save(s, null, c2, null, null, awa, ((today + 1) + time '13:00') at time zone tz, array[color, brushing], null, null);
  perform public.salon_appointment_save(s, null, c3, null, null, junior, ((today + 1) + time '10:00') at time zone tz, array[coupe, barbe], null, null);
  perform public.salon_appointment_save(s, null, null, 'Béatrice', '061230000', paul, ((today + 1) + time '15:00') at time zone tz, array[locks], null, null);
  perform public.salon_appointment_save(s, null, null, 'Christelle', null, paul, ((today + 3) + time '10:30') at time zone tz, array[brushing], null, null);
  -- Notes payées (passages en caisse) puis antidatées sur la semaine pour les rapports.
  for i in 1..6 loop
    tk := (public.salon_ticket_open(s, null, case when i % 3 = 0 then c3 end, case when i % 3 = 0 then null else 'Client ' || i end, 'seed-tk-' || lpad(i::text, 6, '0')) ->> 'id')::uuid;
    perform public.salon_ticket_add_line(s, tk, 'service', case i % 3 when 0 then coupe when 1 then tresses else color end,
      case i % 3 when 0 then junior when 1 then paul else awa end, 1, null);
    if i = 2 then perform public.salon_ticket_add_line(s, tk, 'product', huile, null, 1, null); end if;
    perform public.salon_ticket_pay(s, tk,
      jsonb_build_array(jsonb_build_object('method', case when i % 2 = 0 then 'mobile_money' else 'cash' end,
        'amount_xaf', (select total_xaf from public.salon_tickets where id = tk))), 'seed-pay-' || lpad(i::text, 6, '0'));
    if i > 2 then
      update public.salon_tickets set paid_at = paid_at - (i - 2) * interval '1 day' where id = tk;
      update public.salon_payments set recorded_at = recorded_at - (i - 2) * interval '1 day' where ticket_id = tk;
    end if;
  end loop;
  -- Une note ouverte (en attente) et une demande à planifier.
  tk := (public.salon_ticket_open(s, null, null, 'Client de passage', 'seed-open-000001') ->> 'id')::uuid;
  perform public.salon_ticket_add_line(s, tk, 'service', brushing, paul, 1, null);
  insert into public.shop_expenses(shop_id, category, label, amount, expense_date) values
    (s, 'Loyer', 'Loyer du mois', 80000, today), (s, 'Électricité', 'Facture SNE', 15000, today);
end $$;
-- Rendez-vous d'aujourd'hui (insérés directement pour le banc : l'heure courante peut être hors ouverture).
insert into public.salon_appointments(shop_id, client_id, client_name, client_phone, employee_id, starts_at, ends_at, status, estimated_price_xaf)
select '10000000-0000-0000-0000-00000000f001', null, x.n, null, e.id,
  (((now() at time zone 'Africa/Brazzaville')::date + x.t) at time zone 'Africa/Brazzaville'),
  (((now() at time zone 'Africa/Brazzaville')::date + x.t + x.d) at time zone 'Africa/Brazzaville'), x.st, x.p
from (values ('Grâce', 'Paul Mabiala', time '09:00', interval '45 minutes', 'completed', 5000),
             ('Ornella', 'Awa Nkounkou', time '10:00', interval '90 minutes', 'confirmed', 15000),
             ('Didier', 'Junior Mbemba', time '11:00', interval '30 minutes', 'arrived', 3000),
             ('Sandrine', 'Paul Mabiala', time '14:00', interval '3 hours', 'confirmed', 25000),
             ('Rufin', 'Junior Mbemba', time '16:00', interval '20 minutes', 'cancelled', 2000)) x(n, emp, t, d, st, p)
join public.employees e on e.full_name = x.emp and e.shop_id = '10000000-0000-0000-0000-00000000f001';
insert into public.salon_appointment_services(shop_id, appointment_id, position, service_id, name, price_xaf, duration_minutes)
select a.shop_id, a.id, 1, sv.id, sv.name, sv.price_xaf, sv.duration_minutes
from public.salon_appointments a join public.salon_services sv on sv.shop_id = a.shop_id and sv.price_xaf = a.estimated_price_xaf
where a.shop_id = '10000000-0000-0000-0000-00000000f001' and not exists (select 1 from public.salon_appointment_services x where x.appointment_id = a.id);
-- Comptes : Paul (coiffeur) relié à sa fiche.
insert into public.salon_staff_members(shop_id, user_id, employee_id, display_name, role, created_by)
select '10000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000f002', e.id, 'Paul', 'stylist', '00000000-0000-0000-0000-00000000f001'
from public.employees e where e.full_name = 'Paul Mabiala' on conflict do nothing;
select 'seed ok';
