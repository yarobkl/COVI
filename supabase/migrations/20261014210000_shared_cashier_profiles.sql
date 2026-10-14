-- COVI: shared management login, individual cashier PIN profiles (no cashier login).
-- Additive only: existing sellers, shops, stock and sales are untouched.
create table public.shop_cashier_profiles (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 60),
  pin_hash text not null check (pin_hash like '$2_$%'),
  active boolean not null default true,
  max_discount_pct numeric not null default 0 check (max_discount_pct between 0 and 100),
  can_view_shop_sales boolean not null default false,
  failed_attempts integer not null default 0 check (failed_attempts >= 0),
  locked_until timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index shop_cashier_profiles_shop_idx on public.shop_cashier_profiles(shop_id);
create trigger shop_cashier_profiles_touch_updated_at
  before update on public.shop_cashier_profiles
  for each row execute function public.touch_updated_at();
alter table public.shop_cashier_profiles enable row level security;
revoke all on public.shop_cashier_profiles from public, anon, authenticated;

create table public.shop_cashier_tills (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  cashier_id uuid not null references public.shop_cashier_profiles(id) on delete cascade,
  token_hash bytea not null unique,
  opened_by uuid not null references auth.users(id),
  opened_at timestamptz not null default now(),
  expires_at timestamptz not null,
  closed_at timestamptz
);
create index shop_cashier_tills_active_idx on public.shop_cashier_tills(shop_id, cashier_id, expires_at)
  where closed_at is null;
alter table public.shop_cashier_tills enable row level security;
revoke all on public.shop_cashier_tills from public, anon, authenticated;

alter table public.sales add column cashier_profile_id uuid
  references public.shop_cashier_profiles(id);
create index sales_cashier_profile_idx on public.sales(shop_id, cashier_profile_id, sold_at desc);

create or replace function public.list_shared_cashiers(p_shop_id uuid)
returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
begin
  perform public.assert_shop_owner(p_shop_id);
  return coalesce((
    select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'id',c.id,'display_name',c.display_name,'active',c.active,
      'max_discount_pct',c.max_discount_pct,
      'can_view_shop_sales',c.can_view_shop_sales,'pin_set',true)
      order by c.display_name, c.id)
    from public.shop_cashier_profiles c where c.shop_id=p_shop_id), '[]'::jsonb);
end;
$fn$;

create or replace function public.create_shared_cashier(
  p_shop_id uuid,p_display_name text,p_pin text,
  p_max_discount_pct numeric default 0,p_can_view_shop_sales boolean default false)
returns jsonb language plpgsql security definer set search_path to ''
as $fn$
declare
  v_name text:=pg_catalog.btrim(p_display_name);
  v_row public.shop_cashier_profiles%rowtype;
begin
  perform public.assert_shop_owner(p_shop_id);
  perform public.member_pin_assert_strength(p_pin);
  if v_name is null or char_length(v_name) not between 1 and 60
    or v_name ~ '[[:cntrl:]]' then
    raise exception 'Invalid display name';
  end if;
  if p_max_discount_pct is null or p_max_discount_pct < 0 or p_max_discount_pct > 100 then
    raise exception 'Invalid discount';
  end if;
  if (select count(*) from public.shop_cashier_profiles where shop_id=p_shop_id) >= 100 then
    raise exception 'Too many cashiers';
  end if;
  insert into public.shop_cashier_profiles
    (shop_id,display_name,pin_hash,max_discount_pct,can_view_shop_sales,created_by)
  values(p_shop_id,v_name,
    extensions.crypt(p_pin,extensions.gen_salt('bf',10)),
    p_max_discount_pct,coalesce(p_can_view_shop_sales,false),auth.uid())
  returning * into v_row;
  perform public.shop_audit(p_shop_id,'shared_cashier_created',v_row.id::text,
    pg_catalog.jsonb_build_object('display_name',v_name));
  return pg_catalog.jsonb_build_object('id',v_row.id,'display_name',v_row.display_name,
    'active',true,'pin_set',true,'max_discount_pct',v_row.max_discount_pct,
    'can_view_shop_sales',v_row.can_view_shop_sales);
end;
$fn$;

