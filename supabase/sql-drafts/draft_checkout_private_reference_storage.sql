-- DRAFT ONLY: private images attached to QR/social customer order requests.
-- Must be applied AFTER draft_checkout_manual_payment_schema.sql and
-- draft_public_order_channels.sql in a disposable Supabase test project.
-- These are NOT catalogue images, product photos, or public media.
begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('covi-order-references', 'covi-order-references', false, 320000, array['image/jpeg'])
on conflict (id) do nothing;

-- The Edge gateway uploads with the service role only, after validation and
-- anti-abuse checks; public clients receive neither object permissions nor URLs.
-- A signed-in merchant may only create a short-lived signed URL to an image
-- attached to an order from their own shop, never another shop.
create policy "shop owner reads their customers private order reference"
on storage.objects for select to authenticated
using (
  bucket_id = 'covi-order-references'
  and exists (
    select 1 from public.checkout_orders o
    join public.shops s on s.id = o.shop_id
    where s.owner_id = (select auth.uid())
      and o.reference_image_path = storage.objects.name
      and o.shop_id::text = split_part(storage.objects.name, '/', 1)
      and o.id::text = split_part(storage.objects.name, '/', 2)
  )
);

-- No INSERT/UPDATE/DELETE policies for browser users.
-- Remove abandoned objects and old reference screenshots via a separately
-- reviewed lifecycle policy once business retention is decided.
commit;
