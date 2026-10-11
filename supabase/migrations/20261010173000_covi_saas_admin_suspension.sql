-- COVI SaaS: suspension administrative explicite, sans effacer les boutiques.
-- Requiert les migrations SaaS précédentes. Ne pas appliquer en production
-- sans revue de sécurité, tests SQL et accord du propriétaire.

create or replace function public.covi_admin_suspend_subscription(
  p_subscription_id uuid,
  p_reason text
) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_owner_account_id uuid;
begin
  if not public.covi_is_platform_admin() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
  if p_subscription_id is null or length(btrim(coalesce(p_reason, ''))) < 8 then
    raise exception 'Subscription ID and reason (8 characters minimum) required'
      using errcode = '22023';
  end if;

  update public.covi_subscriptions
    set status = 'suspended', grace_until = null
    where id = p_subscription_id
      and status in ('active', 'grace')
    returning owner_account_id into v_owner_account_id;

  if not found then
    raise exception 'Active subscription not found' using errcode = 'P0001';
  end if;

  insert into public.covi_subscription_audit (
    actor_user_id, owner_account_id, action, details
  ) values (
    auth.uid(), v_owner_account_id, 'subscription_suspended',
    jsonb_build_object('subscription_id', p_subscription_id,
                       'reason', btrim(p_reason))
  );
end;
$$;
revoke all on function public.covi_admin_suspend_subscription(uuid,text)
  from public, anon;
grant execute on function public.covi_admin_suspend_subscription(uuid,text)
  to authenticated;