create or replace function public.set_shared_cashier_active(p_cashier_id uuid,p_active boolean)
returns boolean language plpgsql security definer set search_path to ''
as $fn$
declare v_cashier public.shop_cashier_profiles%rowtype;
begin
  select * into v_cashier from public.shop_cashier_profiles where id=p_cashier_id for update;
  if not found then raise exception 'Cashier not found' using errcode='42501'; end if;
  perform public.assert_shop_owner(v_cashier.shop_id);
  if p_active is null then raise exception 'Invalid state'; end if;
  update public.shop_cashier_profiles set active=p_active where id=p_cashier_id;
  if not p_active then
    update public.shop_cashier_tills set closed_at=now()
    where cashier_id=p_cashier_id and closed_at is null;
  end if;
  perform public.shop_audit(v_cashier.shop_id,
    case when p_active then 'shared_cashier_enabled' else 'shared_cashier_disabled' end,
    p_cashier_id::text,'{}'::jsonb);
  return true;
end;
$fn$;

create or replace function public.shared_cashier_pin_check(p_cashier_id uuid,p_pin text)
returns jsonb language plpgsql security definer set search_path to ''
as $fn$
declare
  v_row public.shop_cashier_profiles%rowtype;
  v_fail integer;
begin
  select * into v_row from public.shop_cashier_profiles where id=p_cashier_id for update;
  if not found or not v_row.active then
    return '{"status":"invalid","attempts_left":0}'::jsonb;
  end if;
  if v_row.locked_until > now() then
    return pg_catalog.jsonb_build_object('status','locked','retry_after',v_row.locked_until);
  end if;
  if p_pin is not null and p_pin ~ '^[0-9]{4,6}$'
    and extensions.crypt(p_pin,v_row.pin_hash)=v_row.pin_hash then
    update public.shop_cashier_profiles set failed_attempts=0,locked_until=null
    where id=p_cashier_id;
    return '{"status":"ok"}'::jsonb;
  end if;
  v_fail:=v_row.failed_attempts+1;
  update public.shop_cashier_profiles
  set failed_attempts=case when v_fail>=5 then 0 else v_fail end,
      locked_until=case when v_fail>=5 then now()+interval '15 minutes' else null end
  where id=p_cashier_id;
  if v_fail>=5 then
    return pg_catalog.jsonb_build_object('status','locked',
      'retry_after',now()+interval '15 minutes');
  end if;
  return pg_catalog.jsonb_build_object('status','invalid','attempts_left',5-v_fail);
end;
$fn$;

create or replace function public.open_shared_cashier_till(
  p_shop_id uuid,p_cashier_id uuid,p_pin text)
returns jsonb language plpgsql security definer set search_path to ''
as $fn$
declare
  v_cashier public.shop_cashier_profiles%rowtype;
  v_check jsonb;
  v_token text;
  v_session public.shop_cashier_tills%rowtype;
begin
  perform public.assert_shop_owner(p_shop_id);
  if not exists(select 1 from public.owner_pins where shop_id=p_shop_id) then
    raise exception 'Owner PIN required' using errcode='42501';
  end if;
  select * into v_cashier from public.shop_cashier_profiles
  where id=p_cashier_id and shop_id=p_shop_id and active;
  if not found then raise exception 'Cashier not found' using errcode='42501'; end if;
  v_check:=public.shared_cashier_pin_check(p_cashier_id,p_pin);
  if v_check->>'status'<>'ok' then
    perform public.shop_audit(p_shop_id,'shared_cashier_pin_failed',p_cashier_id::text,
      pg_catalog.jsonb_build_object('result',v_check->>'status'));
    return v_check;
  end if;
  v_token:=pg_catalog.encode(extensions.gen_random_bytes(32),'hex');
  insert into public.shop_cashier_tills
    (shop_id,cashier_id,token_hash,opened_by,expires_at)
  values (p_shop_id,p_cashier_id,
    pg_catalog.sha256(pg_catalog.convert_to('covi-shared-cashier:'||v_token,'UTF8')),
    auth.uid(),now()+interval '12 hours')
  returning * into v_session;
  perform public.shop_audit(p_shop_id,'shared_cashier_till_opened',p_cashier_id::text,
    pg_catalog.jsonb_build_object('till_id',v_session.id));
  return pg_catalog.jsonb_build_object(
    'status','ok','token',v_token,'session_id',v_session.id,
    'expires_at',v_session.expires_at,'cashier_profile_id',p_cashier_id,
    'member_id',p_cashier_id,'user_id',auth.uid(),
    'display_name',v_cashier.display_name,
    'max_discount_pct',v_cashier.max_discount_pct,
    'can_view_shop_sales',v_cashier.can_view_shop_sales);
