-- Ephemeral local Supabase Auth + PostgREST only. NOT A PRODUCTION MIGRATION.
-- Supabase CLI has already provisioned auth.users, auth.uid() and the API roles.
-- Production COVI's existing tables are intentionally NOT copied.
begin;
create table public.shops (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id),
  name text not null
);
create table public.arrivals (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id),
  status text not null default 'received',
  is_test boolean not null default false
);
create table public.sales (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id),
  payment_method text not null,
  total_amount numeric not null default 0,
  sold_at timestamptz not null default now(),
  client_operation_id uuid,
  is_test boolean not null default false
);
alter table public.shops enable row level security;
create policy "owners only see native fixture shops"
  on public.shops for select to authenticated
  using (owner_id = (select auth.uid()));
grant select on public.shops to authenticated;
commit;
