drop policy if exists "COVI owners read product images" on storage.objects;
drop policy if exists "COVI owners upload product images" on storage.objects;
drop policy if exists "COVI owners update product images" on storage.objects;
drop policy if exists "COVI owners delete product images" on storage.objects;

create policy "COVI owners read product images" on storage.objects for select to authenticated using (bucket_id = 'covi-product-images' and exists (select 1 from public.shops as shop where shop.id::text = (storage.foldername(storage.objects.name))[1] and shop.owner_id = (select auth.uid())));
create policy "COVI owners upload product images" on storage.objects for insert to authenticated with check (bucket_id = 'covi-product-images' and exists (select 1 from public.shops as shop where shop.id::text = (storage.foldername(storage.objects.name))[1] and shop.owner_id = (select auth.uid())));
create policy "COVI owners update product images" on storage.objects for update to authenticated using (bucket_id = 'covi-product-images' and exists (select 1 from public.shops as shop where shop.id::text = (storage.foldername(storage.objects.name))[1] and shop.owner_id = (select auth.uid()))) with check (bucket_id = 'covi-product-images' and exists (select 1 from public.shops as shop where shop.id::text = (storage.foldername(storage.objects.name))[1] and shop.owner_id = (select auth.uid())));
create policy "COVI owners delete product images" on storage.objects for delete to authenticated using (bucket_id = 'covi-product-images' and exists (select 1 from public.shops as shop where shop.id::text = (storage.foldername(storage.objects.name))[1] and shop.owner_id = (select auth.uid())));
