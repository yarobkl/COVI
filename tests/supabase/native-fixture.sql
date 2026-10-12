-- Disposable native Supabase CI fixture: use real COVI core migrations.
-- Supabase CLI already applied supabase/migrations/* to localhost.
-- Never recreate existing COVI production tables or alter production.
do $native$
begin
  if to_regclass('public.shops') is null
    or to_regclass('public.arrivals') is null
    or to_regclass('public.sales') is null
    or to_regclass('auth.users') is null then
    raise exception 'Expected real local Supabase migrations/Auth to be present';
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'shops'
  ) then
    raise exception 'The real shops owner RLS policy is missing';
  end if;
end;
$native$;
select 'PASS: Actual COVI schema and Supabase Auth are in disposable local DB' as result;
