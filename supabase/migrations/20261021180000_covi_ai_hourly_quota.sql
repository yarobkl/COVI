-- Quota persistant pour les appels IA, par boutique et heure UTC.
-- La fonction ne fait aucune écriture dans les ventes, paiements ou stocks.
create table public.covi_ai_hourly_quota (
  shop_id uuid not null references public.shops(id) on delete cascade,
  hour_start timestamptz not null,
  used integer not null default 0 check (used between 0 and 12),
  primary key (shop_id, hour_start)
);
alter table public.covi_ai_hourly_quota enable row level security;
revoke all on public.covi_ai_hourly_quota from public, anon, authenticated;

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

  -- ON CONFLICT sérialise les appels concurrents: impossible de dépasser le quota.
  insert into public.covi_ai_hourly_quota as q (shop_id, hour_start, used)
  values (p_shop_id, v_hour, 1)
  on conflict (shop_id, hour_start)
  do update set used = q.used + 1 where q.used < 12
  returning used into v_used;
  return v_used is not null;
end;
$$;
revoke all on function public.covi_ai_allow_request(uuid) from public, anon, authenticated;
grant execute on function public.covi_ai_allow_request(uuid) to authenticated;

comment on function public.covi_ai_allow_request(uuid) is
  'Quota IA : maximum 12 demandes par heure UTC pour une boutique dont auth.uid() est propriétaire.';
