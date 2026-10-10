-- COVI SaaS — état d'abonnement lisible par le commerçant connecté (lecture seule).
-- Branche claude/audit-saas (#14). NE PAS APPLIQUER en production sans revue et accord explicite.
--
-- Pourquoi : l'interface doit savoir, avant d'agir, si la boutique est en lecture seule et si
-- « Ajouter une boutique » est possible. Sans cette fonction, le front recopiait en TypeScript la
-- règle de covi_shop_subscription_writable (non exécutable par authenticated) et celle du quota
-- de create_my_shop. Ici, une seule source : la base.
--
-- Renvoie, pour le compte de auth.uid() uniquement (jamais un autre compte), un jsonb :
--   status      text | null   statut de l'abonnement courant (null : commerçant V1 sans compte SaaS,
--                             ou compte sans aucun abonnement)
--   writable    boolean       même règle que covi_shop_subscription_writable (migration 180000) :
--                             V1 → vrai ; pending_payment jamais activé → vrai ; active dans sa
--                             période → vrai ; grace avant grace_until → vrai ; sinon faux
--   shopLimit   int | null    boutiques couvertes (V1 : 1 ; compte sans abonnement : null)
--   shopCount   int           boutiques du compte
--   canAddShop  boolean       même règle que create_my_shop (migration 174000) : V1 → aucune
--                             boutique encore ; compte SaaS → abonnement 'active' dans sa période
--                             ET shopCount < shopLimit
--   periodEnd   timestamptz | null
--   isLegacyV1  boolean       pas de ligne covi_owner_accounts
-- Pas de détail par boutique : toutes les boutiques d'un compte ont le même propriétaire, donc
-- le même état (le garde-fou décide d'après le propriétaire de la boutique).
--
-- Le serveur reste l'autorité : cette fonction n'autorise rien, les écritures restent contrôlées
-- par le trigger covi_subscription_write_guard et par create_my_shop.

create or replace function public.covi_my_subscription_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_account uuid;
  v_count integer;
  v_sub public.covi_subscriptions;
  v_writable boolean;
  v_can_add boolean;
begin
  if v_uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select count(*)::integer into v_count from public.shops where owner_id = v_uid;
  select a.id into v_account from public.covi_owner_accounts a where a.user_id = v_uid;

  if v_account is null then
    return jsonb_build_object(
      'status', null, 'writable', true, 'shopLimit', 1, 'shopCount', v_count,
      'canAddShop', v_count < 1, 'periodEnd', null, 'isLegacyV1', true);
  end if;

  -- Abonnement courant : au plus un (index covi_subscriptions_one_current_per_owner) ;
  -- à défaut, le plus récent (annulé).
  select s.* into v_sub from public.covi_subscriptions s
    where s.owner_account_id = v_account
    order by (s.status in ('pending_payment', 'active', 'grace', 'suspended')) desc,
             s.created_at desc, s.id
    limit 1;

  -- Même expression que covi_shop_subscription_writable, sur toutes les lignes du compte.
  v_writable := exists (
    select 1 from public.covi_subscriptions s
    where s.owner_account_id = v_account
      and (
        (s.status = 'pending_payment' and s.period_start is null)
        or (s.status = 'active' and s.period_start <= now() and s.period_end > now())
        or (s.status = 'grace' and s.grace_until > now())
      )
  );

  -- Même condition que create_my_shop pour un compte SaaS.
  v_can_add := exists (
    select 1 from public.covi_subscriptions s
    where s.owner_account_id = v_account
      and s.status = 'active'
      and s.period_start <= now()
      and s.period_end > now()
      and v_count < s.shop_limit
  );

  return jsonb_build_object(
    'status', v_sub.status,
    'writable', v_writable,
    'shopLimit', v_sub.shop_limit,
    'shopCount', v_count,
    'canAddShop', v_can_add,
    'periodEnd', v_sub.period_end,
    'isLegacyV1', false);
end;
$$;

revoke all on function public.covi_my_subscription_state() from public, anon;
grant execute on function public.covi_my_subscription_state() to authenticated;
