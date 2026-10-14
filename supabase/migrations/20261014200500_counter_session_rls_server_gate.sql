-- COVI secure shared counter: owner stays signed in; their JWT is restricted
-- SERVER-SIDE while this Supabase Auth session is in counter mode.
-- No customer rows are deleted or changed. Do not apply to production
-- before JWT-signed end-to-end tests and an explicit release review.

create table if not exists public.counter_device_locks (
  auth_session_id uuid primary key,
  shop_id uuid not null references public.shops(id) on delete cascade,
  owner_id uuid not null references auth.users(id),
  member_id uuid references public.shop_members(id),
  till_session_id uuid references public.till_sessions(id),
  started_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  closed_at timestamptz
);
create index if not exists counter_device_locks_owner_idx
  on public.counter_device_locks(owner_id, closed_at);
alter table public.counter_device_locks enable row level security;
revoke all on public.counter_device_locks from public, anon, authenticated;

-- A session id is taken ONLY from the server-provided, signed JWT claims.
-- In local SQL fixtures PostgREST's old per-claim GUC is used as fallback.
create or replace function public.counter_auth_session_id()
returns uuid language sql stable set search_path to ''
as $$
  select coalesce(
    nullif(nullif(pg_catalog.current_setting('request.jwt.claims', true), '')::jsonb
      ->> 'session_id', '')::uuid,
    nullif(pg_catalog.current_setting('request.jwt.claim.session_id', true), '')::uuid
  )
$$;

-- SECDEF bypasses the table RLS intentionally; no raw table rows are returned.
create or replace function public.counter_lock_active()
returns boolean language sql stable security definer set search_path to ''
as $$
  select coalesce(
    auth.uid() is not null and public.counter_auth_session_id() is not null and
    exists (
      select 1 from public.counter_device_locks l
      where l.auth_session_id = public.counter_auth_session_id()
        and l.owner_id = auth.uid() and l.closed_at is null
    ), false)
$$;

-- One restrictive rule is ANDed with every existing permissive policy.
-- A locked owner JWT is limited to products and selected-cashier sales.
create or replace function public.counter_row_allowed(
  p_table text, p_shop_id uuid, p_seller_id uuid default null)
returns boolean language plpgsql stable security definer set search_path to ''
as $$
declare
  v_lock public.counter_device_locks%rowtype;
  v_member public.shop_members%rowtype;
begin
  if auth.uid() is null then return false; end if;
  if public.counter_auth_session_id() is null then return true; end if;
  select * into v_lock from public.counter_device_locks l
  where l.auth_session_id = public.counter_auth_session_id()
    and l.owner_id = auth.uid() and l.closed_at is null;
  if not found then return true; end if;
  if p_shop_id is distinct from v_lock.shop_id then return false; end if;
  if p_table = 'shop' then return true; end if;
  if v_lock.member_id is null then return false; end if;
  select * into v_member from public.shop_members m
  where m.id = v_lock.member_id and m.shop_id = v_lock.shop_id and m.active;
  if not found then return false; end if;
  if p_table = 'products' then return true; end if;
  if p_table = 'sales' then
    return v_member.can_view_shop_sales or p_seller_id = v_member.user_id;
  end if;
  return false;
end;
$$;

create or replace function public.counter_sale_item_allowed(p_sale_id uuid)
returns boolean language sql stable security definer set search_path to ''
as $$
  select coalesce(
    (select public.counter_row_allowed('sales', s.shop_id, s.seller_id)
     from public.sales s where s.id = p_sale_id), false)
$$;

-- Reading shop metadata is needed by AuthGate on refresh; no edits are allowed.
create policy counter_shops_read on public.shops as restrictive for select
  to authenticated using (public.counter_row_allowed('shop', id));
create policy counter_shops_insert on public.shops as restrictive for insert
  to authenticated with check (not public.counter_lock_active());
create policy counter_shops_update on public.shops as restrictive for update
  to authenticated using (not public.counter_lock_active())
  with check (not public.counter_lock_active());
create policy counter_shops_delete on public.shops as restrictive for delete
  to authenticated using (not public.counter_lock_active());

