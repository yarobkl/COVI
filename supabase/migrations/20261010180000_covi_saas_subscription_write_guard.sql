-- COVI SaaS — garde-fou : un abonnement suspendu ou échu bloque RÉELLEMENT les écritures métier.
-- Correctif d'audit (branche claude/audit-saas) des migrations 2026101017xxxx de la PR #12.
-- NE PAS APPLIQUER en production sans revue et accord explicite du porteur de projet.
--
-- Constat : covi_admin_suspend_subscription passait le statut à 'suspended', mais aucune
-- écriture n'en tenait compte : record_sale, record_cart_sale, INSERT/UPDATE de products,
-- arrivals, shop_expenses restaient possibles (simulation tests/sql/saas_simulation.sql,
-- étape 10). Seul create_my_shop vérifiait l'abonnement.
--
-- Règle (décidée au niveau de la boutique, d'après son PROPRIÉTAIRE, pas de l'appelant) :
--   * propriétaire sans compte SaaS (commerçant V1 historique) ............ écriture permise
--   * abonnement 'pending_payment' jamais activé (period_start NULL) ........ écriture permise
--     (seul un commerçant V1 à qui l'on vient d'émettre une première facture peut avoir des
--      boutiques dans cet état : create_my_shop exige un abonnement actif pour un compte SaaS ;
--      on ne gèle donc pas un commerçant historique dès l'émission de sa facture)
--   * 'active' avec period_start <= now() < period_end ...................... écriture permise
--   * 'grace' avec grace_until > now() ...................................... écriture permise
--   * tout le reste (suspended, cancelled, active échu, grace échue) ........ écriture REFUSÉE
-- La lecture n'est jamais bloquée : les données restent consultables pendant la suspension.
--
-- Contexte serveur : sans utilisateur connecté (auth.uid() NULL : service_role, migrations,
-- tâches d'administration), le contrôle ne s'applique pas. Les RPC SECURITY DEFINER
-- (record_sale, record_cart_sale) gardent auth.uid() du commerçant : elles sont contrôlées.
--
-- Erreur : SQLSTATE P0001, message 'Subscription inactive: shop is read-only'. Le message ne
-- contient aucun des mots que la file hors ligne (src/lib/offline.ts) traite comme une erreur
-- réseau : une vente hors ligne rejouée après suspension est donc rejetée de façon définitive,
-- conservée avec son motif, et le stock local est restauré.

create or replace function public.covi_shop_subscription_writable(p_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_shop_id is null then true  -- laissé aux contraintes NOT NULL / RLS existantes
    when not exists (
      select 1 from public.shops sh
      join public.covi_owner_accounts a on a.user_id = sh.owner_id
      where sh.id = p_shop_id
    ) then true
    else exists (
      select 1
      from public.shops sh
      join public.covi_owner_accounts a on a.user_id = sh.owner_id
      join public.covi_subscriptions s on s.owner_account_id = a.id
      where sh.id = p_shop_id
        and (
          (s.status = 'pending_payment' and s.period_start is null)
          or (s.status = 'active' and s.period_start <= now() and s.period_end > now())
          or (s.status = 'grace' and s.grace_until > now())
        )
    )
  end
$$;
revoke all on function public.covi_shop_subscription_writable(uuid) from public, anon, authenticated;

create or replace function public.covi_enforce_subscription_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_shop_id uuid;
begin
  if auth.uid() is null then
    return coalesce(new, old);
  end if;
  if tg_table_name = 'shops' then
    v_shop_id := old.id;
  elsif tg_op = 'DELETE' then
    v_shop_id := old.shop_id;
  else
    v_shop_id := new.shop_id;
  end if;
  if not public.covi_shop_subscription_writable(v_shop_id) then
    raise exception 'Subscription inactive: shop is read-only' using errcode = 'P0001';
  end if;
  -- Déplacement d'une ligne depuis une boutique en lecture seule : refusé aussi.
  if tg_op = 'UPDATE' and tg_table_name <> 'shops' then
    if old.shop_id is distinct from new.shop_id
       and not public.covi_shop_subscription_writable(old.shop_id) then
      raise exception 'Subscription inactive: shop is read-only' using errcode = 'P0001';
    end if;
  end if;
  return coalesce(new, old);
end;
$$;
revoke all on function public.covi_enforce_subscription_write() from public, anon, authenticated;

-- Tables métier portant shop_id. sale_items n'a pas de shop_id : ses écritures client sont
-- déjà interdites (#6) et record_sale/record_cart_sale insèrent d'abord dans sales.
drop trigger if exists covi_subscription_write_guard on public.products;
create trigger covi_subscription_write_guard
  before insert or update or delete on public.products
  for each row execute function public.covi_enforce_subscription_write();

drop trigger if exists covi_subscription_write_guard on public.arrivals;
create trigger covi_subscription_write_guard
  before insert or update or delete on public.arrivals
  for each row execute function public.covi_enforce_subscription_write();

drop trigger if exists covi_subscription_write_guard on public.sales;
create trigger covi_subscription_write_guard
  before insert or update or delete on public.sales
  for each row execute function public.covi_enforce_subscription_write();

drop trigger if exists covi_subscription_write_guard on public.shop_expenses;
create trigger covi_subscription_write_guard
  before insert or update or delete on public.shop_expenses
  for each row execute function public.covi_enforce_subscription_write();

-- Suppression d'une boutique (et de toutes ses données en cascade) interdite pendant une
-- suspension : « suspension sans perte de données ». Le renommage reste permis.
drop trigger if exists covi_subscription_write_guard on public.shops;
create trigger covi_subscription_write_guard
  before delete on public.shops
  for each row execute function public.covi_enforce_subscription_write();
