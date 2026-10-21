-- Chat IA: quota augmenté pour conversations réelles sans permettre d'appels illimités.
-- Ne concerne que la table de quota COVI ; aucune donnée financière ou vente modifiée.
alter table public.covi_ai_hourly_quota
  drop constraint if exists covi_ai_hourly_quota_used_check;
alter table public.covi_ai_hourly_quota
  add constraint covi_ai_hourly_quota_used_check check (used between 0 and 60);

create or replace function public.covi_ai_allow_request(p_shop_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hour timestamptz := pg_catalog.date_trunc('hour', pg_catalog.now());
  v_used integer;
begin
  if (select auth.uid()) is null
     or not exists (
       select 1 from public.shops s
       where s.id = p_shop_id and s.owner_id = (select auth.uid())
     ) then
    raise exception 'Access denied' using errcode = '42501';
  end if;

  insert into public.covi_ai_hourly_quota as q (shop_id, hour_start, used)
  values (p_shop_id, v_hour, 1)
  on conflict (shop_id, hour_start)
  do update set used = q.used + 1 where q.used < 60
  returning used into v_used;
  return v_used is not null;
end;
$$;
revoke all on function public.covi_ai_allow_request(uuid) from public, anon, authenticated;
grant execute on function public.covi_ai_allow_request(uuid) to authenticated;
comment on function public.covi_ai_allow_request(uuid) is
 'Quota COVI Assistant : maximum 60 messages par heure UTC et par boutique propriétaire.';

-- Refuse qu'une autre table publique lise le quota (aucune nouvelle policy).
alter table public.covi_ai_hourly_quota enable row level security;
revoke all on public.covi_ai_hourly_quota from public, anon, authenticated;
