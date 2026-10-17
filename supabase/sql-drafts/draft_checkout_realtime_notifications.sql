-- COVI draft / isolated test only. Do not run in production until checkout
-- tables, tenant isolation and checkout change subscriptions are audited.
-- Realtime event payloads are NOT used as authorization or source of truth.
-- The cashier refreshes its order inbox through owner-authorized SQL RPC.
-- The app also polls every 15 seconds if Realtime is disconnected.
--
-- Prerequisites:
-- 1. public.checkout_orders exists, and its SELECT RLS is owner-only.
-- 2. Supabase Realtime service is configured for postgres_changes.
-- 3. Review publication settings for the deployment environment.
--
-- Realtime stream table changes are delivered ONLY to subscribers who pass
-- the table's SELECT policies. Never create public SELECT grants.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'checkout_orders'
    ) then
    alter publication supabase_realtime add table public.checkout_orders;
  end if;
end;
$$;