create policy counter_products_read on public.products as restrictive for select
  to authenticated using (public.counter_row_allowed('products', shop_id));
create policy counter_products_insert on public.products as restrictive for insert
  to authenticated with check (not public.counter_lock_active());
create policy counter_products_update on public.products as restrictive for update
  to authenticated using (not public.counter_lock_active())
  with check (not public.counter_lock_active());
create policy counter_products_delete on public.products as restrictive for delete
  to authenticated using (not public.counter_lock_active());

create policy counter_sales_read on public.sales as restrictive for select
  to authenticated using (public.counter_row_allowed('sales', shop_id, seller_id));
create policy counter_sale_items_read on public.sale_items as restrictive for select
  to authenticated using (public.counter_sale_item_allowed(sale_id));

create policy counter_arrivals_select on public.arrivals as restrictive for select
  to authenticated using (not public.counter_lock_active());
create policy counter_arrivals_insert on public.arrivals as restrictive for insert
  to authenticated with check (not public.counter_lock_active());
create policy counter_arrivals_update on public.arrivals as restrictive for update
  to authenticated using (not public.counter_lock_active())
  with check (not public.counter_lock_active());
create policy counter_arrivals_delete on public.arrivals as restrictive for delete
  to authenticated using (not public.counter_lock_active());
create policy counter_expenses_select on public.shop_expenses as restrictive for select
  to authenticated using (not public.counter_lock_active());
create policy counter_expenses_insert on public.shop_expenses as restrictive for insert
  to authenticated with check (not public.counter_lock_active());
create policy counter_expenses_update on public.shop_expenses as restrictive for update
  to authenticated using (not public.counter_lock_active())
  with check (not public.counter_lock_active());
create policy counter_expenses_delete on public.shop_expenses as restrictive for delete
  to authenticated using (not public.counter_lock_active());
create policy counter_team_select on public.shop_members as restrictive for select
  to authenticated using (not public.counter_lock_active());
create policy counter_team_insert on public.shop_members as restrictive for insert
  to authenticated with check (not public.counter_lock_active());
create policy counter_team_update on public.shop_members as restrictive for update
  to authenticated using (not public.counter_lock_active())
  with check (not public.counter_lock_active());
create policy counter_team_delete on public.shop_members as restrictive for delete
  to authenticated using (not public.counter_lock_active());
create policy counter_audit_select on public.shop_audit_log as restrictive for select
  to authenticated using (not public.counter_lock_active());
create policy counter_audit_insert on public.shop_audit_log as restrictive for insert
  to authenticated with check (not public.counter_lock_active());
create policy counter_audit_update on public.shop_audit_log as restrictive for update
  to authenticated using (not public.counter_lock_active())
  with check (not public.counter_lock_active());
create policy counter_audit_delete on public.shop_audit_log as restrictive for delete
  to authenticated using (not public.counter_lock_active());

-- All owner-only SECURITY DEFINER operations must enforce this guard.
create or replace function public.assert_shop_owner(p_shop_id uuid)
returns uuid language plpgsql stable security definer set search_path to ''
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if public.counter_lock_active() then
    raise exception 'Owner privileges locked for this till session' using errcode = '42501';
  end if;
  if p_shop_id is null or not exists (
    select 1 from public.shops s where s.id = p_shop_id and s.owner_id = v_uid
  ) then
    raise exception 'Shop not found' using errcode = '42501';
  end if;
  return v_uid;
end;
$$;

-- Direct owner/supervisor queries call shop_role or has_shop_permission.
create or replace function public.shop_role(p_shop_id uuid)
returns text language sql stable security definer set search_path to ''
as $$
  select case
    when public.counter_lock_active() then null::text
    when exists (select 1 from public.shops s
                 where s.id = p_shop_id and s.owner_id = auth.uid()) then 'owner'
    when exists (select 1 from public.shop_members m
                 where m.shop_id = p_shop_id and m.user_id = auth.uid() and m.active)
      then 'cashier'
  end
$$;

