-- Assistant COVI : accès contrôlé aux propriétaires et comptes collaborateurs.
-- Les collaborateurs reçoivent uniquement le contexte produit, jamais les chiffres du propriétaire.
create or replace function public.covi_ai_shop_context(p_shop_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_shop public.shops;
begin
  if v_uid is null then return null; end if;
  select * into v_shop from public.shops s
  where s.id = p_shop_id
    and (
      s.owner_id = v_uid
      or exists (select 1 from public.shop_members m where m.shop_id = s.id and m.user_id = v_uid and m.active)
      or exists (select 1 from public.restaurant_staff_members m where m.shop_id = s.id and m.user_id = v_uid and m.active)
      or exists (select 1 from public.salon_staff_members m where m.shop_id = s.id and m.user_id = v_uid and m.active)
    );
  if not found then return null; end if;
  return jsonb_build_object(
    'id', v_shop.id,
    'name', v_shop.name,
    'currency', v_shop.currency,
    'business_kind', v_shop.business_kind,
    'owner_id', v_shop.owner_id
  );
end;
$function$;
revoke all on function public.covi_ai_shop_context(uuid) from public, anon;
grant execute on function public.covi_ai_shop_context(uuid) to authenticated;

create or replace function public.covi_ai_allow_request(p_shop_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_hour timestamptz := date_trunc('hour', now());
  v_used integer;
begin
  if v_uid is null or public.covi_ai_shop_context(p_shop_id) is null then
    raise exception 'Access denied' using errcode = '42501';
  end if;
  insert into public.covi_ai_hourly_quota as q (shop_id, hour_start, used)
  values (p_shop_id, v_hour, 1)
  on conflict (shop_id, hour_start)
  do update set used = q.used + 1 where q.used < 60
  returning used into v_used;
  return v_used is not null;
end;
$function$;
revoke all on function public.covi_ai_allow_request(uuid) from public, anon;
grant execute on function public.covi_ai_allow_request(uuid) to authenticated;
