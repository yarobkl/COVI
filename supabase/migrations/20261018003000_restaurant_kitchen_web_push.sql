-- Restaurant kitchen remote Web Push — development only, NOT applied to live Supabase.
-- Browser subscriptions are bound to authenticated shop staff; dispatch RPCs are service-only.
create table public.restaurant_kitchen_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null check(length(endpoint) between 50 and 1500),
  p256dh text not null check(length(p256dh) between 40 and 255),
  auth_secret text not null check(length(auth_secret) between 12 and 128),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_delivered_event_id bigint not null default 0 check(last_delivered_event_id>=0),
  lease_token uuid,
  lease_until timestamptz,
  next_retry_at timestamptz not null default now(),
  failures integer not null default 0 check(failures between 0 and 32),
  -- One browser endpoint belongs to only one active account/shop at a time.
  unique(endpoint)
);
create index restaurant_push_due on public.restaurant_kitchen_push_subscriptions(next_retry_at,lease_until);
create index restaurant_push_user on public.restaurant_kitchen_push_subscriptions(shop_id,user_id);
alter table public.restaurant_kitchen_push_subscriptions enable row level security;
revoke all on public.restaurant_kitchen_push_subscriptions from public,anon,authenticated;
-- There is no direct SELECT permission; endpoint and encryption keys stay private.
-- Supported push services are explicitly bounded to prevent SSRF through forged endpoints.
create function public.restaurant_push_endpoint_allowed(p_endpoint text)
returns boolean language plpgsql immutable set search_path=''
as $$
declare v_host text;
begin
 if p_endpoint is null or length(p_endpoint) not between 50 and 1500
   or p_endpoint !~ '^https://[A-Za-z0-9.-]+/[^/?#][^#]*$' then return false;end if;
 v_host:=lower(split_part(split_part(p_endpoint,'/',3),':',1));
 return v_host in ('fcm.googleapis.com','updates.push.services.mozilla.com',
  'web.push.apple.com')
  or v_host ~ '^[a-z0-9-]+[.]push[.]apple[.]com$'
  or v_host ~ '^[a-z0-9-]+[.]notify[.]windows[.]com$';
end; $$;
revoke all on function public.restaurant_push_endpoint_allowed(text) from public,anon,authenticated;
-- Registered only after explicit browser consent, one shop and one user.
create function public.restaurant_kitchen_push_register(
 p_shop uuid,p_endpoint text,p_p256dh text,p_auth text
) returns boolean language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid();v_cursor bigint;
begin
 if v_uid is null or not exists(
   select 1 from public.shops s where s.id=p_shop and s.business_kind='restaurant'
     and (s.owner_id=v_uid or exists(
       select 1 from public.restaurant_staff_members m
       where m.shop_id=p_shop and m.user_id=v_uid and m.active and m.staff_role='kitchen'
     ))
 ) then raise exception 'Access denied' using errcode='42501';end if;
 if not public.restaurant_push_endpoint_allowed(p_endpoint)
   or coalesce(p_p256dh,'') !~ '^[A-Za-z0-9_-]{40,255}$'
   or coalesce(p_auth,'') !~ '^[A-Za-z0-9_-]{12,128}$'
 then raise exception 'Unsupported or malformed browser push subscription';end if;
 select coalesce(max(id),0) into v_cursor from public.restaurant_kitchen_events
  where shop_id=p_shop;
 insert into public.restaurant_kitchen_push_subscriptions(
   shop_id,user_id,endpoint,p256dh,auth_secret,last_delivered_event_id)
 values(p_shop,v_uid,p_endpoint,p_p256dh,p_auth,v_cursor)
 on conflict(endpoint) do update
  set shop_id=excluded.shop_id,user_id=excluded.user_id,
      p256dh=excluded.p256dh,auth_secret=excluded.auth_secret,
      -- Preserve the cursor only when the same person reconnects to the same shop.
      last_delivered_event_id=case
        when restaurant_kitchen_push_subscriptions.shop_id=excluded.shop_id
         and restaurant_kitchen_push_subscriptions.user_id=excluded.user_id
        then restaurant_kitchen_push_subscriptions.last_delivered_event_id
        else excluded.last_delivered_event_id end,
      lease_token=null,lease_until=null,failures=0,next_retry_at=now(),
      updated_at=now();
 return true;
end; $$;
revoke all on function public.restaurant_kitchen_push_register(uuid,text,text,text)
 from public,anon;
grant execute on function public.restaurant_kitchen_push_register(uuid,text,text,text)
 to authenticated;

-- Logout or manual opt-out: only delete the caller's own matching endpoint.
create function public.restaurant_kitchen_push_unregister(p_shop uuid,p_endpoint text)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_count integer;
begin
 if auth.uid() is null then raise exception 'Access denied' using errcode='42501';end if;
 delete from public.restaurant_kitchen_push_subscriptions
 where shop_id=p_shop and user_id=auth.uid() and endpoint=p_endpoint;
 get diagnostics v_count=row_count;
 return v_count>0;
end; $$;
revoke all on function public.restaurant_kitchen_push_unregister(uuid,text)
 from public,anon;
grant execute on function public.restaurant_kitchen_push_unregister(uuid,text)
 to authenticated;