end;
$fn$;

create or replace function public.shared_cashier_from_till(p_shop_id uuid,p_token text)
returns uuid language sql stable security definer set search_path to ''
as $fn$
  select c.id from public.shop_cashier_tills t
  join public.shop_cashier_profiles c on c.id=t.cashier_id
  join public.shops s on s.id=t.shop_id
  where p_token is not null and p_token ~ '^[0-9a-f]{64}$'
    and t.token_hash=pg_catalog.sha256(
      pg_catalog.convert_to('covi-shared-cashier:'||p_token,'UTF8'))
    and t.shop_id=p_shop_id and c.shop_id=p_shop_id and c.active
    and t.closed_at is null and t.expires_at>now()
    and s.owner_id=auth.uid() and t.opened_by=auth.uid()
$fn$;

create or replace function public.unlock_shared_cashier_till(
  p_shop_id uuid,p_token text,p_pin text)
returns jsonb language plpgsql security definer set search_path to ''
as $fn$
declare
  v_cashier_id uuid;
  v_check jsonb;
begin
  perform public.assert_shop_owner(p_shop_id);
  v_cashier_id:=public.shared_cashier_from_till(p_shop_id,p_token);
  if v_cashier_id is null then raise exception 'Till session invalid' using errcode='42501'; end if;
  v_check:=public.shared_cashier_pin_check(v_cashier_id,p_pin);
  if v_check->>'status'<>'ok' then
    perform public.shop_audit(p_shop_id,'shared_cashier_pin_failed',v_cashier_id::text,
      pg_catalog.jsonb_build_object('result',v_check->>'status','context','unlock'));
  end if;
  return v_check;
end;
$fn$;

create or replace function public.close_shared_cashier_till(
  p_shop_id uuid,p_token text)
returns boolean language plpgsql security definer set search_path to ''
as $fn$
declare
  v_cashier_id uuid;
begin
  perform public.assert_shop_owner(p_shop_id);
  v_cashier_id:=public.shared_cashier_from_till(p_shop_id,p_token);
  if v_cashier_id is null then return false; end if;
  update public.shop_cashier_tills set closed_at=now()
  where shop_id=p_shop_id and cashier_id=v_cashier_id
    and token_hash=pg_catalog.sha256(
      pg_catalog.convert_to('covi-shared-cashier:'||p_token,'UTF8'))
    and closed_at is null;
  perform public.shop_audit(p_shop_id,'shared_cashier_till_closed',v_cashier_id::text,'{}'::jsonb);
  return found;
end;
$fn$;

-- Only trusted RPCs are public-facing. Never reveal PIN hashes or raw sessions.
revoke execute on function public.shared_cashier_pin_check(uuid,text) from public,anon,authenticated;
revoke execute on function public.shared_cashier_from_till(uuid,text) from public,anon,authenticated;
revoke execute on function public.list_shared_cashiers(uuid) from public,anon;
revoke execute on function public.create_shared_cashier(uuid,text,text,numeric,boolean) from public,anon;
revoke execute on function public.set_shared_cashier_active(uuid,boolean) from public,anon;
revoke execute on function public.open_shared_cashier_till(uuid,uuid,text) from public,anon;
revoke execute on function public.unlock_shared_cashier_till(uuid,text,text) from public,anon;
revoke execute on function public.close_shared_cashier_till(uuid,text) from public,anon;
grant execute on function public.list_shared_cashiers(uuid) to authenticated;
grant execute on function public.create_shared_cashier(uuid,text,text,numeric,boolean) to authenticated;
grant execute on function public.set_shared_cashier_active(uuid,boolean) to authenticated;
grant execute on function public.open_shared_cashier_till(uuid,uuid,text) to authenticated;
grant execute on function public.unlock_shared_cashier_till(uuid,text,text) to authenticated;
grant execute on function public.close_shared_cashier_till(uuid,text) to authenticated;