create or replace function public.has_shop_permission(p_shop_id uuid, p_permission text)
returns boolean language sql stable security definer set search_path to ''
as $$
  select case
    when public.counter_lock_active() then
      p_permission in ('view_products','view_own_sales','sell')
      and exists (
        select 1 from public.counter_device_locks l
        join public.shop_members m on m.id = l.member_id
        where l.auth_session_id = public.counter_auth_session_id()
          and l.owner_id = auth.uid() and l.closed_at is null
          and l.shop_id = p_shop_id and m.active)
    else coalesce(
      (exists (select 1 from public.shops s
               where s.id = p_shop_id and s.owner_id = auth.uid())
        and p_permission in ('manage','sell','view_products','view_own_sales','view_shop_sales'))
      or exists (
        select 1 from public.shop_members m
        where m.shop_id = p_shop_id and m.user_id = auth.uid() and m.active
          and (p_permission in ('view_products','view_own_sales')
               or (p_permission = 'view_shop_sales' and m.can_view_shop_sales)
               or (p_permission = 'sell' and public.cashier_pin_unlocked(m.id))))
    ,false)
  end
$$;

create or replace function public.assert_can_sell(p_shop_id uuid)
returns boolean language plpgsql stable security definer set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_shop_id is null then
    raise exception 'Shop not found' using errcode = '42501';
  end if;
  if public.counter_lock_active() then
    if exists (select 1 from public.counter_device_locks l
      join public.shop_members m on m.id = l.member_id
      where l.auth_session_id = public.counter_auth_session_id()
        and l.owner_id = v_uid and l.shop_id = p_shop_id
        and l.closed_at is null and l.till_session_id is not null and m.active)
    then return true; end if;
    raise exception 'Cashier PIN required' using errcode = '42501';
  end if;
  if exists (select 1 from public.shops s where s.id = p_shop_id and s.owner_id = v_uid)
    then return true; end if;
  if exists (select 1 from public.shop_members m
             where m.shop_id = p_shop_id and m.user_id = v_uid and m.active)
    then return false; end if;
  raise exception 'Shop not found' using errcode = '42501';
end;
$$;

-- During counter mode, the server insists on both the active selected
-- member AND their exact current till token. No owner sale or discounts.
create or replace function public.sale_seller(
  p_shop_id uuid, p_till_session text,
  out seller_id uuid, out max_discount_pct numeric)
returns record language plpgsql security definer set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  v_owner boolean;
  v_member public.shop_members%rowtype;
  v_lock public.counter_device_locks%rowtype;
  v_till_id uuid;
begin
  v_owner := exists (select 1 from public.shops s where s.id=p_shop_id and s.owner_id=v_uid);
  if public.counter_lock_active() then
    select * into v_lock from public.counter_device_locks l
    where l.auth_session_id=public.counter_auth_session_id()
      and l.owner_id=v_uid and l.shop_id=p_shop_id and l.closed_at is null;
    if not found or p_till_session is null or v_lock.member_id is null then
      raise exception 'Cashier PIN required' using errcode='42501';
    end if;
    v_member := public.till_session_member(p_shop_id,p_till_session);
    select id into v_till_id from public.till_sessions
    where shop_id=p_shop_id and member_id=v_member.id
      and token_hash=pg_catalog.sha256(pg_catalog.convert_to('covi-till:' || p_till_session,'UTF8'))
      and closed_at is null;
    if v_member.id is distinct from v_lock.member_id
       or v_till_id is distinct from v_lock.till_session_id then
      raise exception 'Wrong active cashier' using errcode='42501';
    end if;
    seller_id:=v_member.user_id;
    max_discount_pct:=v_member.max_discount_pct;
    return;
  end if;
  if p_till_session is not null then
    if not v_owner then raise exception 'Till session invalid' using errcode='42501'; end if;
    v_member:=public.till_session_member(p_shop_id,p_till_session);
    seller_id:=v_member.user_id;
    max_discount_pct:=v_member.max_discount_pct;
    return;
  end if;
  if v_owner then
    seller_id:=v_uid; max_discount_pct:=null; return;
  end if;
  v_member:=public.assert_active_member(p_shop_id);
  if not exists (select 1 from public.member_pins p
    where p.member_id=v_member.id and p.pin_hash is not null) then
    raise exception 'PIN required' using errcode='42501';
  end if;
  if not public.cashier_pin_unlocked(v_member.id) then
    raise exception 'PIN unlock required' using errcode='42501';
  end if;
  perform public.cashier_touch_unlock(v_member.id);
  seller_id:=v_uid;
  max_discount_pct:=v_member.max_discount_pct;
