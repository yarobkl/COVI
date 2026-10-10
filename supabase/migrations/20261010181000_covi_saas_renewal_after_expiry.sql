-- COVI SaaS — correctif d'audit : renouvellement possible après expiration de la période.
-- NE PAS APPLIQUER en production sans revue et accord explicite du porteur de projet.
--
-- Constat (tests/sql/saas_simulation.sql, étape 12c) : aucune tâche ne fait passer un
-- abonnement de 'active' à 'grace'/'suspended' à l'échéance. Un abonnement échu reste donc
-- 'active' avec period_end <= now(), et covi_admin_confirm_mobile_payment refusait de le
-- renouveler (« Subscription cannot be activated from this state ») : le seul contournement
-- était de le suspendre d'abord.
--
-- Changements, signature et droits inchangés :
--   1. un abonnement 'active' dont la période est TERMINÉE peut être réactivé par une facture
--      payée (un abonnement 'active' en cours reste protégé : pas d'écrasement de période) ;
--   2. le contrôle de période de la facture (commit d94478c) est placé AVANT toute écriture.
--      Fonctionnellement c'était déjà atomique (l'exception annule tout), mais l'ordre rend
--      l'intention lisible et évite des écritures inutiles.

create or replace function public.covi_admin_confirm_mobile_payment(
  p_invoice_id uuid,
  p_provider text,
  p_provider_reference text,
  p_amount_xaf integer
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_invoice public.covi_subscription_invoices%rowtype;
  v_payment_id uuid;
  v_owner_account_id uuid;
begin
  if not public.covi_is_platform_admin() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
  if nullif(btrim(p_provider), '') is null
     or nullif(btrim(p_provider_reference), '') is null
     or p_amount_xaf is null or p_amount_xaf <= 0 then
    raise exception 'Invalid payment details' using errcode = '22023';
  end if;

  select * into v_invoice from public.covi_subscription_invoices
    where id = p_invoice_id for update;
  if not found or v_invoice.status <> 'pending' then
    raise exception 'Invoice not pending' using errcode = 'P0001';
  end if;
  if v_invoice.amount_xaf <> p_amount_xaf then
    raise exception 'Payment amount mismatch' using errcode = 'P0001';
  end if;
  -- Avant toute écriture : période de la facture en cours.
  if v_invoice.period_end <= now() or v_invoice.period_start > now() then
    raise exception 'Invoice period is not currently valid' using errcode = 'P0001';
  end if;

  insert into public.covi_subscription_payments (
    invoice_id, provider, provider_reference, amount_xaf,
    status, verified_by, verified_at
  ) values (
    p_invoice_id, btrim(p_provider), btrim(p_provider_reference),
    p_amount_xaf, 'verified', auth.uid(), now()
  ) returning id into v_payment_id;

  update public.covi_subscription_invoices
    set status = 'paid' where id = p_invoice_id;

  update public.covi_subscriptions
    set status = 'active',
        shop_limit = v_invoice.shop_limit,
        period_start = v_invoice.period_start,
        period_end = v_invoice.period_end,
        grace_until = null
    where id = v_invoice.subscription_id
      and (status in ('pending_payment', 'suspended', 'grace')
           or (status = 'active' and period_end <= now()));

  if not found then
    raise exception 'Subscription cannot be activated from this state'
      using errcode = 'P0001';
  end if;

  select owner_account_id into v_owner_account_id
    from public.covi_subscriptions where id = v_invoice.subscription_id;

  insert into public.covi_subscription_audit (
    actor_user_id, owner_account_id, action, details
  ) values (
    auth.uid(), v_owner_account_id, 'mobile_payment_confirmed',
    jsonb_build_object(
      'invoice_id', p_invoice_id, 'payment_id', v_payment_id,
      'provider', btrim(p_provider), 'amount_xaf', p_amount_xaf
    )
  );

  return v_payment_id;
end;
$$;
revoke all on function public.covi_admin_confirm_mobile_payment(uuid,text,text,integer)
  from public, anon;
grant execute on function public.covi_admin_confirm_mobile_payment(uuid,text,text,integer)
  to authenticated;
