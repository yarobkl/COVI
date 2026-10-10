-- COVI SaaS — création contrôlée de facture pour un Owner existant.
-- L'invitation d'un nouvel utilisateur doit passer par une API serveur
-- Supabase Auth Admin ; jamais par une clé service_role exposée au navigateur.

create or replace function public.covi_admin_issue_subscription_invoice(
  p_owner_user_id uuid,
  p_invoice_number text,
  p_shop_limit integer,
  p_period_start timestamptz,
  p_period_end timestamptz
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_account_id uuid;
  v_plan_id uuid;
  v_subscription_id uuid;
  v_invoice_id uuid;
  v_amount integer;
begin
  if not public.covi_is_platform_admin() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
  if p_owner_user_id is null or nullif(btrim(p_invoice_number), '') is null
     or p_shop_limit is null or p_shop_limit < 1
     or p_period_start is null or p_period_end is null
     or p_period_end <= p_period_start then
    raise exception 'Invalid subscription invoice details' using errcode = '22023';
  end if;

  -- Le compte doit déjà exister dans Supabase Auth.
  insert into public.covi_owner_accounts (user_id)
    values (p_owner_user_id)
    on conflict (user_id) do update set user_id = excluded.user_id
    returning id into v_account_id;

  select id, first_shop_monthly_xaf + (p_shop_limit - 1) * extra_shop_monthly_xaf
    into v_plan_id, v_amount
    from public.covi_subscription_plans
    where code = 'covi-monthly-v1';
  if not found then
    raise exception 'Subscription plan missing' using errcode = 'P0001';
  end if;

  -- Lock owner account so concurrent invoice issuance cannot create
  -- two current subscriptions.
  perform 1 from public.covi_owner_accounts where id = v_account_id for update;

  select id into v_subscription_id from public.covi_subscriptions
    where owner_account_id = v_account_id
      and status in ('pending_payment', 'active', 'grace', 'suspended')
    for update;

  if not found then
    insert into public.covi_subscriptions (owner_account_id, plan_id, status, shop_limit)
      values (v_account_id, v_plan_id, 'pending_payment', p_shop_limit)
      returning id into v_subscription_id;
  end if;

  -- One outstanding invoice per subscription to avoid ambiguous manual matching.
  if exists (
    select 1 from public.covi_subscription_invoices
    where subscription_id = v_subscription_id and status = 'pending'
  ) then
    raise exception 'Pending invoice already exists' using errcode = 'P0001';
  end if;

  insert into public.covi_subscription_invoices (
    subscription_id, invoice_number, period_start, period_end,
    shop_limit, amount_xaf, status
  ) values (
    v_subscription_id, btrim(p_invoice_number), p_period_start, p_period_end,
    p_shop_limit, v_amount, 'pending'
  ) returning id into v_invoice_id;

  insert into public.covi_subscription_audit (
    actor_user_id, owner_account_id, action, details
  ) values (
    auth.uid(), v_account_id, 'subscription_invoice_issued',
    jsonb_build_object('invoice_id', v_invoice_id, 'amount_xaf', v_amount,
                       'shop_limit', p_shop_limit)
  );
  return v_invoice_id;
end;
$$;
revoke all on function public.covi_admin_issue_subscription_invoice(uuid,text,integer,timestamptz,timestamptz)
  from public, anon;
grant execute on function public.covi_admin_issue_subscription_invoice(uuid,text,integer,timestamptz,timestamptz)
  to authenticated;