end;
$$;

-- State is only ever changed from SECURITY DEFINER functions with verified
-- auth.uid + auth_session_id. LocalStorage has NO authority.
create or replace function public.counter_status(p_shop_id uuid)
returns jsonb language plpgsql stable security definer set search_path to ''
as $$
declare
  v_lock public.counter_device_locks%rowtype;
begin
  if auth.uid() is null or public.counter_auth_session_id() is null then
    return '{"active":false}'::jsonb;
  end if;
  select * into v_lock from public.counter_device_locks l
  where l.auth_session_id=public.counter_auth_session_id()
    and l.owner_id=auth.uid() and l.shop_id=p_shop_id and l.closed_at is null;
  if not found then return '{"active":false}'::jsonb; end if;
  return pg_catalog.jsonb_build_object('active',true,
    'shop_id',v_lock.shop_id,'member_id',v_lock.member_id);
end;
$$;

create or replace function public.counter_start(p_shop_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare
  v_session uuid := public.counter_auth_session_id();
begin
  -- This function is ONLY available while the owner is still unlocked.
  perform public.assert_shop_owner(p_shop_id);
  if v_session is null then
    raise exception 'Authenticated session id required' using errcode='42501';
  end if;
  if not exists (select 1 from public.owner_pins o where o.shop_id=p_shop_id) then
    raise exception 'Owner PIN required' using errcode='42501';
  end if;
  if not exists (select 1 from public.shop_members m
      join public.member_pins p on p.member_id=m.id
      where m.shop_id=p_shop_id and m.active
        and p.pin_hash is not null and not p.must_change) then
    raise exception 'No cashier with PIN available' using errcode='42501';
  end if;
  insert into public.counter_device_locks(auth_session_id,shop_id,owner_id)
  values(v_session,p_shop_id,auth.uid())
  on conflict(auth_session_id) do update
    set shop_id=excluded.shop_id,owner_id=excluded.owner_id,
        member_id=null,till_session_id=null,closed_at=null,
        started_at=now(),updated_at=now()
  where public.counter_device_locks.closed_at is not null;
  if not found then
    raise exception 'Counter already active' using errcode='42501';
  end if;
  perform public.shop_audit(p_shop_id,'counter_mode_entered',null,'{}'::jsonb);
  return '{"active":true}'::jsonb;
end;
$$;

create or replace function public.counter_members(p_shop_id uuid)
returns jsonb language plpgsql stable security definer set search_path to ''
as $$
begin
  if not exists (select 1 from public.counter_device_locks l
      where l.auth_session_id=public.counter_auth_session_id()
        and l.owner_id=auth.uid() and l.shop_id=p_shop_id and l.closed_at is null) then
    raise exception 'Counter not active' using errcode='42501';
  end if;
  return coalesce((
    select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'id',m.id,'display_name',m.display_name,
      'pin_set',p.pin_hash is not null and not p.must_change) order by m.display_name)
    from public.shop_members m left join public.member_pins p on p.member_id=m.id
    where m.shop_id=p_shop_id and m.active), '[]'::jsonb);
end;
$$;

create or replace function public.counter_choose_cashier(
  p_shop_id uuid,p_member_id uuid,p_pin text)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare
  v_lock public.counter_device_locks%rowtype;
  v_member public.shop_members%rowtype;
  v_result jsonb;
  v_token text;
  v_till public.till_sessions%rowtype;