-- Preserve the legacy till and personal-account paths, while supporting shared-account PIN profiles.
CREATE OR REPLACE FUNCTION public.sale_seller(p_shop_id uuid, p_till_session text, OUT seller_id uuid, OUT max_discount_pct numeric)
 RETURNS record
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_is_owner boolean;
  v_member public.shop_members%rowtype;
  v_cashier public.shop_cashier_profiles%rowtype;
begin
  v_is_owner := exists (
    select 1 from public.shops s where s.id = p_shop_id and s.owner_id = v_uid);
  if p_till_session is not null then
    if not v_is_owner then
      raise exception 'Till session invalid' using errcode = '42501';
    end if;
    select c.* into v_cashier from public.shop_cashier_profiles c
    where c.id=public.shared_cashier_from_till(p_shop_id,p_till_session);
    if found then
      seller_id:=v_uid;
      max_discount_pct:=v_cashier.max_discount_pct;
      return;
    end if;
    v_member := public.till_session_member(p_shop_id, p_till_session);
    seller_id := v_member.user_id;
    max_discount_pct := v_member.max_discount_pct;
    return;
  end if;
  if v_is_owner then
    seller_id := v_uid;
    max_discount_pct := null;
    return;
  end if;
  v_member := public.assert_active_member(p_shop_id);
  if not exists (select 1 from public.member_pins p
                 where p.member_id = v_member.id and p.pin_hash is not null) then
    raise exception 'PIN required' using errcode = '42501';
  end if;
  if not public.cashier_pin_unlocked(v_member.id) then
    raise exception 'PIN unlock required' using errcode = '42501';
  end if;
  -- Sliding expiry: active cashiers may keep selling without entering the PIN every five minutes.
  perform public.cashier_touch_unlock(v_member.id);
  seller_id := v_uid;
  max_discount_pct := v_member.max_discount_pct;
end;
$function$;

