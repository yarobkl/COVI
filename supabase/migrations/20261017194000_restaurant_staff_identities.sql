-- COVI Restaurant — distinct authenticated staff identities and privileges.
-- Staged migration only: never apply to the production project without approval.
-- Employees (including their salaries) remain private records, NOT login permissions.
create table public.restaurant_staff_members (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null check(length(btrim(display_name)) between 1 and 80),
  staff_role text not null check(staff_role in ('waiter','kitchen','cashier')),
  active boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  disabled_at timestamptz,
  unique(shop_id,user_id),
  constraint staff_active_consistent check(active or disabled_at is not null)
);
create index restaurant_staff_by_user on public.restaurant_staff_members(user_id,active);

create table public.restaurant_staff_invites (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  code_digest bytea not null unique,
  display_name text not null check(length(btrim(display_name)) between 1 and 80),
  staff_role text not null check(staff_role in ('waiter','kitchen','cashier')),
  created_by uuid not null references auth.users(id),
  expires_at timestamptz not null,
  used_by uuid references auth.users(id),
  used_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);
create index restaurant_invites_pending on public.restaurant_staff_invites(shop_id,expires_at)
 where used_at is null and revoked_at is null;

create table public.restaurant_staff_invite_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  successful boolean not null,
  created_at timestamptz not null default now()
);
create index restaurant_staff_attempts_by_user
  on public.restaurant_staff_invite_attempts(user_id,created_at desc);

-- Action audit is private to owner; staff can only append via vetted RPC logic.
create table public.restaurant_staff_events (
  id bigint generated always as identity primary key,
  shop_id uuid not null references public.shops(id) on delete cascade,
  actor_user_id uuid not null references auth.users(id),
  session_id uuid,
  line_id uuid,
  event_type text not null check(event_type in (
    'member_joined','member_disabled','table_opened','group_code_issued',
    'line_added','line_served','payment_confirmed'
  )),
  details jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  foreign key(shop_id,session_id) references public.restaurant_table_sessions(shop_id,id),
  foreign key(shop_id,line_id) references public.restaurant_session_lines(shop_id,id)
);
create index restaurant_staff_events_by_shop
  on public.restaurant_staff_events(shop_id,occurred_at desc);
create index restaurant_staff_events_by_session
  on public.restaurant_staff_events(shop_id,session_id,occurred_at desc);

do $$
declare t text;
begin
 foreach t in array array[
  'restaurant_staff_members','restaurant_staff_invites',
  'restaurant_staff_invite_attempts','restaurant_staff_events'
 ] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
 end loop;
end $$;

grant select on public.restaurant_staff_members,public.restaurant_staff_events to authenticated;
create policy staff_directory_owner_read on public.restaurant_staff_members
 for select to authenticated using(exists(
  select 1 from public.shops s where s.id=shop_id
    and s.owner_id=(select auth.uid()) and s.business_kind='restaurant'
 ));
create policy staff_events_owner_read on public.restaurant_staff_events
 for select to authenticated using(exists(
  select 1 from public.shops s where s.id=shop_id
    and s.owner_id=(select auth.uid()) and s.business_kind='restaurant'
 ));

create function public.restaurant_staff_allowed(p_shop uuid,p_action text)
returns boolean language sql stable security definer set search_path=''
as $$
 select exists(select 1 from public.shops s
   where s.id=p_shop and s.owner_id=auth.uid() and s.business_kind='restaurant')
 or exists(select 1 from public.restaurant_staff_members m
  join public.shops s on s.id=m.shop_id and s.business_kind='restaurant'
  where m.shop_id=p_shop and m.user_id=auth.uid() and m.active
   and (
    p_action='view_room'
    or (p_action in ('open_table','issue_group_code','staff_add_item') and m.staff_role='waiter')
    or (p_action='mark_served' and m.staff_role in ('waiter','kitchen'))
    or (p_action='capture_cash' and m.staff_role='cashier')
   ));
$$;
revoke all on function public.restaurant_staff_allowed(uuid,text) from public,anon,authenticated;
-- Internal definer methods can call this function; browser cannot arbitrarily probe roles.

create function public.restaurant_staff_my_spaces()
returns table(shop_id uuid,shop_name text,staff_role text,display_name text)
language sql stable security definer set search_path=''
as $$
 select m.shop_id,s.name,m.staff_role,m.display_name
 from public.restaurant_staff_members m
 join public.shops s on s.id=m.shop_id and s.business_kind='restaurant'
 where m.user_id=auth.uid() and m.active
 order by s.name,m.shop_id;
$$;
revoke all on function public.restaurant_staff_my_spaces() from public,anon;
grant execute on function public.restaurant_staff_my_spaces() to authenticated;

