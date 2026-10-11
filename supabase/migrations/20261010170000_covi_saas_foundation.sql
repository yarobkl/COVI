-- COVI SaaS foundation: additive only, no production deployment authorized.
-- Does NOT drop shops_owner_id_uidx or alter create_my_shop yet.
-- No payment may be self-confirmed by an authenticated client.

create table public.covi_owner_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.covi_subscription_plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  currency text not null default 'XAF' check (currency = 'XAF'),
  first_shop_monthly_xaf integer not null check (first_shop_monthly_xaf >= 0),
  extra_shop_monthly_xaf integer not null check (extra_shop_monthly_xaf >= 0),
  created_at timestamptz not null default now()
);

insert into public.covi_subscription_plans
  (code, currency, first_shop_monthly_xaf, extra_shop_monthly_xaf)
values ('covi-monthly-v1', 'XAF', 10000, 5000);

create table public.covi_subscriptions (
  id uuid primary key default gen_random_uuid(),
  owner_account_id uuid not null references public.covi_owner_accounts(id) on delete cascade,
  plan_id uuid not null references public.covi_subscription_plans(id),
  status text not null default 'pending_payment'
    check (status in ('pending_payment', 'active', 'grace', 'suspended', 'cancelled')),
  shop_limit integer not null default 1 check (shop_limit >= 1),
  period_start timestamptz,
  period_end timestamptz,
  grace_until timestamptz,
  created_at timestamptz not null default now(),
  check (period_start is null or period_end is null or period_end > period_start)
);

create unique index covi_subscriptions_one_current_per_owner
  on public.covi_subscriptions(owner_account_id)
  where status in ('pending_payment', 'active', 'grace', 'suspended');

create table public.covi_subscription_invoices (
  id uuid primary key default gen_random_uuid(),
  subscription_id uuid not null references public.covi_subscriptions(id),
  invoice_number text not null unique,
  period_start timestamptz not null,
  period_end timestamptz not null,
  shop_limit integer not null check (shop_limit >= 1),
  currency text not null default 'XAF' check (currency = 'XAF'),
  amount_xaf integer not null check (amount_xaf >= 0),
  status text not null default 'pending' check (status in ('pending','paid','cancelled')),
  created_at timestamptz not null default now(),
  check (period_end > period_start)
);

create table public.covi_subscription_payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.covi_subscription_invoices(id),
  provider text not null,
  provider_reference text,
  amount_xaf integer not null check (amount_xaf > 0),
  status text not null default 'pending' check (status in ('pending','verified','rejected')),
  verified_by uuid references auth.users(id),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  check ((status = 'verified') = (verified_by is not null and verified_at is not null))
);

create unique index covi_verified_payment_reference
  on public.covi_subscription_payments(provider, provider_reference)
  where status = 'verified' and provider_reference is not null;

create table public.covi_subscription_audit (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id),
  owner_account_id uuid references public.covi_owner_accounts(id),
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- RLS is enabled on every table, with NO client write policies.
-- Owner-facing reads are limited to their own subscription/invoice records.
alter table public.covi_owner_accounts enable row level security;
alter table public.covi_subscription_plans enable row level security;
alter table public.covi_subscriptions enable row level security;
alter table public.covi_subscription_invoices enable row level security;
alter table public.covi_subscription_payments enable row level security;
alter table public.covi_subscription_audit enable row level security;

create policy covi_owner_account_read on public.covi_owner_accounts
  for select to authenticated using (user_id = (select auth.uid()));

create policy covi_plan_read on public.covi_subscription_plans
  for select to authenticated using (true);

create policy covi_subscription_owner_read on public.covi_subscriptions
  for select to authenticated using (
    exists (select 1 from public.covi_owner_accounts a
      where a.id = owner_account_id and a.user_id = (select auth.uid()))
  );

create policy covi_invoice_owner_read on public.covi_subscription_invoices
  for select to authenticated using (
    exists (select 1 from public.covi_subscriptions s
      join public.covi_owner_accounts a on a.id = s.owner_account_id
      where s.id = subscription_id and a.user_id = (select auth.uid()))
  );

-- Payments and audit are administrative-only: no authenticated client read policy.
revoke all on public.covi_owner_accounts, public.covi_subscription_plans,
  public.covi_subscriptions, public.covi_subscription_invoices,
  public.covi_subscription_payments, public.covi_subscription_audit from anon, authenticated;
grant select on public.covi_owner_accounts, public.covi_subscription_plans,
  public.covi_subscriptions, public.covi_subscription_invoices to authenticated;

-- Future activation, payment verification and quota changes must be implemented
-- via a separately audited server-only path; never expose service_role in the UI.
