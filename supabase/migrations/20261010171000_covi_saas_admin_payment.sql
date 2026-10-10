-- COVI SaaS — administration manuelle Mobile Money.
-- DÉPEND de 20261010170000_covi_saas_foundation.sql.
-- À tester sur une base de test ; NE PAS APPLIQUER en production sans accord explicite.

create table public.covi_platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.covi_platform_admins enable row level security;
revoke all on public.covi_platform_admins from anon, authenticated;

-- Bootstrap initial uniquement via rôle service_role / SQL admin après vérification
-- de l'identité. Ne jamais laisser un utilisateur s'auto-déclarer admin.

create or replace function public.covi_is_platform_admin()
returns boolean language sql stable security definer
set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1 from public.covi_platform_admins a where a.user_id = auth.uid()
  );
$$;
revoke all on function public.covi_is_platform_admin() from public, anon;
grant execute on function public.covi_is_platform_admin() to authenticated;

-- Vue sécurisée pour le tableau de bord Super Admin : pas de numéros
-- Mobile Money en clair ni de données des ventes des boutiques.
create or replace function public.covi_admin_subscription_overview()
returns table (
  subscription_id uuid,
  owner_user_id uuid,
  status text,
  shop_limit integer,
  period_end timestamptz,
  monthly_price_xaf integer
) language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.covi_is_platform_admin() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
  return query
    select s.id, a.user_id, s.status, s.shop_limit, s.period_end,
      (p.first_shop_monthly_xaf + (s.shop_limit - 1) * p.extra_shop_monthly_xaf)::integer
    from public.covi_subscriptions s
    join public.covi_owner_accounts a on a.id = s.owner_account_id
    join public.covi_subscription_plans p on p.id = s.plan_id
    order by s.created_at desc;
end;
$$;
revoke all on function public.covi_admin_subscription_overview() from public, anon;
grant execute on function public.covi_admin_subscription_overview() to authenticated;

-- Après vérification humaine des fonds effectivement reçus, l'administrateur
-- enregistre une transaction. Le même couple fournisseur/référence ne peut
-- jamais être confirmé deux fois (index de la migration précédente).
-- Une facture doit déjà exister : sa création fait partie du workflow
-- administratif futur, pas d'un droit accordé au client.
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
  -- V1 : paiement complet seulement, sans crédit partiel ni prorata implicite.
  if v_invoice.amount_xaf <> p_amount_xaf then
    raise exception 'Payment amount mismatch' using errcode = 'P0001';
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

  -- Refuser l'activation d'une période déjà terminée ou incohérente.
  if v_invoice.period_end <= now() or v_invoice.period_start > now() then
    raise exception 'Invoice period is not currently valid' using errcode = 'P0001';
  end if;

  -- La confirmation d'une facture ne peut pas écraser une période active.
  -- Le renouvellement anticipé sera traité par un workflow distinct.
  update public.covi_subscriptions
    set status = 'active',
        shop_limit = v_invoice.shop_limit,
        period_start = v_invoice.period_start,
        period_end = v_invoice.period_end,
        grace_until = null
    where id = v_invoice.subscription_id
      and status in ('pending_payment', 'suspended', 'grace');

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