create function public.restaurant_staff_create_invite(
 p_shop uuid,p_name text,p_role text
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_code text;v_invite uuid;
begin
 if auth.uid() is null or not exists(
  select 1 from public.shops s where s.id=p_shop and s.owner_id=auth.uid()
    and s.business_kind='restaurant'
 ) then raise exception 'Access denied' using errcode='42501'; end if;
 if p_name is null or length(btrim(p_name)) not between 1 and 80
    or p_role not in ('waiter','kitchen','cashier') then
   raise exception 'Invalid staff invitation'; end if;
 if (select count(*) from public.restaurant_staff_invites i
    where i.shop_id=p_shop and i.expires_at>now()
    and i.used_at is null and i.revoked_at is null)>=30 then
    raise exception 'Too many pending invitations'; end if;
 v_code:=upper(replace(gen_random_uuid()::text,'-',''));
 insert into public.restaurant_staff_invites(
  shop_id,code_digest,display_name,staff_role,created_by,expires_at
 ) values(p_shop,sha256(convert_to(v_code,'UTF8')),btrim(p_name),p_role,
  auth.uid(),now()+interval '48 hours') returning id into v_invite;
 return jsonb_build_object('inviteId',v_invite,'code',v_code,
   'displayName',btrim(p_name),'staffRole',p_role);
end; $$;
revoke all on function public.restaurant_staff_create_invite(uuid,text,text)
 from public,anon;
grant execute on function public.restaurant_staff_create_invite(uuid,text,text)
 to authenticated;

-- No error raising after attempt logging: failed guesses are committed and rate-limited.
create function public.restaurant_staff_join(p_code text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid();v_invite public.restaurant_staff_invites%rowtype;
        v_count integer;v_previous public.restaurant_staff_members%rowtype;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 -- Serialize attempts from the same account, even if many simultaneous requests.
 perform 1 from auth.users where id=v_uid for update;
 select count(*) into v_count from public.restaurant_staff_invite_attempts
  where user_id=v_uid and not successful and created_at>now()-interval '15 minutes';
 if v_count>=5 then return jsonb_build_object('ok',false,'reason','locked'); end if;
 if p_code is null or p_code !~ '^[A-F0-9]{32}$' then
  insert into public.restaurant_staff_invite_attempts(user_id,successful) values(v_uid,false);
  return jsonb_build_object('ok',false,'reason','invalid');
 end if;
 select * into v_invite from public.restaurant_staff_invites
 where code_digest=sha256(convert_to(p_code,'UTF8'))
 for update;
 if not found or v_invite.used_at is not null or v_invite.revoked_at is not null
   or v_invite.expires_at<=now()
   or exists(select 1 from public.shops s where s.id=v_invite.shop_id
      and s.owner_id=v_uid)
 then
  insert into public.restaurant_staff_invite_attempts(user_id,successful) values(v_uid,false);
  return jsonb_build_object('ok',false,'reason','invalid');
 end if;
 select * into v_previous from public.restaurant_staff_members
 where shop_id=v_invite.shop_id and user_id=v_uid for update;
 if found and v_previous.active then
  insert into public.restaurant_staff_invite_attempts(user_id,successful) values(v_uid,false);
  return jsonb_build_object('ok',false,'reason','already_member');
 end if;
 insert into public.restaurant_staff_members(
  shop_id,user_id,display_name,staff_role,active,disabled_at,created_by
 ) values(v_invite.shop_id,v_uid,v_invite.display_name,v_invite.staff_role,true,null,v_invite.created_by)
 on conflict(shop_id,user_id) do update
  set display_name=excluded.display_name,staff_role=excluded.staff_role,
      active=true,disabled_at=null,created_by=excluded.created_by;
 update public.restaurant_staff_invites
  set used_at=now(),used_by=v_uid where id=v_invite.id;
 insert into public.restaurant_staff_invite_attempts(user_id,successful) values(v_uid,true);
 insert into public.restaurant_staff_events(shop_id,actor_user_id,event_type,details)
 values(v_invite.shop_id,v_uid,'member_joined',
  jsonb_build_object('role',v_invite.staff_role));
 return jsonb_build_object('ok',true,'shopId',v_invite.shop_id,
   'staffRole',v_invite.staff_role);
end; $$;
revoke all on function public.restaurant_staff_join(text) from public,anon;
grant execute on function public.restaurant_staff_join(text) to authenticated;

create function public.restaurant_staff_disable(p_shop uuid,p_member uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_user uuid;
begin
 if auth.uid() is null or not exists(select 1 from public.shops s
  where s.id=p_shop and s.owner_id=auth.uid() and s.business_kind='restaurant')
 then raise exception 'Access denied' using errcode='42501'; end if;
 update public.restaurant_staff_members set active=false,disabled_at=now()
 where shop_id=p_shop and id=p_member and active
 returning user_id into v_user;
 if v_user is null then return false; end if;
 insert into public.restaurant_staff_events(shop_id,actor_user_id,event_type,details)
 values(p_shop,auth.uid(),'member_disabled',jsonb_build_object('memberId',p_member));
 return true;
end; $$;
revoke all on function public.restaurant_staff_disable(uuid,uuid) from public,anon;
grant execute on function public.restaurant_staff_disable(uuid,uuid) to authenticated;

create function public.restaurant_staff_pending_invites(p_shop uuid)
returns table(id uuid,display_name text,staff_role text,expires_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$
begin
 if auth.uid() is null or not exists(select 1 from public.shops s
  where s.id=p_shop and s.owner_id=auth.uid() and s.business_kind='restaurant')
 then raise exception 'Access denied' using errcode='42501'; end if;
 return query select i.id,i.display_name,i.staff_role,i.expires_at
  from public.restaurant_staff_invites i
  where i.shop_id=p_shop and i.used_at is null
    and i.revoked_at is null and i.expires_at>now()
  order by i.created_at desc;
end; $$;
revoke all on function public.restaurant_staff_pending_invites(uuid) from public,anon;
grant execute on function public.restaurant_staff_pending_invites(uuid) to authenticated;

create function public.restaurant_staff_revoke_invite(p_shop uuid,p_invite uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
 if auth.uid() is null or not exists(select 1 from public.shops s
  where s.id=p_shop and s.owner_id=auth.uid() and s.business_kind='restaurant')
 then raise exception 'Access denied' using errcode='42501'; end if;
 update public.restaurant_staff_invites set revoked_at=now()
 where id=p_invite and shop_id=p_shop and used_at is null and revoked_at is null
 returning id into v_id;
 return v_id is not null;
end; $$;
revoke all on function public.restaurant_staff_revoke_invite(uuid,uuid) from public,anon;
grant execute on function public.restaurant_staff_revoke_invite(uuid,uuid) to authenticated;
