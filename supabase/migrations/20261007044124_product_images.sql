alter table public.products
  add column if not exists image_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('covi-product-images', 'covi-product-images', false, 5242880, array['image/jpeg','image/png','image/webp']::text[])
on conflict (id) do nothing;

create policy "COVI owners read product images"
on storage.objects for select to authenticated
using (
  bucket_id = 'covi-product-images'
  and exists (
    select 1 from public.shops s
    where s.id::text = (storage.foldername(name))[1]
      and s.owner_id = (select auth.uid())
  )
);

create policy "COVI owners upload product images"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'covi-product-images'
  and exists (
    select 1 from public.shops s
    where s.id::text = (storage.foldername(name))[1]
      and s.owner_id = (select auth.uid())
  )
);

create policy "COVI owners update product images"
on storage.objects for update to authenticated
using (
  bucket_id = 'covi-product-images'
  and exists (
    select 1 from public.shops s
    where s.id::text = (storage.foldername(name))[1]
      and s.owner_id = (select auth.uid())
  )
)
with check (
  bucket_id = 'covi-product-images'
  and exists (
    select 1 from public.shops s
    where s.id::text = (storage.foldername(name))[1]
      and s.owner_id = (select auth.uid())
  )
);

create policy "COVI owners delete product images"
on storage.objects for delete to authenticated
using (
  bucket_id = 'covi-product-images'
  and exists (
    select 1 from public.shops s
    where s.id::text = (storage.foldername(name))[1]
      and s.owner_id = (select auth.uid())
  )
);
