-- Assistant IA sans demande de PIN. Les caisses partagées conservent leurs protections.
-- Enregistre le session_id signé par Supabase lorsque la caisse est ouverte.
alter table public.till_sessions add column if not exists owner_auth_session_id uuid;
alter table public.shop_cashier_tills add column if not exists owner_auth_session_id uuid;

create or replace function public.covi_ai_tag_till()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.owner_auth_session_id := public.cashier_session_id();
  return new;
end;
$$;

drop trigger if exists covi_ai_tag_till on public.till_sessions;
create trigger covi_ai_tag_till before insert on public.till_sessions
for each row execute function public.covi_ai_tag_till();

drop trigger if exists covi_ai_tag_shared_till on public.shop_cashier_tills;
create trigger covi_ai_tag_shared_till before insert on public.shop_cashier_tills
for each row execute function public.covi_ai_tag_till();

create or replace function public.covi_ai_owner_session_allowed(p_shop_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select auth.uid() is not null
   and public.cashier_session_id() is not null
   and exists (
     select 1 from public.shops s
     where s.id=p_shop_id and s.owner_id=auth.uid()
   )
   and not exists (
     select 1 from public.till_sessions t
     where t.shop_id=p_shop_id and t.opened_by=auth.uid()
       and t.closed_at is null and t.expires_at>now()
       and (t.owner_auth_session_id=public.cashier_session_id()
            or t.owner_auth_session_id is null)
   )
   and not exists (
     select 1 from public.shop_cashier_tills t
     where t.shop_id=p_shop_id and t.opened_by=auth.uid()
       and t.closed_at is null and t.expires_at>now()
       and (t.owner_auth_session_id=public.cashier_session_id()
            or t.owner_auth_session_id is null)
   )
$$;

revoke all on function public.covi_ai_tag_till() from public,anon,authenticated;
revoke all on function public.covi_ai_owner_session_allowed(uuid) from public,anon,authenticated;
grant execute on function public.covi_ai_owner_session_allowed(uuid) to authenticated;
