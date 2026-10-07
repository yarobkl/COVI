alter table public.arrivals add column if not exists is_test boolean not null default false;
alter table public.products add column if not exists is_test boolean not null default false;
alter table public.sales add column if not exists is_test boolean not null default false;
alter table public.shop_expenses add column if not exists is_test boolean not null default false;

