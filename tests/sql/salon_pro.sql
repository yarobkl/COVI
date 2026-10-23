-- COVI Salon professionnel : droits, agenda, caisse, stock, commissions et finances.
-- Base jetable, tout est annulé (rollback) à la fin.
\set ON_ERROR_STOP 1
begin;

-- Utilisateurs : 2 propriétaires de salon, 1 propriétaire de boutique, responsable, coiffeur,
-- caissière, inconnu.
insert into auth.users(id) values
 ('00000000-0000-0000-0000-00000000a001'), -- propriétaire salon A
 ('00000000-0000-0000-0000-00000000a002'), -- propriétaire salon B
 ('00000000-0000-0000-0000-00000000a003'), -- propriétaire boutique
 ('00000000-0000-0000-0000-00000000a004'), -- responsable A
 ('00000000-0000-0000-0000-00000000a005'), -- coiffeur A (Paul)
 ('00000000-0000-0000-0000-00000000a006'), -- caissière A
 ('00000000-0000-0000-0000-00000000a007'); -- inconnu
insert into public.shops(id, owner_id, name, business_kind) values
 ('10000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000a001', 'Salon A', 'salon'),
 ('10000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-00000000a002', 'Salon B', 'salon'),
 ('10000000-0000-0000-0000-00000000a003', '00000000-0000-0000-0000-00000000a003', 'Boutique', 'retail');

create function pg_temp.as_user(p uuid) returns void language sql as
$$ select set_config('request.jwt.claim.sub', p::text, true) $$;
create function pg_temp.expect_error(p_sql text, p_state text, p_label text) returns void
language plpgsql as $$
declare v_state text; v_msg text;
begin
  execute p_sql;
  raise exception 'FAIL %: aurait dû échouer', p_label;
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  if v_msg like 'FAIL %' then raise; end if;
  if p_state is not null and v_state <> p_state then
    raise exception 'FAIL %: SQLSTATE % (%) au lieu de %', p_label, v_state, v_msg, p_state;
  end if;
end $$;
create function pg_temp.check(p_ok boolean, p_label text) returns void language plpgsql as
$$ begin if p_ok is not true then raise exception 'FAIL %', p_label; end if; end $$;
grant execute on all functions in schema pg_temp to authenticated;

create temporary table ids (k text primary key, v uuid) on commit drop;
grant all on ids to authenticated;

-- Les fonctions du module sont SECURITY DEFINER : seul auth.uid() compte (simulé ci-dessous).
-- Les lectures de contrôle se font en superutilisateur ; l'accès direct est testé à part (§ 6 bis).
do $t$
declare
  a uuid := '10000000-0000-0000-0000-00000000a001';
  b uuid := '10000000-0000-0000-0000-00000000a002';
  shop uuid := '10000000-0000-0000-0000-00000000a003';
  owner_a uuid := '00000000-0000-0000-0000-00000000a001';
  owner_b uuid := '00000000-0000-0000-0000-00000000a002';
  owner_shop uuid := '00000000-0000-0000-0000-00000000a003';
  manager uuid := '00000000-0000-0000-0000-00000000a004';
  stylist uuid := '00000000-0000-0000-0000-00000000a005';
  cashier uuid := '00000000-0000-0000-0000-00000000a006';
  stranger uuid := '00000000-0000-0000-0000-00000000a007';
  tz text := 'Africa/Brazzaville';
  tomorrow date := (now() at time zone 'Africa/Brazzaville')::date + 1;
  paul uuid; awa uuid; tresses uuid; coloration uuid; coupe uuid;
  creme uuid; huile uuid; client1 uuid; r jsonb; appt uuid; appt2 uuid; tk uuid; code text;
  v numeric; line_huile uuid;
