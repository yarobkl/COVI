-- COVI: proposed additive schema for category stock.
-- REVIEW ONLY: this file is NOT applied to Supabase.
-- Existing products, sales, sale_items, arrivals and authentication remain untouched.
begin;

create table if not exists public.stock_categories (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id),
  category_key text not null,
  display_name text not null,
  quantity_on_hand integer not null default 0 check (quantity_on_hand >= 0),
  quantity_reserved integer not null default 0 check (quantity_reserved >= 0),
  is_test boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stock_categories_valid_key check (category_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint stock_categories_reserved_le_total check (quantity_reserved <= quantity_on_hand),
  constraint stock_categories_shop_category_test_unique unique (shop_id, category_key, is_test),
  constraint stock_categories_id_shop_unique unique (id, shop_id)
);

-- These composite FKs ensure arrivals belong to the same shop as their stock categories.
-- A unique (id, shop_id) index is additive and does not change existing arrival rows.
create unique index if not exists arrivals_id_shop_for_stock_fk on public.arrivals(id, shop_id);
create unique index if not exists sales_id_shop_for_stock_fk on public.sales(id, shop_id);

create table if not exists public.arrival_category_items (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id),
  arrival_id uuid not null,
  category_id uuid not null,
  quantity_received integer not null check (quantity_received > 0),
  created_at timestamptz not null default now(),
  constraint arrival_category_items_arrival_shop_fk foreign key (arrival_id, shop_id)
    references public.arrivals(id, shop_id),
  constraint arrival_category_items_category_shop_fk foreign key (category_id, shop_id)
    references public.stock_categories(id, shop_id),
  constraint arrival_category_items_unique unique (arrival_id, category_id)
);

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id),
  category_id uuid not null,
  movement_type text not null check (movement_type in ('receipt','sale','correction','reversal')),
  quantity_delta integer not null check (quantity_delta <> 0),
  arrival_id uuid,
  sale_id uuid,
  operation_id uuid not null,
  created_at timestamptz not null default now(),
  constraint stock_movements_arrival_shop_fk foreign key (arrival_id, shop_id)
    references public.arrivals(id, shop_id),
  constraint stock_movements_sale_shop_fk foreign key (sale_id, shop_id)
    references public.sales(id, shop_id),
  constraint stock_movements_category_shop_fk foreign key (category_id, shop_id)
    references public.stock_categories(id, shop_id),
  constraint stock_movements_unique_operation unique (shop_id, category_id, operation_id)
);

-- A durable canonical payload makes retries safe even when the same UUID is reused
-- with different category quantities.
create table if not exists public.arrival_stock_postings (
  arrival_id uuid primary key,
  shop_id uuid not null,
  operation_id uuid not null,
  canonical_lines jsonb not null check (jsonb_typeof(canonical_lines) = 'array'),
  category_count integer not null check (category_count > 0),
  created_at timestamptz not null default now(),
  constraint arrival_stock_postings_arrival_shop_fk foreign key (arrival_id, shop_id)
    references public.arrivals(id, shop_id),
  constraint arrival_stock_postings_unique_operation unique (shop_id, operation_id)
);

create index if not exists stock_movements_shop_category_date_idx
  on public.stock_movements(shop_id, category_id, created_at desc);

alter table public.stock_categories enable row level security;
alter table public.arrival_category_items enable row level security;
alter table public.stock_movements enable row level security;
alter table public.arrival_stock_postings enable row level security;

-- Read-only for shop owners. Writes will require vetted SECURITY DEFINER RPCs
-- with explicit auth.uid() ownership checks and row locking.
create policy "owner can read category stock"
  on public.stock_categories for select to authenticated
  using (exists (select 1 from public.shops s where s.id = shop_id and s.owner_id = (select auth.uid())));
create policy "owner can read arrival categories"
  on public.arrival_category_items for select to authenticated
  using (exists (select 1 from public.shops s where s.id = shop_id and s.owner_id = (select auth.uid())));
create policy "owner can read stock movements"
  on public.stock_movements for select to authenticated
  using (exists (select 1 from public.shops s where s.id = shop_id and s.owner_id = (select auth.uid())));

create policy "owner can read arrival stock postings"
  on public.arrival_stock_postings for select to authenticated
  using (exists (select 1 from public.shops s where s.id = shop_id and s.owner_id = (select auth.uid())));

-- Explicitly prevent direct writes from client roles. Future audited RPCs may
-- use a dedicated owner with controlled privileges; table owners retain DDL rights.
revoke insert, update, delete on public.stock_categories from anon, authenticated;
revoke insert, update, delete on public.arrival_category_items from anon, authenticated;
revoke insert, update, delete on public.stock_movements from anon, authenticated;
revoke insert, update, delete on public.arrival_stock_postings from anon, authenticated;

-- No anonymous policies and no direct INSERT/UPDATE/DELETE policies.
-- Before applying: inspect pre-existing policy names and default privileges;
-- validate this SQL in a disposable local database first.
-- IMPORTANT: CREATE POLICY is not idempotent; this draft must not be reapplied blindly.
commit;
