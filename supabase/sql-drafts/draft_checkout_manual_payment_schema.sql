-- COVI DRAFT: omnichannel orders and manual cashier payment confirmation.
-- NOT APPLIED. Review with existing shops/users schema before executing.
-- Depends on draft_category_stock_schema.sql.
-- No payment provider integration: payment is received externally, then
-- a server-side authorized cashier/owner records their manual confirmation.
begin;

create table if not exists public.checkout_orders (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id),
  guest_tracking_token uuid not null default gen_random_uuid() unique,
  reference_image_path text check (
    reference_image_path is null or
    reference_image_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/reference[.]jpg$'
