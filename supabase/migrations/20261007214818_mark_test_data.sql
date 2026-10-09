alter table public.arrivals add column if not exists is_test boolean not null default false;
alter table public.products add column if not exists is_test boolean not null default false;
alter table public.sales add column if not exists is_test boolean not null default false;
alter table public.shop_expenses add column if not exists is_test boolean not null default false;
create index if not exists arrivals_shop_test_idx on public.arrivals (shop_id, is_test);
create index if not exists products_shop_test_idx on public.products (shop_id, is_test);
create index if not exists sales_shop_test_sold_at_idx on public.sales (shop_id, is_test, sold_at desc);
create index if not exists expenses_shop_test_date_idx on public.shop_expenses (shop_id, is_test, expense_date desc);