-- Revoke kitchen push when an employee is disabled or leaves the kitchen role.
create function public.restaurant_kitchen_push_revoke_staff()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 if old.staff_role='kitchen' and (not new.active or new.staff_role<>'kitchen') then
  delete from public.restaurant_kitchen_push_subscriptions
   where shop_id=new.shop_id and user_id=new.user_id;
 end if;
 return new;
end; $$;
revoke all on function public.restaurant_kitchen_push_revoke_staff()
 from public,anon,authenticated;
create trigger restaurant_kitchen_push_staff_revoked
 after update of active,staff_role on public.restaurant_staff_members
 for each row when (old.staff_role='kitchen' and (new.active=false or new.staff_role<>'kitchen'))
 execute function public.restaurant_kitchen_push_revoke_staff();

-- Service-only leasing of eligible events; stale leases expire and are retried.
-- Never send client names, prices, orders, or payment details in notifications.
create function public.restaurant_kitchen_push_claim(p_limit integer default 25)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_sub record;v_max bigint;v_count integer;v_lease uuid;v_out jsonb:='[]'::jsonb;
begin
 if auth.role() is distinct from 'service_role' then
   raise exception 'Service role required' using errcode='42501';end if;
 if p_limit is null or p_limit<1 or p_limit>50 then
   raise exception 'Invalid batch size';end if;
 for v_sub in
   select p.* from public.restaurant_kitchen_push_subscriptions p
   join public.shops s on s.id=p.shop_id and s.business_kind='restaurant'
   where p.next_retry_at<=now()
    and (p.lease_until is null or p.lease_until<now())
    and (s.owner_id=p.user_id or exists(
     select 1 from public.restaurant_staff_members m
     where m.shop_id=p.shop_id and m.user_id=p.user_id
       and m.active and m.staff_role='kitchen'))
    and exists (
      select 1 from public.restaurant_kitchen_events e
       join public.restaurant_session_lines l
         on l.shop_id=e.shop_id and l.id=e.line_id
       join public.restaurant_table_sessions ss
         on ss.shop_id=e.shop_id and ss.id=e.session_id
      where e.shop_id=p.shop_id and e.id>p.last_delivered_event_id
        and ss.status='submitted' and l.status='ordered'
    )
   order by p.next_retry_at,p.created_at,p.id
   for update of p skip locked
   limit p_limit
 loop
   select coalesce(max(e.id),0),count(*) into v_max,v_count
   from public.restaurant_kitchen_events e
     join public.restaurant_session_lines l on l.shop_id=e.shop_id and l.id=e.line_id
     join public.restaurant_table_sessions ss
       on ss.shop_id=e.shop_id and ss.id=e.session_id
   where e.shop_id=v_sub.shop_id and e.id>v_sub.last_delivered_event_id
     and ss.status='submitted' and l.status='ordered';
   if v_count=0 then continue;end if;
   v_lease:=gen_random_uuid();
   update public.restaurant_kitchen_push_subscriptions
    set lease_token=v_lease,lease_until=now()+interval '90 seconds'
    where id=v_sub.id;
   v_out:=v_out||jsonb_build_array(jsonb_build_object(
     'id',v_sub.id,'lease',v_lease,'through',v_max::text,
     'count',least(v_count,999),'endpoint',v_sub.endpoint,
     'p256dh',v_sub.p256dh,'auth',v_sub.auth_secret));
 end loop;
 return v_out;
end; $$;
revoke all on function public.restaurant_kitchen_push_claim(integer)
 from public,anon,authenticated;
grant execute on function public.restaurant_kitchen_push_claim(integer) to service_role;

create function public.restaurant_kitchen_push_finish(
 p_id uuid,p_lease uuid,p_through text,p_outcome text
) returns boolean language plpgsql security definer set search_path=''
as $$
declare v_row public.restaurant_kitchen_push_subscriptions%rowtype;v_cursor bigint;
begin
 if auth.role() is distinct from 'service_role' then
  raise exception 'Service role required' using errcode='42501';end if;
 if p_through is null or p_through !~ '^[1-9][0-9]{0,18}$'
   or p_outcome not in ('sent','retry','gone') then
   raise exception 'Invalid delivery outcome';end if;
 v_cursor:=p_through::bigint;
 select * into v_row from public.restaurant_kitchen_push_subscriptions
   where id=p_id and lease_token=p_lease for update;
 if not found or v_row.lease_until<now() then return false;end if;
 if p_outcome='gone' then
  delete from public.restaurant_kitchen_push_subscriptions where id=p_id;
 elsif p_outcome='sent' then
  if v_cursor>coalesce((select max(id) from public.restaurant_kitchen_events
    where shop_id=v_row.shop_id),0) then
    raise exception 'Invalid delivery cursor';end if;
  update public.restaurant_kitchen_push_subscriptions set
   last_delivered_event_id=greatest(last_delivered_event_id,v_cursor),
   failures=0,next_retry_at=now(),lease_until=null,lease_token=null
   where id=p_id;
 else
  update public.restaurant_kitchen_push_subscriptions set
   failures=least(failures+1,32),
   next_retry_at=now()+ make_interval(secs=>least(3600,
     (power(2,least(failures,10))::integer)*30)),
   lease_until=null,lease_token=null where id=p_id;
 end if;
 return true;
end; $$;
revoke all on function public.restaurant_kitchen_push_finish(uuid,uuid,text,text)
 from public,anon,authenticated;
grant execute on function public.restaurant_kitchen_push_finish(uuid,uuid,text,text)
 to service_role;