begin
  select * into v_lock from public.counter_device_locks l
  where l.auth_session_id=public.counter_auth_session_id() and l.owner_id=auth.uid()
    and l.shop_id=p_shop_id and l.closed_at is null for update;
  if not found then raise exception 'Counter not active' using errcode='42501'; end if;
  select * into v_member from public.shop_members m
  where m.id=p_member_id and m.shop_id=p_shop_id and m.active;
  if not found then raise exception 'Member not found' using errcode='42501'; end if;
  v_result:=public.member_pin_check(p_member_id,p_pin);
  if v_result->>'status'<>'ok' then return v_result; end if;
  if v_lock.till_session_id is not null then
    update public.till_sessions set closed_at=now()
    where id=v_lock.till_session_id and closed_at is null;
  end if;
  v_token:=pg_catalog.encode(extensions.gen_random_bytes(32),'hex');
  insert into public.till_sessions(shop_id,member_id,token_hash,opened_by,expires_at)
  values(p_shop_id,p_member_id,
    pg_catalog.sha256(pg_catalog.convert_to('covi-till:'||v_token,'UTF8')),
    auth.uid(),now()+interval '12 hours')
  returning * into v_till;
  update public.counter_device_locks set member_id=p_member_id,
    till_session_id=v_till.id,updated_at=now()
  where auth_session_id=v_lock.auth_session_id;
  perform public.shop_audit(p_shop_id,'counter_cashier_selected',p_member_id::text,
    pg_catalog.jsonb_build_object('till_session_id',v_till.id));
  return pg_catalog.jsonb_build_object('status','ok','token',v_token,
    'session_id',v_till.id,'expires_at',v_till.expires_at,
    'member_id',v_member.id,'user_id',v_member.user_id,
    'display_name',v_member.display_name,
    'max_discount_pct',v_member.max_discount_pct,
    'can_view_shop_sales',v_member.can_view_shop_sales);
end;
$$;

create or replace function public.counter_leave(p_shop_id uuid,p_pin text)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare
  v_lock public.counter_device_locks%rowtype;
  v_check jsonb;
begin
  select * into v_lock from public.counter_device_locks l
  where l.auth_session_id=public.counter_auth_session_id()
    and l.owner_id=auth.uid() and l.shop_id=p_shop_id and l.closed_at is null
  for update;
  if not found then
    raise exception 'Counter not active' using errcode='42501';
  end if;
  v_check:=public.owner_pin_check(p_shop_id,p_pin);
  if v_check->>'status'<>'ok' then
    perform public.owner_pin_audit_failure(p_shop_id,'counter_leave',v_check);
    return v_check;
  end if;
  if v_lock.till_session_id is not null then
    update public.till_sessions set closed_at=now()
    where id=v_lock.till_session_id and closed_at is null;
  end if;
  update public.counter_device_locks
  set closed_at=now(),updated_at=now(),member_id=null,till_session_id=null
  where auth_session_id=v_lock.auth_session_id;
  perform public.shop_audit(p_shop_id,'counter_mode_left',null,'{}'::jsonb);
  return '{"status":"ok"}'::jsonb;
end;
$$;

-- Never expose the raw state lookup or unprotected helpers through the Data API.
revoke execute on function public.counter_auth_session_id() from public, anon, authenticated;
revoke execute on function public.counter_lock_active() from public, anon;
revoke execute on function public.counter_row_allowed(text,uuid,uuid) from public, anon;
revoke execute on function public.counter_sale_item_allowed(uuid) from public, anon;
revoke execute on function public.counter_status(uuid) from public, anon;
revoke execute on function public.counter_start(uuid) from public, anon;
revoke execute on function public.counter_members(uuid) from public, anon;
revoke execute on function public.counter_choose_cashier(uuid,uuid,text) from public, anon;
revoke execute on function public.counter_leave(uuid,text) from public, anon;

grant execute on function public.counter_lock_active() to authenticated;
grant execute on function public.counter_row_allowed(text,uuid,uuid) to authenticated;
grant execute on function public.counter_sale_item_allowed(uuid) to authenticated;
grant execute on function public.counter_status(uuid) to authenticated;
grant execute on function public.counter_start(uuid) to authenticated;
grant execute on function public.counter_members(uuid) to authenticated;
grant execute on function public.counter_choose_cashier(uuid,uuid,text) to authenticated;
grant execute on function public.counter_leave(uuid,text) to authenticated;
