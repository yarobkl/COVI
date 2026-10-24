-- COVI Salon : recette SAL-001..SAL-014 et FIN-002..FIN-006 (docs/recette/SALON.md et FINANCE.md,
-- PR #67), exécutée côté serveur sur les vraies fonctions. Données 100 % fictives.
-- Chaque contrôle porte l'ID du scénario. Les écarts avec le référentiel qui relèvent d'une décision
-- du propriétaire (FIN-004) sont MESURÉS et affichés (NOTICE), pas corrigés : la règle reste celle
-- de 20261024095000_salon_pro_reports.sql.
-- Base jetable, tout est annulé (rollback) à la fin.
\set ON_ERROR_STOP 1
begin;

-- Utilisateurs : propriétaires des salons A, B, F (finances) et R (remboursement entre deux mois),
-- coiffeur A (compte relié), inconnu.
insert into auth.users(id) values
 ('00000000-0000-0000-0000-0000000005a1'), -- propriétaire salon A
 ('00000000-0000-0000-0000-0000000005b1'), -- propriétaire salon B
 ('00000000-0000-0000-0000-0000000005f1'), -- propriétaire salon F
 ('00000000-0000-0000-0000-0000000005e1'), -- propriétaire salon R
 ('00000000-0000-0000-0000-0000000005a2'), -- coiffeur A (Paul)
 ('00000000-0000-0000-0000-0000000005a3'); -- inconnu
insert into public.shops(id, owner_id, name, business_kind) values
 ('10000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000005a1', 'Salon A (test)', 'salon'),
 ('10000000-0000-0000-0000-0000000005b1', '00000000-0000-0000-0000-0000000005b1', 'Salon B (test)', 'salon'),
 ('10000000-0000-0000-0000-0000000005f1', '00000000-0000-0000-0000-0000000005f1', 'Salon F (test)', 'salon'),
 ('10000000-0000-0000-0000-0000000005e1', '00000000-0000-0000-0000-0000000005e1', 'Salon R (test)', 'salon');

create function pg_temp.as_user(p uuid) returns void language sql as
$$ select set_config('request.jwt.claim.sub', coalesce(p::text, ''), true) $$;
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
  raise notice 'ok % (refus % : %)', p_label, v_state, v_msg;
end $$;
create function pg_temp.check(p_ok boolean, p_label text) returns void language plpgsql as
$$ begin if p_ok is not true then raise exception 'FAIL %', p_label; end if; raise notice 'ok %', p_label; end $$;
create function pg_temp.hours() returns jsonb language sql as
$$ select jsonb_agg(jsonb_build_object('weekday', d, 'opens_at', '08:00', 'closes_at', '20:00')) from generate_series(1, 7) d $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- SAL-001 à SAL-006, SAL-009 à SAL-011 : salon A, attaques depuis B, coiffeur et inconnu --------------
do $t$
declare
  a uuid := '10000000-0000-0000-0000-0000000005a1';
  b uuid := '10000000-0000-0000-0000-0000000005b1';
  owner_a uuid := '00000000-0000-0000-0000-0000000005a1';
  owner_b uuid := '00000000-0000-0000-0000-0000000005b1';
  stylist uuid := '00000000-0000-0000-0000-0000000005a2';
  stranger uuid := '00000000-0000-0000-0000-0000000005a3';
  tz text := 'Africa/Brazzaville';
  d date := (now() at time zone 'Africa/Brazzaville')::date + 2;
  paul uuid; awa uuid; coupe uuid; coloration uuid; soin uuid; huile uuid; gel uuid;
  client1 uuid; appt uuid; n_before bigint; code text; r jsonb; tk uuid; line uuid; v numeric;
begin
  perform pg_temp.as_user(owner_a);
  perform public.salon_settings_save(a, 'mixed', 'Mme A', null, 2, tz, pg_temp.hours());
  paul := public.salon_staff_save(a, null, 'Paul Test', 'Coiffeur', null, 'percent', 10, 0, '#17408b', true, null);
  awa := public.salon_staff_save(a, null, 'Awa Test', 'Coloriste', null, 'percent', 10, 0, '#0a7a43', true, null);
  coupe := public.salon_service_save(a, null, 'Coupe', 'Coupe', null, 12000, 30, 0, true, array[paul, awa]);
  coloration := public.salon_service_save(a, null, 'Coloration', 'Couleur', null, 15000, 30, 0, true, array[awa]);
  client1 := (public.salon_client_save(a, null, 'Cliente', 'Fictive', '060000001', null, null, false, false, false) ->> 'id')::uuid;

  -- SAL-001 : même coiffeur, 10:00–10:30 deux fois → le second est refusé par la contrainte.
  appt := public.salon_appointment_save(a, null, client1, null, null, paul, (d + time '10:00') at time zone tz, array[coupe], null, null);
  perform pg_temp.expect_error(format($$select public.salon_appointment_save(%L, null, null, 'Doublon', null, %L,
    %L::timestamptz, array[%L]::uuid[], null, null)$$, a, paul, (d + time '10:00') at time zone tz, coupe),
    '23P01', 'SAL-001 second RDV 10:00–10:30 du même coiffeur refusé');
  perform pg_temp.check((select count(*) from public.salon_appointments where shop_id = a and employee_id = paul) = 1,
    'SAL-001 un seul RDV enregistré pour Paul');
  -- (Version concurrente : tests/sql/salon_concurrency.sh, cas 1.)

  -- SAL-002 : autre coiffeur, même créneau → admis.
  perform public.salon_appointment_save(a, null, null, 'Autre cliente', '060000002', awa, (d + time '10:00') at time zone tz, array[coupe], null, null);
  perform pg_temp.check((select count(*) from public.salon_appointments where shop_id = a
    and starts_at = (d + time '10:00') at time zone tz) = 2, 'SAL-002 deux coiffeurs distincts au même créneau');

  -- SAL-003 : absence et hors horaires individuels → refus, aucune réservation partielle.
  select count(*) into n_before from public.salon_appointments where shop_id = a;
  perform public.salon_staff_absence_set(a, awa, d + 1, true, 'Congé');
  perform pg_temp.expect_error(format($$select public.salon_appointment_save(%L, null, null, 'Absente', null, %L,
    %L::timestamptz, array[%L]::uuid[], null, null)$$, a, awa, (d + 1 + time '10:00') at time zone tz, coupe),
    '22023', 'SAL-003 RDV pendant une absence refusé');
  perform public.salon_staff_hours_set(a, paul, (select jsonb_agg(jsonb_build_object('weekday', x,
    'starts_at', '09:00', 'ends_at', '17:00')) from generate_series(1, 7) x));
  perform pg_temp.expect_error(format($$select public.salon_appointment_save(%L, null, null, 'Tard', null, %L,
    %L::timestamptz, array[%L]::uuid[], null, null)$$, a, paul, (d + time '16:45') at time zone tz, coupe),
    '22023', 'SAL-003 RDV hors horaires du coiffeur refusé');
  perform pg_temp.check((select count(*) from public.salon_appointments where shop_id = a) = n_before
    and not exists (select 1 from public.salon_appointment_services s where s.shop_id = a
                    and not exists (select 1 from public.salon_appointments x where x.id = s.appointment_id)),
    'SAL-003 aucune réservation partielle');

  -- SAL-004 : coiffeur non habilité (Paul n'est pas habilité à la coloration) → refus serveur.
  perform pg_temp.expect_error(format($$select public.salon_appointment_save(%L, null, null, 'Couleur', null, %L,
    %L::timestamptz, array[%L]::uuid[], null, null)$$, a, paul, (d + time '14:00') at time zone tz, coloration),
    '22023', 'SAL-004 coiffeur non habilité refusé');
  perform pg_temp.check((select count(*) from public.salon_appointments where shop_id = a) = n_before,
    'SAL-004 rien n''est écrit');

  -- SAL-005 : invitation à usage unique, rôle restreint.
  code := public.salon_staff_create_invite(a, 'Paul', 'stylist', paul) ->> 'code';
  perform pg_temp.as_user(stylist);
  perform pg_temp.check((public.salon_staff_join(code) ->> 'ok')::boolean, 'SAL-005 le coiffeur rejoint avec le code');
  perform pg_temp.check(public.salon_role(a) = 'stylist', 'SAL-005 rôle restreint « stylist »');
  perform pg_temp.as_user(stranger);
  perform pg_temp.check((public.salon_staff_join(code) ->> 'ok')::boolean is false, 'SAL-005 second usage du code refusé');
  perform pg_temp.check(public.salon_role(a) is null, 'SAL-005 l''inconnu n''a obtenu aucun rôle');

  -- SAL-006 : le coiffeur ne lit pas le fichier clients et ne rembourse pas.
  perform pg_temp.as_user(owner_a);
  huile := public.salon_supply_save(a, null, 'Huile', 'Soin', 'piece', 'sale', 1, 0, 6000, true);
  perform public.salon_supply_adjust(a, huile, 'purchase', 5, 3000, null, 'a-huile-achat-01');
  tk := (public.salon_ticket_open(a, null, client1, null, 'a-tk-0000000001') ->> 'id')::uuid;
  perform public.salon_ticket_add_line(a, tk, 'service', coupe, paul, 1, null);
  perform public.salon_ticket_add_line(a, tk, 'product', huile, null, 1, null);
  perform public.salon_ticket_pay(a, tk, '[{"method":"cash","amount_xaf":18000}]'::jsonb, 'a-pay-000000001');
  perform pg_temp.as_user(stylist);
  perform pg_temp.expect_error(format('select public.salon_clients_search(%L, '''', 50)', a), '42501', 'SAL-006 coiffeur : recherche clients refusée');
  perform pg_temp.expect_error(format('select public.salon_client_get(%L, %L)', a, client1), '42501', 'SAL-006 coiffeur : fiche client refusée');
  perform pg_temp.expect_error(format('select public.salon_ticket_refund(%L, %L, array[(select id from public.salon_ticket_lines where ticket_id = %L and kind = ''service'')], ''cash'', false, ''Essai'', ''a-ref-stylist-01'')', a, tk, tk),
    '42501', 'SAL-006 coiffeur : remboursement refusé');
  perform pg_temp.expect_error(format('select public.salon_report(%L, current_date, current_date)', a), '42501', 'SAL-006 coiffeur : rapports refusés');
  r := public.salon_agenda(a, now(), now() + interval '7 days');
  perform pg_temp.check((select bool_and((x ->> 'employee_id')::uuid = paul) from jsonb_array_elements(r -> 'appointments') x)
    and r::text not like '%0000002%' and r::text not like '%Autre cliente%',
    'SAL-006 agenda du coiffeur : ses RDV seulement, aucun client d''un collègue');
  -- Observation (règle de conception, docs/salon/AUDIT-ET-ARCHITECTURE.md) : sur SES rendez-vous, le
  -- coiffeur voit le nom et le téléphone du client. À confirmer par le propriétaire si SAL-006
  -- l'exclut aussi.
  if r::text like '%0000001%' then
    raise notice 'OBSERVATION SAL-006 : le coiffeur voit le téléphone du client de ses propres rendez-vous';
  end if;

  -- SAL-009 : remboursement d'une ligne payée, motif obligatoire, rejoué une seule fois ; sans
  -- demande explicite de remise en stock, le produit ne revient pas.
  perform pg_temp.as_user(owner_a);
  select id into line from public.salon_ticket_lines where ticket_id = tk and kind = 'product';
  perform pg_temp.expect_error(format('select public.salon_ticket_refund(%L, %L, array[%L]::uuid[], ''cash'', false, '' '', ''a-ref-0000000001'')', a, tk, line),
    '22023', 'SAL-009 motif obligatoire');
  v := (select quantity_on_hand from public.salon_supplies where id = huile);
  r := public.salon_ticket_refund(a, tk, array[line], 'cash', false, 'Produit abîmé', 'a-ref-0000000001');
  r := public.salon_ticket_refund(a, tk, array[line], 'cash', false, 'Produit abîmé', 'a-ref-0000000001');
  perform pg_temp.check((select count(*) from public.salon_payments where ticket_id = tk and kind = 'refund') = 1
    and (select sum(amount_xaf) from public.salon_payments where ticket_id = tk and kind = 'refund') = 6000,
    'SAL-009 une seule écriture de remboursement de 6 000 malgré la relance');
  perform pg_temp.expect_error(format('select public.salon_ticket_refund(%L, %L, array[%L]::uuid[], ''cash'', false, ''Encore'', ''a-ref-0000000002'')', a, tk, line),
    '22023', 'SAL-009 ligne déjà remboursée refusée avec une nouvelle clé');
  perform pg_temp.check((select quantity_on_hand from public.salon_supplies where id = huile) = v,
    'SAL-009 stock non restitué sans demande explicite');
  perform pg_temp.check((select count(*) from public.salon_events where entity_id = tk and event_type = 'ticket_refunded') = 1,
    'SAL-009 un seul événement de remboursement tracé');

  -- SAL-011 : consommable requis 30 ml, stock 20 ml → la caisse passe, sortie 20, manque 10 signalé.
  gel := public.salon_supply_save(a, null, 'Gel', 'Soin', 'ml', 'consumption', 0, 0, null, true);
  perform public.salon_supply_adjust(a, gel, 'purchase', 20, 10, null, 'a-gel-achat-001');
  soin := public.salon_service_save(a, null, 'Soin gel', 'Soin', null, 5000, 30, 0, true, null);
  perform public.salon_service_consumables_set(a, soin, jsonb_build_array(jsonb_build_object('supply_id', gel, 'quantity', 30)));
  tk := (public.salon_ticket_open(a, null, null, 'Passage', 'a-tk-0000000002') ->> 'id')::uuid;
  perform public.salon_ticket_add_line(a, tk, 'service', soin, awa, 1, null);
  r := public.salon_ticket_pay(a, tk, '[{"method":"cash","amount_xaf":5000}]'::jsonb, 'a-pay-000000002');
  perform pg_temp.check(r ->> 'status' = 'paid', 'SAL-011 la caisse n''est pas bloquée');
  perform pg_temp.check((select quantity_on_hand from public.salon_supplies where id = gel) = 0, 'SAL-011 stock 20 → 0, jamais négatif');
  perform pg_temp.check((select delta = -20 and shortfall = 10 from public.salon_supply_movements
    where ticket_id = tk and supply_id = gel and reason = 'consumption'), 'SAL-011 sortie de 20 ml, manque 10 ml noté');
  perform pg_temp.check(exists (select 1 from public.salon_events where shop_id = a and event_type = 'stock_shortfall'
    and entity_id = gel and (details ->> 'missing')::numeric = 10), 'SAL-011 manque signalé dans le journal');

  -- SAL-010 : le propriétaire de B appelle les fonctions de A avec des UUID connus.
  perform pg_temp.as_user(owner_b);
  perform public.salon_settings_save(b, 'mixed', 'Mme B', null, 1, tz, pg_temp.hours());
  perform pg_temp.expect_error(format('select public.salon_agenda(%L, now(), now() + interval ''7 days'')', a), '42501', 'SAL-010 agenda de A refusé');
  perform pg_temp.expect_error(format('select public.salon_client_get(%L, %L)', a, client1), '42501', 'SAL-010 client de A refusé');
  perform pg_temp.expect_error(format('select public.salon_ticket_get(%L, %L)', a, tk), '42501', 'SAL-010 ticket de A refusé');
  perform pg_temp.expect_error(format('select public.salon_report(%L, current_date - 30, current_date)', a), '42501', 'SAL-010 rapport de A refusé');
  perform pg_temp.expect_error(format('select public.salon_commission_balances(%L)', a), '42501', 'SAL-010 commissions de A refusées');
  perform pg_temp.expect_error(format('select public.salon_ticket_get(%L, %L)', b, tk), '42501', 'SAL-010 ticket de A via le salon B refusé');
  perform pg_temp.expect_error(format('select public.salon_ticket_refund(%L, %L, array[(select id from public.salon_ticket_lines where ticket_id = %L)], ''cash'', false, ''Intrus'', ''b-ref-intrus-01'')', b, tk, tk),
    '42501', 'SAL-010 remboursement d''un ticket de A via B refusé');
  perform pg_temp.expect_error(format('select public.salon_appointment_set_status(%L, %L, ''cancelled'')', b, appt), '42501', 'SAL-010 RDV de A via B refusé');
  perform pg_temp.check((select status from public.salon_appointments where id = appt) = 'confirmed'
    and (select count(*) from public.salon_payments where ticket_id = tk) = 1, 'SAL-010 état de A inchangé');
  perform pg_temp.as_user(stranger);
  perform pg_temp.expect_error(format('select public.salon_dashboard(%L)', a), '42501', 'SAL-010 inconnu : tableau de bord refusé');
end $t$;

-- SAL-007, SAL-008, FIN-002, FIN-003, FIN-005, FIN-006 : salon F, données du référentiel ---------------
-- Prestation 12 000 (coût direct 2 000, commission 10 % = 1 200) + produit 6 000 (coût 3 000) ;
-- payé 10 000 espèces + 8 000 Mobile Money ; charge 1 500.
do $f$
declare
  f uuid := '10000000-0000-0000-0000-0000000005f1';
  tz text := 'Africa/Brazzaville';
  today date := (now() at time zone 'Africa/Brazzaville')::date;
  sty uuid; svc uuid; prod uuid; tk uuid; r jsonb; fin jsonb; line uuid;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000005f1');
  perform public.salon_settings_save(f, 'mixed', 'Mme F', null, 1, tz, pg_temp.hours());
  sty := public.salon_staff_save(f, null, 'Styliste F', 'Coiffeur', null, 'percent', 10, 0, '#17408b', true, null);
  svc := public.salon_service_save(f, null, 'Prestation', 'Coiffure', null, 12000, 60, 2000, true, null);
  prod := public.salon_supply_save(f, null, 'Produit', 'Soin', 'piece', 'sale', 0, 0, 6000, true);
  perform public.salon_supply_adjust(f, prod, 'purchase', 1, 3000, null, 'f-prod-achat-01');
  insert into public.shop_expenses(shop_id, category, label, amount, expense_date) values (f, 'Loyer', 'Charge test', 1500, today);

  -- SAL-007 / FIN-003 : paiement mixte.
  tk := (public.salon_ticket_open(f, null, null, 'Client F', 'f-tk-0000000001') ->> 'id')::uuid;
  perform public.salon_ticket_add_line(f, tk, 'service', svc, sty, 1, null);
  perform public.salon_ticket_add_line(f, tk, 'product', prod, null, 1, null);
  r := public.salon_ticket_pay(f, tk, '[{"method":"cash","amount_xaf":10000},{"method":"mobile_money","amount_xaf":8000}]'::jsonb, 'f-pay-000000001');
  perform pg_temp.check((r ->> 'total_xaf')::bigint = 18000 and r ->> 'status' = 'paid', 'SAL-007 total 18 000, ticket payé');
  perform pg_temp.check((select sum(amount_xaf) = 18000 and count(*) = 2 from public.salon_payments where ticket_id = tk and kind = 'payment'),
    'SAL-007 / FIN-003 paiements cumulés 18 000 (10 000 + 8 000), une seule fois');
  perform pg_temp.check((select confirmation from public.salon_payments where ticket_id = tk and method = 'mobile_money') = 'manual'
    and (select reference from public.salon_payments where ticket_id = tk and method = 'mobile_money') is null,
    'SAL-007 / FIN-003 Mobile Money : confirmation manuelle, sans référence opérateur');

  -- SAL-008 / FIN-003 : même clé rejouée → 0 encaissement, 0 commission, 0 débit de stock en plus.
  r := public.salon_ticket_pay(f, tk, '[{"method":"cash","amount_xaf":10000},{"method":"mobile_money","amount_xaf":8000}]'::jsonb, 'f-pay-000000001');
  perform pg_temp.check((select count(*) from public.salon_payments where ticket_id = tk) = 2, 'SAL-008 aucun paiement en double');
  perform pg_temp.check((select quantity_on_hand from public.salon_supplies where id = prod) = 0
    and (select count(*) from public.salon_supply_movements where ticket_id = tk and reason = 'sale') = 1, 'SAL-008 stock débité une seule fois');
  perform pg_temp.check((select sum(commission_xaf) from public.salon_ticket_lines where ticket_id = tk) = 1200, 'SAL-008 commission 1 200 une seule fois');
  perform pg_temp.check((select count(*) from public.salon_events where entity_id = tk and event_type = 'ticket_paid') = 1, 'SAL-008 un seul événement de paiement');

  -- FIN-002 : rapport de la période comparé au référentiel.
  fin := public.salon_report(f, today, today) -> 'finance';
  raise notice 'FIN-002 rapport : %', fin;
  perform pg_temp.check((fin ->> 'services_revenue_xaf')::bigint = 12000 and (fin ->> 'products_revenue_xaf')::bigint = 6000
    and (fin ->> 'revenue_xaf')::bigint = 18000, 'FIN-002 CA 12 000 + 6 000 = 18 000');
  perform pg_temp.check((fin ->> 'service_direct_costs_xaf')::bigint + (fin ->> 'product_costs_xaf')::bigint = 5000, 'FIN-002 coûts directs 5 000');
  perform pg_temp.check((fin ->> 'gross_margin_xaf')::bigint = 13000, 'FIN-002 marge brute 13 000');
  perform pg_temp.check((fin ->> 'commissions_due_xaf')::bigint = 1200, 'FIN-002 commissions dues 1 200');
  perform pg_temp.check((fin ->> 'other_charges_xaf')::bigint = 1500, 'FIN-002 charges 1 500');
  perform pg_temp.check((fin ->> 'estimated_result_xaf')::bigint = 10300, 'FIN-002 résultat de pilotage 10 300');
  perform pg_temp.check((fin ->> 'net_collected_xaf')::bigint = 18000, 'FIN-002 encaissements nets 18 000');
  perform pg_temp.check((fin ->> 'commissions_paid_xaf')::bigint = 0, 'FIN-002 commission due mais pas versée : aucune sortie');

  -- FIN-005 : commission 1 200 versée + charge saisie en catégorie « Commission » (même 1 200).
  perform public.salon_commission_pay(f, sty, 1200, 'cash', null, 'f-payout-000001');
  insert into public.shop_expenses(shop_id, category, label, amount, expense_date) values (f, 'Commission', 'Commission Styliste F', 1200, today);
  fin := public.salon_report(f, today, today) -> 'finance';
  raise notice 'FIN-005 rapport : %', fin;
  perform pg_temp.check((fin ->> 'commissions_due_xaf')::bigint = 1200 and (fin ->> 'other_charges_xaf')::bigint = 1500
    and (fin ->> 'commission_category_charges_xaf')::bigint = 1200 and (fin ->> 'estimated_result_xaf')::bigint = 10300,
    'FIN-005 résultat : une seule charge commission de 1 200 (la charge « Commission » est mise à part)');
  -- Trésorerie : 18 000 − 1 200 versés − 1 500 charges − 3 000 achat produit = 12 300.
  perform pg_temp.check((fin ->> 'commissions_paid_xaf')::bigint = 1200 and (fin ->> 'estimated_cash_flow_xaf')::bigint = 12300,
    'FIN-005 trésorerie : une seule sortie de 1 200 (flux 12 300 avec l''achat de 3 000)');

  -- FIN-006 : remboursement de la ligne produit 6 000 avec remise en stock.
  select id into line from public.salon_ticket_lines where ticket_id = tk and kind = 'product';
  perform public.salon_ticket_refund(f, tk, array[line], 'cash', true, 'Retour produit', 'f-ref-000000001');
  fin := public.salon_report(f, today, today) -> 'finance';
  raise notice 'FIN-006 rapport : %', fin;
  perform pg_temp.check((fin ->> 'net_collected_xaf')::bigint = 12000, 'FIN-006 encaissements nets 12 000');
  perform pg_temp.check((select quantity_on_hand from public.salon_supplies where id = prod) = 1, 'FIN-006 +1 unité remise en stock');
  perform pg_temp.check((fin ->> 'commissions_due_xaf')::bigint = 1200
    and (select commission_xaf from public.salon_ticket_lines where ticket_id = tk and kind = 'service') = 1200,
    'FIN-006 commission de la prestation conservée');
  perform pg_temp.check((fin ->> 'revenue_xaf')::bigint = 12000 and (fin ->> 'product_costs_xaf')::bigint = 0
    and (fin ->> 'service_direct_costs_xaf')::bigint = 2000, 'FIN-006 CA 12 000, coût produit retiré, coût prestation gardé');
end $f$;

-- FIN-004 / SAL-012 : prestation 12 000 payée le 28/09, remboursée intégralement le 05/10 ----------------
-- On passe par les vraies fonctions, puis on antidate (comme supabase/preprod/seed_salon.sql).
do $m$
declare
  s uuid := '10000000-0000-0000-0000-0000000005e1';
  tz text := 'Africa/Brazzaville';
  v_paid timestamptz := timestamp '2026-09-28 12:00' at time zone 'Africa/Brazzaville';
  v_refunded timestamptz := timestamp '2026-10-05 12:00' at time zone 'Africa/Brazzaville';
  sty uuid; svc uuid; tk uuid; line uuid; sep jsonb; oct jsonb; sep_before jsonb; total jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000005e1');
  perform public.salon_settings_save(s, 'mixed', 'Mme R', null, 1, tz, pg_temp.hours());
  sty := public.salon_staff_save(s, null, 'Styliste R', 'Coiffeur', null, 'percent', 10, 0, '#17408b', true, null);
  svc := public.salon_service_save(s, null, 'Prestation', 'Coiffure', null, 12000, 60, 0, true, null);
  tk := (public.salon_ticket_open(s, null, null, 'Client R', 'r-tk-0000000001') ->> 'id')::uuid;
  perform public.salon_ticket_add_line(s, tk, 'service', svc, sty, 1, null);
  perform public.salon_ticket_pay(s, tk, '[{"method":"cash","amount_xaf":12000}]'::jsonb, 'r-pay-000000001');
  update public.salon_tickets set paid_at = v_paid, opened_at = v_paid where id = tk;
  update public.salon_payments set recorded_at = v_paid where ticket_id = tk;
  sep_before := public.salon_report(s, '2026-09-01', '2026-09-30') -> 'finance';
  perform pg_temp.check((sep_before ->> 'revenue_xaf')::bigint = 12000 and (sep_before ->> 'payments_xaf')::bigint = 12000,
    'FIN-004 avant remboursement : septembre CA 12 000, encaissé 12 000');

  select id into line from public.salon_ticket_lines where ticket_id = tk;
  perform public.salon_ticket_refund(s, tk, array[line], 'cash', false, 'Client mécontent', 'r-ref-000000001');
  update public.salon_ticket_lines set refunded_at = v_refunded where ticket_id = tk;
  update public.salon_payments set recorded_at = v_refunded where ticket_id = tk and kind = 'refund';

  sep := public.salon_report(s, '2026-09-01', '2026-09-30') -> 'finance';
  oct := public.salon_report(s, '2026-10-01', '2026-10-31') -> 'finance';
  total := public.salon_report(s, '2026-09-01', '2026-10-31') -> 'finance';
  raise notice 'FIN-004 MESURE septembre : CA % | encaissé % | remboursé % | net encaissé % | commissions dues % | résultat %',
    sep ->> 'revenue_xaf', sep ->> 'payments_xaf', sep ->> 'refunds_xaf', sep ->> 'net_collected_xaf',
    sep ->> 'commissions_due_xaf', sep ->> 'estimated_result_xaf';
  raise notice 'FIN-004 MESURE octobre   : CA % | encaissé % | remboursé % | net encaissé % | commissions dues % | résultat %',
    oct ->> 'revenue_xaf', oct ->> 'payments_xaf', oct ->> 'refunds_xaf', oct ->> 'net_collected_xaf',
    oct ->> 'commissions_due_xaf', oct ->> 'estimated_result_xaf';
  raise notice 'FIN-004 MESURE sept.+oct.: CA % | net encaissé %', total ->> 'revenue_xaf', total ->> 'net_collected_xaf';

  -- Trésorerie : conforme à la recommandation (+12 000 en septembre, −12 000 en octobre).
  perform pg_temp.check((sep ->> 'net_collected_xaf')::bigint = 12000 and (oct ->> 'refunds_xaf')::bigint = 12000
    and (oct ->> 'net_collected_xaf')::bigint = -12000, 'FIN-004 trésorerie : +12 000 en septembre, −12 000 en octobre');
  perform pg_temp.check((total ->> 'revenue_xaf')::bigint = 0 and (total ->> 'net_collected_xaf')::bigint = 0,
    'FIN-004 cumul sept.+oct. : CA net 0, flux net 0');
  -- ANOMALIE ANO-FIN-001 (constat, pas un échec de la suite — décision du propriétaire en attente) :
  -- la recommandation FIN-004 veut septembre figé (CA +12 000) et un ajustement de CA −12 000 en octobre.
  -- La règle actuelle de salon_report retire la vente du CA de SEPTEMBRE (l.refunded_at is null) et
  -- n'inscrit aucun ajustement de CA en octobre. On fige ici le comportement mesuré pour qu'un
  -- changement de règle soit visible ; à mettre à jour avec la décision du propriétaire.
  perform pg_temp.check((sep ->> 'revenue_xaf')::bigint = 0 and (oct ->> 'revenue_xaf')::bigint = 0,
    'FIN-004 règle actuelle mesurée : septembre CA 0 (rétroactif), octobre CA 0 (pas d''ajustement)');
  if (sep ->> 'revenue_xaf')::bigint <> 12000 then
    raise notice 'ANOMALIE ANO-FIN-001 CONFIRMÉE : CA de septembre % au lieu de 12 000 (recommandation FIN-004) ; octobre % au lieu de −12 000',
      sep ->> 'revenue_xaf', oct ->> 'revenue_xaf';
  end if;
end $m$;

-- SAL-014 : fonction sensible appelée sans droits ou sans session → échec explicite, rien d'écrit ------
do $p$
declare
  a uuid := '10000000-0000-0000-0000-0000000005a1';
  n_pay bigint := (select count(*) from public.salon_payments);
  missing text;
begin
  -- Aucune fonction Salon exécutable par anon, toutes en SECURITY DEFINER avec search_path figé.
  select string_agg(p.proname, ', ') into missing from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname like 'salon\_%' and has_function_privilege('anon', p.oid, 'execute');
  perform pg_temp.check(missing is null, 'SAL-014 aucune fonction salon_* exécutable par anon' || coalesce(' : ' || missing, ''));
  select string_agg(p.proname, ', ') into missing from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname like 'salon\_%' and p.prosecdef
    and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
  perform pg_temp.check(missing is null, 'SAL-014 search_path figé sur toutes les fonctions SECURITY DEFINER' || coalesce(' : ' || missing, ''));
  -- Sans utilisateur (jeton absent) : refus explicite avant toute écriture.
  perform pg_temp.as_user(null);
  perform pg_temp.expect_error(format($$select public.salon_ticket_open(%L, null, null, 'X', 'anon-tk-000001')$$, a), '42501', 'SAL-014 ouverture de ticket sans session refusée');
  perform pg_temp.expect_error(format('select public.salon_report(%L, current_date, current_date)', a), '42501', 'SAL-014 rapport sans session refusé');
  perform pg_temp.check((select count(*) from public.salon_payments) = n_pay
    and not exists (select 1 from public.salon_tickets where client_name = 'X'), 'SAL-014 aucune écriture partielle');
end $p$;

-- SAL-014 (suite) : rôle anon réel (PostgREST) : ni fonction, ni table.
set local role anon;
do $q$
begin
  perform pg_temp.expect_error($$select public.salon_report('10000000-0000-0000-0000-0000000005a1', current_date, current_date)$$,
    '42501', 'SAL-014 anon : salon_report non exécutable');
  perform pg_temp.expect_error('select * from public.salon_tickets', '42501', 'SAL-014 anon : table des tickets illisible');
end $q$;
reset role;

select 'ok recette_salon : SAL-001..012, SAL-014, FIN-002..006 (SAL-013 visuel hors base)';
rollback;
