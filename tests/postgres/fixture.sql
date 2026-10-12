-- Disposable PostgreSQL fixture only; never run against production.
-- Minimal shape of existing COVI tables required by isolated SQL drafts.
create schema if not exists auth;
create role authenticated nologin;
create role anon nologin;

create table auth.users (id uuid primary key);
create function auth.uid() returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

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

insert into auth.users(id) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');

insert into public.shops(id, owner_id, name) values
  ('11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Boutique A'),
  ('22222222-2222-4222-8222-222222222222', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Boutique B');

grant usage on schema public, auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