CREATE OR REPLACE FUNCTION public.record_sale(p_shop_id uuid, p_product_id uuid, p_quantity integer, p_sold_unit_price numeric, p_payment_method text, p_client_operation_id uuid, p_till_session text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_seller record;
  v_min_price numeric;
  v_product public.products%rowtype;
  v_sale_id uuid;
begin
  -- Propriétaire ou membre actif (lève 'Authentication required' / 'Shop not found').
  perform public.assert_can_sell(p_shop_id);
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be positive'; end if;
  if p_sold_unit_price is null or p_sold_unit_price < 0 then
    raise exception 'Sold price cannot be negative';
  end if;
  if p_client_operation_id is null then raise exception 'Sale operation id is required'; end if;
  if p_payment_method is null
     or p_payment_method not in ('cash','mobile_money','card','bank_transfer','other') then
    raise exception 'Invalid payment method';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_shop_id::text || ':' || p_client_operation_id::text, 0)
  );
  select s.id into v_sale_id
  from public.sales s
  where s.shop_id = p_shop_id and s.client_operation_id = p_client_operation_id;
  if v_sale_id is not null then return v_sale_id; end if;
  -- Vendeur : session de caisse, propriétaire, ou membre avec PIN.
  select * into v_seller from public.sale_seller(p_shop_id, p_till_session);
  select * into v_product
  from public.products p
  where p.id = p_product_id and p.shop_id = p_shop_id and p.status = 'active'
  for update;
  if not found then raise exception 'Product unavailable'; end if;
  if v_product.is_unique_piece and p_quantity <> 1 then
    raise exception 'Unique piece quantity must be 1';
  end if;
  if v_product.quantity_on_hand < p_quantity then raise exception 'Insufficient stock'; end if;
  v_min_price := public.min_unit_price(v_product.initial_sale_price, v_seller.max_discount_pct);
  if v_min_price is not null and p_sold_unit_price < v_min_price then
    raise exception 'Price below allowed minimum'
      using detail = pg_catalog.format('item 0: product_id %s, minimum_price=%s',
                                       p_product_id, v_min_price);
  end if;
  insert into public.sales(shop_id, payment_method, total_amount, client_operation_id, is_test,
                           seller_id,cashier_profile_id)
    values (p_shop_id, p_payment_method, p_sold_unit_price * p_quantity, p_client_operation_id,
            v_product.is_test, v_seller.seller_id,
            public.shared_cashier_from_till(p_shop_id,p_till_session))
    returning id into v_sale_id;
  insert into public.sale_items(sale_id, product_id, quantity, initial_unit_price, sold_unit_price)
    values (v_sale_id, p_product_id, p_quantity, v_product.initial_sale_price, p_sold_unit_price);
  update public.products
  set quantity_on_hand = quantity_on_hand - p_quantity,
      status = case when quantity_on_hand - p_quantity = 0 then 'sold' else status end
  where id = p_product_id;
  return v_sale_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.record_cart_sale(p_shop_id uuid, p_items jsonb, p_payment_method text, p_client_operation_id uuid, p_till_session text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  c_max_items constant integer := 50;
  c_max_total constant numeric := 999999999999.99;
  c_uuid_re constant text :=
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_seller record;
  v_min_price numeric;
  v_count integer;
  v_item jsonb;
  v_num numeric;
  v_product_id uuid;
  v_ids uuid[] := '{}';
  v_qtys integer[] := '{}';
  v_prices numeric[] := '{}';
  v_initial_prices numeric[] := '{}';
  v_total numeric := 0;
  v_product public.products%rowtype;
  v_any_test boolean := false;
  v_any_real boolean := false;
  v_sale_id uuid;
begin
  -- Session, propriétaire ou membre actif -----------------------------------------------------
  perform public.assert_can_sell(p_shop_id);

  -- Paramètres de la vente ---------------------------------------------------------------------
  if p_client_operation_id is null then raise exception 'Sale operation id is required'; end if;
  if p_payment_method is null
     or p_payment_method not in ('cash','mobile_money','card','bank_transfer','other') then
    raise exception 'Invalid payment method';
  end if;

  -- Format du panier (aucune lecture de table) -------------------------------------------------
  if p_items is null or pg_catalog.jsonb_typeof(p_items) <> 'array' then
    raise exception 'Cart items must be a JSON array';
  end if;
  v_count := pg_catalog.jsonb_array_length(p_items);
  if v_count < 1 or v_count > c_max_items then
    raise exception 'Cart must contain between 1 and 50 items'
      using detail = pg_catalog.format('%s item(s) received', v_count);
  end if;

  for i in 0 .. v_count - 1 loop
    v_item := p_items -> i;
    if pg_catalog.jsonb_typeof(v_item) is distinct from 'object' then
      raise exception 'Invalid cart item'
        using detail = pg_catalog.format('item %s: not a JSON object', i);
    end if;
    if exists (
      select 1 from pg_catalog.jsonb_object_keys(v_item) k
      where k not in ('product_id', 'quantity', 'sold_unit_price')
    ) then
      raise exception 'Invalid cart item'
        using detail = pg_catalog.format(
          'item %s: unknown key (allowed: product_id, quantity, sold_unit_price)', i);
    end if;

    -- product_id : chaîne uuid canonique
    if pg_catalog.jsonb_typeof(v_item -> 'product_id') is distinct from 'string'
       or (v_item ->> 'product_id') !~ c_uuid_re then
      raise exception 'Invalid cart item'
        using detail = pg_catalog.format('item %s: product_id must be a uuid string', i);
    end if;
    v_product_id := (v_item ->> 'product_id')::uuid;
    if v_product_id = any(v_ids) then
      raise exception 'Duplicate product in cart'
        using detail = pg_catalog.format('item %s: product_id %s already in cart', i, v_product_id);
    end if;

    -- quantity : nombre entier > 0
    if pg_catalog.jsonb_typeof(v_item -> 'quantity') is distinct from 'number' then
      raise exception 'Invalid cart item'
        using detail = pg_catalog.format('item %s: quantity must be a JSON number', i);
    end if;
    v_num := (v_item ->> 'quantity')::numeric;
    if v_num <= 0 then
      raise exception 'Quantity must be positive'
        using detail = pg_catalog.format('item %s: quantity %s', i, v_num);
    end if;
    if v_num <> pg_catalog.trunc(v_num) or v_num > 2147483647 then
      raise exception 'Invalid cart item'
        using detail = pg_catalog.format('item %s: quantity must be an integer', i);
    end if;

    -- sold_unit_price : nombre >= 0 (arrondi au centime comme la colonne numeric(14,2))
    if pg_catalog.jsonb_typeof(v_item -> 'sold_unit_price') is distinct from 'number' then
      raise exception 'Invalid cart item'
        using detail = pg_catalog.format('item %s: sold_unit_price must be a JSON number', i);
    end if;
    v_num := pg_catalog.round((v_item ->> 'sold_unit_price')::numeric, 2);
    if v_num < 0 then
      raise exception 'Sold price cannot be negative'
        using detail = pg_catalog.format('item %s: sold_unit_price %s', i, v_num);
    end if;

    v_ids := v_ids || v_product_id;
    v_qtys := v_qtys || (v_item ->> 'quantity')::numeric::integer;
    v_prices := v_prices || v_num;
    v_total := v_total + v_num * v_qtys[i + 1];
    if v_total > c_max_total then
      raise exception 'Sale total too large';
    end if;
  end loop;

  -- Idempotence (même clé et même verrou que record_sale) --------------------------------------
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_shop_id::text || ':' || p_client_operation_id::text, 0)
  );
  select s.id into v_sale_id
  from public.sales s
  where s.shop_id = p_shop_id and s.client_operation_id = p_client_operation_id;
  if v_sale_id is not null then return v_sale_id; end if;

  -- Vendeur : session de caisse, propriétaire, ou membre avec PIN ---------------------------------
  select * into v_seller from public.sale_seller(p_shop_id, p_till_session);

  -- Verrouillage des produits dans l'ordre des id (pas d'interblocage entre paniers) -----------
  -- ORDER BY est appliqué avant FOR UPDATE : les lignes sont verrouillées une à une dans cet ordre.
  perform 1
  from public.products p
  where p.id = any(v_ids) and p.shop_id = p_shop_id
  order by p.id
  for update;

  -- Vérifications, dans l'ordre du panier (lignes verrouillées : état le plus récent) ----------
  for i in 1 .. v_count loop
    select * into v_product
    from public.products p
    where p.id = v_ids[i] and p.shop_id = p_shop_id;
    if not found or v_product.status <> 'active' then
      raise exception 'Product unavailable'
        using detail = pg_catalog.format('item %s: product_id %s', i - 1, v_ids[i]);
    end if;
    if v_product.is_unique_piece and v_qtys[i] <> 1 then
      raise exception 'Unique piece quantity must be 1'
        using detail = pg_catalog.format('item %s: product_id %s', i - 1, v_ids[i]);
    end if;
    if v_product.quantity_on_hand < v_qtys[i] then
      raise exception 'Insufficient stock'
        using detail = pg_catalog.format('item %s: product_id %s, requested %s, available %s',
                                         i - 1, v_ids[i], v_qtys[i], v_product.quantity_on_hand);
    end if;
    v_min_price := public.min_unit_price(v_product.initial_sale_price, v_seller.max_discount_pct);
    if v_min_price is not null and v_prices[i] < v_min_price then
      raise exception 'Price below allowed minimum'
        using detail = pg_catalog.format('item %s: product_id %s, minimum_price=%s',
                                         i - 1, v_ids[i], v_min_price);
    end if;
    if v_product.is_test then v_any_test := true; else v_any_real := true; end if;
    v_initial_prices := v_initial_prices || v_product.initial_sale_price;
  end loop;
  if v_any_test and v_any_real then
    raise exception 'Cannot mix test and real products';
  end if;

  -- Écritures ----------------------------------------------------------------------------------
  insert into public.sales(shop_id, payment_method, total_amount, client_operation_id, is_test,
                           seller_id,cashier_profile_id)
    values (p_shop_id, p_payment_method, v_total, p_client_operation_id, v_any_test,
            v_seller.seller_id,public.shared_cashier_from_till(p_shop_id,p_till_session))
    returning id into v_sale_id;

  insert into public.sale_items(sale_id, product_id, quantity, initial_unit_price, sold_unit_price)
  select v_sale_id, c.product_id, c.quantity, c.initial_unit_price, c.sold_unit_price
  from unnest(v_ids, v_qtys, v_initial_prices, v_prices)
         with ordinality as c(product_id, quantity, initial_unit_price, sold_unit_price, n)
  order by c.n;

  update public.products p
  set quantity_on_hand = p.quantity_on_hand - c.quantity,
      status = case when p.quantity_on_hand - c.quantity = 0 then 'sold' else p.status end
  from unnest(v_ids, v_qtys) as c(product_id, quantity)
  where p.id = c.product_id and p.shop_id = p_shop_id;

  return v_sale_id;
end;
$function$;