begin
  -- 1. Réglages : propriétaire seulement ------------------------------------------------------
  perform pg_temp.as_user(owner_a);
  r := public.salon_settings_save(a, 'mixed', 'Mme A', '+242 06 123 45 67', 3, tz,
    (select jsonb_agg(jsonb_build_object('weekday', d, 'opens_at', '08:00', 'closes_at', '20:00'))
     from generate_series(1, 7) d));
  perform pg_temp.check(jsonb_array_length(r -> 'opening_hours') = 7, 'horaires enregistrés');
  perform pg_temp.check(r -> 'settings' ->> 'business_phone' = '+242061234567', 'téléphone normalisé');

  -- 2. Collaborateurs et commissions ----------------------------------------------------------
  paul := public.salon_staff_save(a, null, 'Paul Mabiala', 'Coiffeur', '061111111', 'percent', 25, 0, '#17408b', true, null);
  awa := public.salon_staff_save(a, null, 'Awa Nkounkou', 'Coloriste', null, 'percent', 20, 0, '#0a7a43', true, null);
  insert into ids values ('paul', paul), ('awa', awa);
  perform pg_temp.expect_error(format($$select public.salon_staff_save(%L, null, 'X Y', 'Coiffeur', null, 'percent', 120, 0, '#17408b', true, null)$$, a),
    '23514', 'commission > 100 % refusée');

  -- 3. Catalogue, habilitations et consommables ----------------------------------------------
  tresses := public.salon_service_save(a, null, 'Tresses', 'Coiffure', null, 50000, 120, 0, true, array[paul]);
  coloration := public.salon_service_save(a, null, 'Coloration', 'Couleur', 'Avec soin', 50000, 90, 0, true, array[awa]);
  coupe := public.salon_service_save(a, null, 'Coupe homme', 'Coupe', null, 10000, 30, 0, true, null);
  insert into ids values ('tresses', tresses), ('coloration', coloration), ('coupe', coupe);
  creme := public.salon_supply_save(a, null, 'Crème colorante', 'Couleur', 'ml', 'consumption', 200, 0, null, true);
  huile := public.salon_supply_save(a, null, 'Huile capillaire', 'Soin', 'piece', 'both', 2, 0, 10000, true);
  insert into ids values ('creme', creme), ('huile', huile);
  -- Achats : 1 000 ml à 100 F/ml ; 10 flacons à 5 000 F.
  perform pg_temp.check(public.salon_supply_adjust(a, creme, 'purchase', 1000, 100, null, 'achat-creme-0001') = 1000, 'achat crème');
  perform pg_temp.check(public.salon_supply_adjust(a, creme, 'purchase', 1000, 100, null, 'achat-creme-0001') = 1000,
    'achat rejoué = idempotent');
  perform pg_temp.check((select quantity_on_hand from public.salon_supplies where id = creme) = 1000, 'stock crème une seule fois');
  perform public.salon_supply_adjust(a, huile, 'purchase', 10, 5000, null, 'achat-huile-0001');
  perform public.salon_service_consumables_set(a, coloration, jsonb_build_array(jsonb_build_object('supply_id', creme, 'quantity', 100)));
  perform pg_temp.expect_error(format($$select public.salon_supply_adjust(%L, %L, 'loss', 5000, null, null, 'perte-trop-0001')$$, a, creme),
    '22023', 'perte supérieure au stock refusée');

  -- 4. Clients et doublons --------------------------------------------------------------------
  r := public.salon_client_save(a, null, 'Mireille', 'Kounkou', '+242 06 555 12 34', null, 'Tresses fines', true, true, false);
  client1 := (r ->> 'id')::uuid;
  insert into ids values ('client1', client1);
  r := public.salon_client_save(a, null, 'Mimi', null, '06 555 12 34', null, null, false, false, false);
  perform pg_temp.check(r ->> 'status' = 'possible_duplicate', 'doublon par téléphone détecté');
  r := public.salon_client_save(a, null, 'Junior', 'Mbemba', '061230000', null, 'secret', false, false, false);
  perform pg_temp.check((select preferences from public.salon_clients where id = (r ->> 'id')::uuid) is null,
    'préférences non gardées sans consentement');

  -- 5. Agenda --------------------------------------------------------------------------------
  appt := public.salon_appointment_save(a, null, client1, null, null, paul,
    (tomorrow + time '10:00') at time zone tz, array[tresses], null, 'Tresses longues');
  insert into ids values ('appt', appt);
  perform pg_temp.check((select ends_at - starts_at from public.salon_appointments where id = appt) = interval '120 minutes',
    'durée = somme des prestations');
  perform pg_temp.check((select client_phone from public.salon_appointments where id = appt) = '+242065551234', 'téléphone client repris');
  -- Double réservation du même coiffeur refusée.
  perform pg_temp.expect_error(format($$select public.salon_appointment_save(%L, null, null, 'Béa', null, %L,
    %L::timestamptz, array[%L]::uuid[], null, null)$$, a, paul, (tomorrow + time '11:00') at time zone tz, coupe),
    '23P01', 'chevauchement du même coiffeur refusé');
  -- Rendez-vous adjacent accepté ; autre coiffeur au même moment accepté.
  appt2 := public.salon_appointment_save(a, null, null, 'Béa', '061234000', paul,
    (tomorrow + time '12:00') at time zone tz, array[coupe], null, null);
  perform public.salon_appointment_save(a, null, null, 'Céline', null, awa,
    (tomorrow + time '10:00') at time zone tz, array[coloration], null, null);
  -- Coiffeur non habilité, salon fermé, passé.
  perform pg_temp.expect_error(format($$select public.salon_appointment_save(%L, null, null, 'Dina', null, %L,
    %L::timestamptz, array[%L]::uuid[], null, null)$$, a, paul, (tomorrow + time '15:00') at time zone tz, coloration),
    '22023', 'coiffeur non habilité refusé');
  perform pg_temp.expect_error(format($$select public.salon_appointment_save(%L, null, null, 'Eve', null, %L,
    %L::timestamptz, array[%L]::uuid[], null, null)$$, a, awa, (tomorrow + time '19:30') at time zone tz, coloration),
    '22023', 'fin après la fermeture refusée');
  perform pg_temp.expect_error(format($$select public.salon_appointment_save(%L, null, null, 'Fanny', null, %L,
    now() - interval '2 hours', array[%L]::uuid[], null, null)$$, a, awa, coupe), '22023', 'rendez-vous dans le passé refusé');
  -- Absence et horaires du collaborateur.
  perform public.salon_staff_absence_set(a, awa, tomorrow + 1, true, 'Congé');
  perform pg_temp.expect_error(format($$select public.salon_appointment_save(%L, null, null, 'Gina', null, %L,
    %L::timestamptz, array[%L]::uuid[], null, null)$$, a, awa, (tomorrow + 1 + time '10:00') at time zone tz, coupe),
    '22023', 'collaborateur absent refusé');
  perform public.salon_staff_hours_set(a, paul, (select jsonb_agg(jsonb_build_object('weekday', d,
    'starts_at', '09:00', 'ends_at', '17:00')) from generate_series(1, 7) d));
  perform pg_temp.expect_error(format($$select public.salon_appointment_save(%L, null, null, 'Hawa', null, %L,
    %L::timestamptz, array[%L]::uuid[], null, null)$$, a, paul, (tomorrow + time '16:45') at time zone tz, coupe),
    '22023', 'hors horaires du coiffeur refusé');
  -- Report : déplacer le rendez-vous 2 sur un créneau libre.
  perform public.salon_appointment_save(a, appt2, null, 'Béa', '061234000', paul,
    (tomorrow + time '14:00') at time zone tz, array[coupe], null, 'Reporté');
  perform pg_temp.check((select starts_at from public.salon_appointments where id = appt2)
    = (tomorrow + time '14:00') at time zone tz, 'report enregistré');
  -- Statuts.
  perform pg_temp.expect_error(format($$select public.salon_appointment_set_status(%L, %L, 'completed')$$, a, appt2),
    '22023', 'confirmé → terminé direct refusé');
  perform pg_temp.check(public.salon_appointment_set_status(a, appt2, 'cancelled', 'Client malade') = 'cancelled', 'annulation');
  -- Le créneau libéré se reprend.
  perform public.salon_appointment_save(a, null, null, 'Ines', null, paul,
    (tomorrow + time '14:00') at time zone tz, array[coupe], null, null);

  -- 6. Isolation entre salons et secteurs ------------------------------------------------------
  perform pg_temp.as_user(owner_b);
  perform pg_temp.expect_error(format('select public.salon_agenda(%L, now(), now() + interval ''7 days'')', a),
    '42501', 'autre salon : agenda refusé');
  perform pg_temp.expect_error(format('select public.salon_client_get(%L, %L)', a, client1), '42501', 'autre salon : client refusé');
  perform pg_temp.expect_error(format('select public.salon_appointment_set_status(%L, %L, ''cancelled'')', b, appt),
    '42501', 'rendez-vous d''un autre salon via son propre salon refusé');
  perform pg_temp.as_user(owner_shop);
  perform pg_temp.expect_error(format('select public.salon_catalog(%L)', shop), '42501', 'boutique : fonctions salon refusées');
  perform pg_temp.as_user(stranger);
  perform pg_temp.expect_error(format('select public.salon_dashboard(%L)', a), '42501', 'inconnu refusé');

  -- 7. Comptes collaborateurs : invitation à usage unique --------------------------------------
  perform pg_temp.as_user(owner_a);
  code := public.salon_staff_create_invite(a, 'Mme Responsable', 'manager', null) ->> 'code';
  perform pg_temp.as_user(manager);
  perform pg_temp.check((public.salon_staff_join(code) ->> 'ok')::boolean, 'responsable rejoint');
  perform pg_temp.check((public.salon_staff_join(code) ->> 'ok')::boolean is false, 'code à usage unique');
  perform pg_temp.as_user(owner_a);
  code := public.salon_staff_create_invite(a, 'Paul', 'stylist', paul) ->> 'code';
  perform pg_temp.as_user(stylist);
  perform public.salon_staff_join(code);
  perform pg_temp.as_user(owner_a);
  code := public.salon_staff_create_invite(a, 'Caisse', 'cashier', null) ->> 'code';
  perform pg_temp.as_user(cashier);
  perform public.salon_staff_join(code);
  perform pg_temp.check(public.salon_role(a) = 'cashier', 'rôle caissière');
  perform pg_temp.expect_error(format('select public.salon_staff_create_invite(%L, ''X'', ''manager'', null)', a),
    '42501', 'caissière ne crée pas de compte');

  -- Droits du coiffeur : ses rendez-vous seulement, pas d'annulation, pas de caisse.
  perform pg_temp.as_user(stylist);
  r := public.salon_agenda(a, now(), now() + interval '7 days');
  perform pg_temp.check((select bool_and((x ->> 'employee_id')::uuid = paul) from jsonb_array_elements(r -> 'appointments') x),
    'coiffeur : uniquement ses rendez-vous');
  perform pg_temp.check(jsonb_array_length(r -> 'appointments') >= 2, 'coiffeur voit ses rendez-vous');
  perform pg_temp.expect_error(format('select public.salon_appointment_set_status(%L, %L, ''cancelled'')', a, appt),
    '42501', 'coiffeur ne peut pas annuler');
  perform pg_temp.expect_error(format('select public.salon_ticket_open(%L, null, null, ''X'', ''op-stylist-0001'')', a),
    '42501', 'coiffeur sans accès caisse');
  perform pg_temp.expect_error(format('select public.salon_clients_search(%L, '''', 10)', a), '42501', 'coiffeur sans fichier clients');
  -- Le responsable ne peut pas fixer les commissions.
  perform pg_temp.as_user(manager);
  perform pg_temp.expect_error(format($$select public.salon_staff_save(%L, %L, 'Paul Mabiala', 'Coiffeur', null, 'percent', 50, 0, '#17408b', true, null)$$, a, paul),
    '42501', 'responsable ne change pas une commission');
  perform pg_temp.expect_error(format('select public.salon_settings_save(%L, ''men'', null, null, null, ''Africa/Brazzaville'', ''[]''::jsonb)', a),
    '42501', 'responsable ne change pas les réglages');

  -- 8. Caisse depuis un rendez-vous (caissière) -----------------------------------------------
  perform pg_temp.as_user(owner_a);
  perform public.salon_appointment_set_status(a, appt, 'arrived');
  perform pg_temp.as_user(cashier);
  r := public.salon_ticket_open(a, appt, null, null, 'ticket-appt-0001');
  tk := (r ->> 'id')::uuid;
  perform pg_temp.check((r ->> 'total_xaf')::bigint = 50000, 'ticket pré-rempli avec la prestation du rendez-vous');
  perform pg_temp.check((public.salon_ticket_open(a, appt, null, null, 'ticket-appt-0002') ->> 'id')::uuid = tk,
    'un seul ticket par rendez-vous');
  perform pg_temp.expect_error(format('select public.salon_ticket_add_line(%L, %L, ''service'', %L, %L, 1, 1000)', a, tk, coupe, paul),
    '42501', 'caissière ne change pas un prix');
  perform pg_temp.expect_error(format('select public.salon_ticket_set_discount(%L, %L, 1000)', a, tk), '42501', 'caissière sans remise');
  perform pg_temp.expect_error(format($$select public.salon_ticket_pay(%L, %L, '[{"method":"cash","amount_xaf":40000}]'::jsonb, 'pay-appt-0001')$$, a, tk),
    '22023', 'paiement différent du total refusé');
  r := public.salon_ticket_pay(a, tk, '[{"method":"cash","amount_xaf":30000},{"method":"mobile_money","amount_xaf":20000,"reference":"MP123"}]'::jsonb, 'pay-appt-0001');
  perform pg_temp.check(r ->> 'status' = 'paid', 'ticket payé');
  perform pg_temp.check((select bool_and(x ->> 'confirmation' = 'manual') from jsonb_array_elements(r -> 'payments') x),
    'Mobile Money marqué confirmé manuellement, pas par l''opérateur');
  r := public.salon_ticket_pay(a, tk, '[{"method":"cash","amount_xaf":30000},{"method":"mobile_money","amount_xaf":20000}]'::jsonb, 'pay-appt-0001');
  perform pg_temp.check((select count(*) from public.salon_payments where ticket_id = tk) = 2, 'paiement rejoué non compté deux fois');
  perform pg_temp.check((select status from public.salon_appointments where id = appt) = 'completed', 'rendez-vous terminé au paiement');
  perform pg_temp.check((select commission_xaf from public.salon_ticket_lines where ticket_id = tk) = 12500,
    'commission 25 % de 50 000 = 12 500');
  perform pg_temp.expect_error(format('select public.salon_ticket_refund(%L, %L, array[(select id from public.salon_ticket_lines where ticket_id = %L)], ''cash'', false, ''Erreur'', ''refund-x-0001'')', a, tk, tk),
    '42501', 'caissière ne rembourse pas');
  perform pg_temp.expect_error(format('select public.salon_report(%L, current_date, current_date)', a), '42501', 'caissière sans rapports');
end $t$;

-- 9. Scénario financier du cahier des charges (propriétaire, salon B neuf) -----------------------
-- Prestations 150 000, produits 30 000 → CA 180 000 ; consommables + coût produits 25 000 ;
-- commissions 35 000 ; autres charges 40 000 (+ 35 000 saisis en « Commissions » à exclure)
-- → résultat estimé 80 000.
do $f$
declare
  b uuid := '10000000-0000-0000-0000-00000000a002';
  a uuid := '10000000-0000-0000-0000-00000000a001';
  s1 uuid; s2 uuid; svc_a uuid; svc_b uuid; oil uuid; dye uuid; tk uuid; r jsonb; fin jsonb;
  today date := (now() at time zone 'Africa/Brazzaville')::date;
  line uuid; v_after numeric;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-00000000a002');
  s1 := public.salon_staff_save(b, null, 'Styliste Un', 'Coiffeur', null, 'percent', 25, 0, '#17408b', true, null);
  s2 := public.salon_staff_save(b, null, 'Styliste Deux', 'Coloriste', null, 'percent', 20, 0, '#17408b', true, null);
  svc_a := public.salon_service_save(b, null, 'Tresses', null, null, 50000, 120, 0, true, null);
  svc_b := public.salon_service_save(b, null, 'Coloration', null, null, 50000, 90, 0, true, null);
  dye := public.salon_supply_save(b, null, 'Teinture', null, 'ml', 'consumption', 0, 0, null, true);
  oil := public.salon_supply_save(b, null, 'Huile', null, 'piece', 'sale', 1, 0, 10000, true);
  perform public.salon_supply_adjust(b, dye, 'purchase', 500, 100, null, 'fin-dye-000001');
  perform public.salon_supply_adjust(b, oil, 'purchase', 5, 5000, null, 'fin-oil-000001');
  perform public.salon_service_consumables_set(b, svc_b, jsonb_build_array(jsonb_build_object('supply_id', dye, 'quantity', 100)));

  -- Ticket 1 : 2 tresses par Styliste Un (100 000 → commission 25 000).
  tk := (public.salon_ticket_open(b, null, null, 'Client 1', 'fin-tk1-00001') ->> 'id')::uuid;
  perform public.salon_ticket_add_line(b, tk, 'service', svc_a, s1, 2, null);
  perform public.salon_ticket_pay(b, tk, '[{"method":"cash","amount_xaf":100000}]'::jsonb, 'fin-pay1-0001');
  -- Ticket 2 : coloration par Styliste Deux (50 000 → commission 10 000 ; 100 ml × 100 F = 10 000 de teinture)
  --            + 3 huiles (30 000, coût 15 000).
  tk := (public.salon_ticket_open(b, null, null, 'Client 2', 'fin-tk2-00001') ->> 'id')::uuid;
  perform public.salon_ticket_add_line(b, tk, 'service', svc_b, s2, 1, null);
  perform public.salon_ticket_add_line(b, tk, 'product', oil, null, 3, null);
  perform public.salon_ticket_pay(b, tk, '[{"method":"mobile_money","amount_xaf":80000}]'::jsonb, 'fin-pay2-0001');
  insert into public.shop_expenses(shop_id, category, label, amount, expense_date)
  values (b, 'Loyer', 'Loyer du mois', 40000, today), (b, 'Commissions', 'Commissions coiffeurs', 35000, today);

  fin := public.salon_report(b, today, today) -> 'finance';
  perform pg_temp.check((fin ->> 'services_revenue_xaf')::bigint = 150000, 'prestations 150 000 : ' || (fin ->> 'services_revenue_xaf'));
  perform pg_temp.check((fin ->> 'products_revenue_xaf')::bigint = 30000, 'produits 30 000');
  perform pg_temp.check((fin ->> 'revenue_xaf')::bigint = 180000, 'CA 180 000');
  perform pg_temp.check((fin ->> 'service_direct_costs_xaf')::bigint + (fin ->> 'product_costs_xaf')::bigint = 25000,
    'consommables + coût produits 25 000 : ' || (fin ->> 'service_direct_costs_xaf') || '+' || (fin ->> 'product_costs_xaf'));
  perform pg_temp.check((fin ->> 'commissions_due_xaf')::bigint = 35000, 'commissions 35 000');
  perform pg_temp.check((fin ->> 'other_charges_xaf')::bigint = 40000, 'charges hors commissions 40 000 (pas de double comptage)');
  perform pg_temp.check((fin ->> 'estimated_result_xaf')::bigint = 80000, 'résultat estimé 80 000 : ' || (fin ->> 'estimated_result_xaf'));
  perform pg_temp.check((fin ->> 'net_collected_xaf')::bigint = 180000, 'encaissements nets 180 000');
  perform pg_temp.check((select quantity_on_hand from public.salon_supplies where id = dye) = 400, 'teinture consommée une fois');
  perform pg_temp.check((select quantity_on_hand from public.salon_supplies where id = oil) = 2, 'huile décrémentée une fois');

  -- Remboursement d'une huile vendue (ligne entière : 3 huiles), remise en stock.
  select id into line from public.salon_ticket_lines where ticket_id = tk and kind = 'product';
  r := public.salon_ticket_refund(b, tk, array[line], 'mobile_money', true, 'Produit défectueux', 'fin-ref1-0001');
  perform pg_temp.check(r ->> 'status' = 'partially_refunded', 'ticket partiellement remboursé');
  r := public.salon_ticket_refund(b, tk, array[line], 'mobile_money', true, 'Produit défectueux', 'fin-ref1-0001');
  perform pg_temp.check((select count(*) from public.salon_payments where ticket_id = tk and kind = 'refund') = 1,
    'remboursement rejoué non compté deux fois');
  perform pg_temp.expect_error(format('select public.salon_ticket_refund(%L, %L, array[%L]::uuid[], ''cash'', true, ''Encore'', ''fin-ref2-0001'')', b, tk, line),
    '22023', 'ligne déjà remboursée refusée');
  perform pg_temp.check((select quantity_on_hand from public.salon_supplies where id = oil) = 5, 'huiles remises en stock');
  fin := public.salon_report(b, today, today) -> 'finance';
  perform pg_temp.check((fin ->> 'revenue_xaf')::bigint = 150000, 'CA corrigé après remboursement');
  perform pg_temp.check((fin ->> 'product_costs_xaf')::bigint = 0, 'coût des produits remboursés retiré');
  perform pg_temp.check((fin ->> 'net_collected_xaf')::bigint = 150000, 'encaissements nets corrigés');
  perform pg_temp.check((fin ->> 'refunds_xaf')::bigint = 30000, 'remboursement visible, pas effacé');

  -- Commissions : solde et versement plafonné.
  perform pg_temp.check((select (x ->> 'balance_xaf')::bigint from jsonb_array_elements(public.salon_commission_balances(b)) x
    where (x ->> 'employee_id')::uuid = s1) = 25000, 'commission due Styliste Un 25 000');
  perform public.salon_commission_pay(b, s1, 20000, 'cash', 'Acompte', 'fin-payout-001');
  perform pg_temp.expect_error(format('select public.salon_commission_pay(%L, %L, 10000, ''cash'', null, ''fin-payout-002'')', b, s1),
    '22023', 'versement supérieur au dû refusé');
  fin := public.salon_report(b, today, today) -> 'finance';
  perform pg_temp.check((fin ->> 'commissions_due_xaf')::bigint = 35000, 'versement ≠ nouvelle charge');
  perform pg_temp.check((fin ->> 'commissions_paid_xaf')::bigint = 20000, 'versement en trésorerie');

  -- Remise répartie au prorata, commissions calculées sur le net.
  tk := (public.salon_ticket_open(b, null, null, 'Client 3', 'fin-tk3-00001') ->> 'id')::uuid;
  perform public.salon_ticket_add_line(b, tk, 'service', svc_a, s1, 1, null);
  perform public.salon_ticket_set_discount(b, tk, 10000);
  r := public.salon_ticket_pay(b, tk, '[{"method":"cash","amount_xaf":40000}]'::jsonb, 'fin-pay3-0001');
  perform pg_temp.check((select net_xaf from public.salon_ticket_lines where ticket_id = tk) = 40000, 'remise appliquée');
  perform pg_temp.check((select commission_xaf from public.salon_ticket_lines where ticket_id = tk) = 10000, 'commission sur le net');

  -- Ticket ouvert = en attente, jamais du CA.
  tk := (public.salon_ticket_open(b, null, null, 'Client 4', 'fin-tk4-00001') ->> 'id')::uuid;
  perform public.salon_ticket_add_line(b, tk, 'service', svc_a, s1, 1, null);
  fin := public.salon_report(b, today, today) -> 'finance';
  perform pg_temp.check((fin ->> 'pending_checkout_xaf')::bigint = 50000, 'prestation non payée en attente');
  perform pg_temp.check((fin ->> 'revenue_xaf')::bigint = 190000, 'non payé exclu du CA');
  perform pg_temp.expect_error(format($$select public.salon_ticket_pay(%L, %L, '[{"method":"cash","amount_xaf":50000}]'::jsonb, 'fin-pay1-0001')$$, b, tk),
    '22023', 'clé de paiement déjà utilisée sur un autre ticket ne paie pas');
  perform pg_temp.check((select status from public.salon_tickets where id = tk) = 'open', 'ticket 4 toujours ouvert');

  -- Stock insuffisant pour un produit vendu : paiement refusé, rien n'est décrémenté.
  perform public.salon_ticket_add_line(b, tk, 'product', oil, null, 9, null);
  perform pg_temp.expect_error(format($$select public.salon_ticket_pay(%L, %L, '[{"method":"cash","amount_xaf":140000}]'::jsonb, 'fin-pay4-0001')$$, b, tk),
    '22023', 'stock insuffisant refusé');
  perform pg_temp.check((select quantity_on_hand from public.salon_supplies where id = oil) = 5, 'stock intact après refus');

  -- Tableau de bord et faits pour l'assistant.
  r := public.salon_dashboard(b);
  perform pg_temp.check((r -> 'day' -> 'finance' ->> 'revenue_xaf')::bigint = 190000, 'tableau de bord : CA du jour');
  r := public.salon_ai_facts(b);
  perform pg_temp.check(r ->> 'sector' = 'salon' and (r -> 'today' -> 'finance' ->> 'revenue_xaf')::bigint = 190000, 'faits assistant');
  perform pg_temp.check(r::text not like '%+242%', 'aucun téléphone client transmis à l''assistant');
end $f$;

-- 6 bis. Accès direct aux tables refusé à tout compte connecté.
set local role authenticated;
do $r$
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000a001', true);
  perform pg_temp.expect_error('select * from public.salon_appointments', '42501', 'lecture directe de table refusée');
  perform pg_temp.expect_error('select * from public.salon_clients', '42501', 'lecture directe des clients refusée');
  perform pg_temp.expect_error($$update public.salon_supplies set quantity_on_hand = 999$$, '42501', 'écriture directe du stock refusée');
  perform pg_temp.expect_error($$insert into public.salon_payments(shop_id, ticket_id, kind, method, amount_xaf, operation_key)
    values ('10000000-0000-0000-0000-00000000a001', gen_random_uuid(), 'payment', 'cash', 1, 'direct-000001')$$, '42501', 'paiement direct refusé');
end $r$;
reset role;

-- 10. Défense en profondeur : même un accès direct (superutilisateur) ne crée pas de doublon.
reset role;
do $d$
declare
  a uuid := '10000000-0000-0000-0000-00000000a001';
  appt record;
begin
  select * into appt from public.salon_appointments where shop_id = a and status = 'confirmed' order by starts_at limit 1;
  begin
    insert into public.salon_appointments (shop_id, client_name, employee_id, starts_at, ends_at, status)
    values (a, 'Intrus', appt.employee_id, appt.starts_at + interval '5 minutes', appt.ends_at, 'confirmed');
    raise exception 'FAIL contrainte d''exclusion absente';
  exception when exclusion_violation then null;
  end;
  begin
    update public.salon_tickets set shop_id = '10000000-0000-0000-0000-00000000a002'
    where shop_id = a and status = 'paid';
    raise exception 'FAIL ticket déplacé vers un autre salon';
  exception when check_violation then null;
  end;
  perform pg_temp.check(not has_table_privilege('anon', 'public.salon_tickets', 'select')
    and not has_table_privilege('authenticated', 'public.salon_payments', 'insert')
    and not has_table_privilege('authenticated', 'public.salon_supplies', 'update')
    and not has_function_privilege('anon', 'public.salon_ticket_pay(uuid,uuid,jsonb,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.salon_require(uuid,text)', 'execute'),
    'privilèges : aucune écriture directe, anon exclu');
end $d$;

select 'ok salon_pro : droits, agenda, caisse, stock, commissions, finances';
rollback;
