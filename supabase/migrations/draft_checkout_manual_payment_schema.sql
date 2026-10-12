-- COVI DRAFT: omnichannel orders and manual cashier payment confirmation.
-- NOT APPLIED. Review with existing shops/users schema before executing.
-- Depends on draft_category_stock_schema.sql.
-- No payment provider integration: payment is received externally, then
-- a server-side authorized cashier/owner records their manual confirmation.
begin;

create table if not exists public.checkout_orders (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id),
  channel text not null check (channel in ('qr', 'social', 'manual')),
  status text not null default 'submitted'
    check (status in ('submitted', 'approved', 'reserved', 'paid', 'cancelled', 'expired')),
  is_test boolean not null default false,
  customer_phone text,
  customer_note text,
  fulfillment text not null default 'pickup'
    check (fulfillment in ('pickup', 'delivery')),
  amount_xaf bigint not null check (amount_xaf >= 0 and amount_xaf <= 9000000000000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint checkout_orders_id_shop_unique unique (id, shop_id)
);

create table if not exists public.checkout_order_lines (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  order_id uuid not null,
  category_id uuid not null,
  quantity integer not null check (quantity > 0),
  negotiated_unit_price_xaf bigint not null check
    (negotiated_unit_price_xaf >= 0 and negotiated_unit_price_xaf <= 9000000000000),
  line_total_xaf bigint generated always as
    (quantity::bigint * negotiated_unit_price_xaf) stored,
  constraint checkout_order_lines_order_shop_fk foreign key (order_id, shop_id)
    references public.checkout_orders(id, shop_id),
  constraint checkout_order_lines_category_shop_fk foreign key (category_id, shop_id)
    references public.stock_categories(id, shop_id),
  constraint checkout_order_lines_total_limit check (line_total_xaf <= 9000000000000)
);

-- Records the SELLER'S assertion that funds have been received.
-- Never label this as payment-provider verification.
-- Seller ID and confirmed_at MUST be assigned from auth.uid() and now()
-- inside a vetted server RPC, never trusted from client JSON.
create table if not exists public.manual_payment_confirmations (
  order_id uuid primary key,
  shop_id uuid not null,
  sale_id uuid not null,
  operation_id uuid not null,
  confirmed_by uuid not null references auth.users(id),
  -- Human-readable cashier name is a receipt snapshot entered before validation,
  -- NOT proof of identity. The server must verify confirmed_by via auth.uid().
  cashier_first_name text not null
    check (char_length(cashier_first_name) between 1 and 60
       and cashier_first_name = btrim(cashier_first_name)),
  confirmed_at timestamptz not null default now(),
  method text not null check (method in ('cash', 'mobile_money', 'other')),
  external_reference text check (length(external_reference) <= 120),
  receipt_number text not null,
  amount_xaf bigint not null check (amount_xaf >= 0),
  receipt_lines jsonb not null check (jsonb_typeof(receipt_lines) = 'array'),
  constraint manual_confirmations_order_shop_fk foreign key (order_id, shop_id)
    references public.checkout_orders(id, shop_id),
  constraint manual_confirmations_sale_shop_fk foreign key (sale_id, shop_id)
    references public.sales(id, shop_id),
  constraint manual_confirmations_sale_unique unique (sale_id),
  constraint manual_confirmations_operation_unique unique (shop_id, operation_id),
  constraint manual_confirmations_receipt_unique unique (shop_id, receipt_number)
);

-- Receipt numbering must be allocated atomically in the payment RPC.
-- TEST counters are separate from REAL counters and have a TEST prefix.
-- Never generate sequential receipt numbers in the browser.
create table if not exists public.shop_receipt_counters (
  shop_id uuid not null references public.shops(id),
  receipt_year integer not null check (receipt_year between 2020 and 9999),
  is_test boolean not null default false,
  last_number bigint not null default 0 check (last_number >= 0),
  primary key (shop_id, receipt_year, is_test)
);

create index if not exists checkout_orders_shop_status_created_idx
  on public.checkout_orders(shop_id, status, created_at desc);

alter table public.checkout_orders enable row level security;
alter table public.checkout_order_lines enable row level security;
alter table public.manual_payment_confirmations enable row level security;
alter table public.shop_receipt_counters enable row level security;

-- Shop owner reads only; employee authorization and public QR submission
-- require a separately audited role model and narrow RPCs.
create policy "shop owner reads checkout orders"
  on public.checkout_orders for select to authenticated
  using (exists (select 1 from public.shops s where s.id = shop_id and s.owner_id = (select auth.uid())));
create policy "shop owner reads checkout lines"
  on public.checkout_order_lines for select to authenticated
  using (exists (select 1 from public.shops s where s.id = shop_id and s.owner_id = (select auth.uid())));
create policy "shop owner reads manual confirmations"
  on public.manual_payment_confirmations for select to authenticated
  using (exists (select 1 from public.shops s where s.id = shop_id and s.owner_id = (select auth.uid())));

revoke insert, update, delete on public.checkout_orders from anon, authenticated;
revoke insert, update, delete on public.checkout_order_lines from anon, authenticated;
revoke insert, update, delete on public.manual_payment_confirmations from anon, authenticated;
revoke insert, update, delete on public.shop_receipt_counters from anon, authenticated;
commit;

-- OPEN SECURITY/PRODUCT DECISIONS BEFORE DEPLOYMENT:
-- - Define employee-to-shop membership and seller permissions (owner-only RLS is insufficient).
-- - Public QR/social order submission needs a restricted endpoint and abuse controls.
-- - Cashier confirmation RPC must lock order AND category rows, validate totals,
--   ensure is_test matches, check available stock, decrement exactly once, and
--   insert immutable receipt + confirmation and the existing sales ledger in one transaction.
-- - Checkout lines remain the sale's category breakdown; old sale_items require products
--   and must not be used for category-only sales.
-- - A payment confirmation stores receipt_lines as a historical receipt snapshot.
-- - Confirm receipt formatting and whether payment correction needs reversal.
-- - Require and normalize cashier_first_name BEFORE confirming; store it with
--   confirmed_by on the receipt as an immutable display snapshot.
-- - Never trust client-supplied confirmed_by, confirmed_at or paid status.
-- - Never grant direct UPDATE on stock, paid orders or confirmations.
