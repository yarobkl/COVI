-- Personal profile photos. Files are private and isolated by authenticated user ID.
-- Applied to COVI Supabase on 2026-10-13 as migration 20261013045706.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'covi-profile-photos',
  'covi-profile-photos',
  false,
  2097152,
  array['image/jpeg']::text[]
)
on conflict (id) do nothing;

create policy "COVI users read own profile photos"
on storage.objects for select to authenticated
using (
  bucket_id = 'covi-profile-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and array_length(storage.foldername(name), 1) = 1
  and storage.extension(name) = 'jpg'
);

create policy "COVI users upload own profile photos"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'covi-profile-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and array_length(storage.foldername(name), 1) = 1
  and storage.extension(name) = 'jpg'
);

create policy "COVI users delete own profile photos"
on storage.objects for delete to authenticated
using (
  bucket_id = 'covi-profile-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and array_length(storage.foldername(name), 1) = 1
  and storage.extension(name) = 'jpg'
);
