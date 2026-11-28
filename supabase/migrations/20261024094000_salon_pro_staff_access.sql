-- COVI Salon professionnel — comptes d'accès des collaborateurs (lot 4).
-- Même mécanisme éprouvé que le restaurant : le propriétaire crée un code à usage unique
-- (48 h, empreinte SHA-256 seulement), le collaborateur le saisit depuis SON compte COVI.
-- Les tentatives ratées sont enregistrées et limitées (5 par quart d'heure).

create function public.salon_staff_create_invite(
  p_shop uuid, p_display_name text, p_role text, p_employee uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'staff_access');
  v_code text;
  v_id uuid;
begin
  if p_display_name is null or char_length(btrim(p_display_name)) not between 1 and 80
     or p_role not in ('manager', 'stylist', 'cashier') then
    raise exception 'Invalid invitation' using errcode = '22023';
  end if;
  if p_employee is not null and not exists (
      select 1 from public.salon_staff_profiles p where p.employee_id = p_employee and p.shop_id = p_shop) then
    raise exception 'Collaborator not found' using errcode = '22023';
  end if;
  if p_role = 'stylist' and p_employee is null then
    raise exception 'A stylist account must be linked to a collaborator' using errcode = '22023';
  end if;
  if (select count(*) from public.salon_staff_invites i where i.shop_id = p_shop
      and i.expires_at > now() and i.used_at is null and i.revoked_at is null) >= 30 then
    raise exception 'Too many pending invitations' using errcode = '22023';
  end if;
  v_code := upper(replace(gen_random_uuid()::text, '-', ''));
  insert into public.salon_staff_invites (shop_id, code_digest, display_name, role, employee_id,
                                          created_by, expires_at)
  values (p_shop, sha256(convert_to('covi-salon:' || v_code, 'UTF8')), btrim(p_display_name), p_role,
          p_employee, auth.uid(), now() + interval '48 hours')
  returning id into v_id;
  perform public.salon_log(p_shop, v_role, 'staff_invite_created', v_id,
    jsonb_build_object('role', p_role));
  return jsonb_build_object('invite_id', v_id, 'code', v_code, 'display_name', btrim(p_display_name),
                            'role', p_role, 'expires_in_hours', 48);
end;
$$;

create function public.salon_staff_join(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_inv public.salon_staff_invites%rowtype;
  v_fails integer;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  perform 1 from auth.users where id = v_uid for update;
  select count(*) into v_fails from public.salon_staff_invite_attempts
  where user_id = v_uid and not successful and created_at > now() - interval '15 minutes';
  if v_fails >= 5 then return jsonb_build_object('ok', false, 'reason', 'locked'); end if;
  if p_code is null or upper(btrim(p_code)) !~ '^[A-F0-9]{32}$' then
    insert into public.salon_staff_invite_attempts (user_id, successful) values (v_uid, false);
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;
  select * into v_inv from public.salon_staff_invites
  where code_digest = sha256(convert_to('covi-salon:' || upper(btrim(p_code)), 'UTF8')) for update;
  if not found or v_inv.used_at is not null or v_inv.revoked_at is not null or v_inv.expires_at <= now()
     or exists (select 1 from public.shops s where s.id = v_inv.shop_id and s.owner_id = v_uid) then
    insert into public.salon_staff_invite_attempts (user_id, successful) values (v_uid, false);
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;
  if exists (select 1 from public.salon_staff_members
             where shop_id = v_inv.shop_id and user_id = v_uid and active) then
    insert into public.salon_staff_invite_attempts (user_id, successful) values (v_uid, false);
    return jsonb_build_object('ok', false, 'reason', 'already_member');
  end if;
  insert into public.salon_staff_members (shop_id, user_id, employee_id, display_name, role, active,
                                          disabled_at, created_by)
  values (v_inv.shop_id, v_uid, v_inv.employee_id, v_inv.display_name, v_inv.role, true, null, v_inv.created_by)
  on conflict (shop_id, user_id) do update set employee_id = excluded.employee_id,
    display_name = excluded.display_name, role = excluded.role, active = true, disabled_at = null,
    created_by = excluded.created_by;
  update public.salon_staff_invites set used_at = now(), used_by = v_uid where id = v_inv.id;
  insert into public.salon_staff_invite_attempts (user_id, successful) values (v_uid, true);
  insert into public.salon_events (shop_id, actor_id, actor_role, event_type, entity_id, details)
  values (v_inv.shop_id, v_uid, v_inv.role, 'staff_joined', v_inv.id, '{}'::jsonb);
  return jsonb_build_object('ok', true, 'shop_id', v_inv.shop_id, 'role', v_inv.role);
end;
$$;

create function public.salon_staff_my_spaces()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('shop_id', m.shop_id, 'shop_name', s.name,
      'role', m.role, 'display_name', m.display_name, 'employee_id', m.employee_id)
      order by s.name), '[]'::jsonb)
  from public.salon_staff_members m
  join public.shops s on s.id = m.shop_id and s.business_kind = 'salon'
  where m.user_id = auth.uid() and m.active
$$;

create function public.salon_staff_accounts(p_shop uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'staff_access');
begin
  return jsonb_build_object(
    'members', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'display_name', m.display_name,
        'role', m.role, 'active', m.active, 'employee_id', m.employee_id, 'created_at', m.created_at)
        order by m.active desc, m.display_name)
      from public.salon_staff_members m where m.shop_id = p_shop), '[]'::jsonb),
    'invites', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'display_name', i.display_name,
        'role', i.role, 'expires_at', i.expires_at) order by i.created_at desc)
      from public.salon_staff_invites i where i.shop_id = p_shop and i.used_at is null
        and i.revoked_at is null and i.expires_at > now()), '[]'::jsonb));
end;
$$;

create function public.salon_staff_disable(p_shop uuid, p_member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'staff_access');
begin
  update public.salon_staff_members set active = false, disabled_at = now()
  where id = p_member and shop_id = p_shop and active;
  if not found then return false; end if;
  perform public.salon_log(p_shop, v_role, 'staff_disabled', p_member, '{}'::jsonb);
  return true;
end;
$$;

create function public.salon_staff_revoke_invite(p_shop uuid, p_invite uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'staff_access');
begin
  update public.salon_staff_invites set revoked_at = now()
  where id = p_invite and shop_id = p_shop and used_at is null and revoked_at is null;
  return found;
end;
$$;

revoke all on function
  public.salon_staff_create_invite(uuid, text, text, uuid),
  public.salon_staff_join(text),
  public.salon_staff_my_spaces(),
  public.salon_staff_accounts(uuid),
  public.salon_staff_disable(uuid, uuid),
  public.salon_staff_revoke_invite(uuid, uuid)
  from public, anon;
grant execute on function
  public.salon_staff_create_invite(uuid, text, text, uuid),
  public.salon_staff_join(text),
  public.salon_staff_my_spaces(),
  public.salon_staff_accounts(uuid),
  public.salon_staff_disable(uuid, uuid),
  public.salon_staff_revoke_invite(uuid, uuid)
  to authenticated;
