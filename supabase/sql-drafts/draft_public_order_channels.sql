-- COVI public QR/social order channel. REVIEW ONLY, NEVER APPLY TO PRODUCTION.
-- Apply in an EPHEMERAL test DB after category stock + checkout order drafts.
-- No payments, no stock deduction, no anonymous direct INSERT grants.
-- A link is disabled by default until the shop owner explicitly enables it.
begin;

create table if not exists public.checkout_public_links (
  shop_id uuid primary key references public.shops(id),
  public_token uuid not null default gen_random_uuid() unique,
  enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.checkout_public_rate_windows (
  shop_id uuid not null references public.shops(id),
  bucket_kind text not null check (bucket_kind in ('minute','day')),
  bucket_start timestamptz not null,
  submissions integer not null default 0 check (submissions >= 0),
  primary key (shop_id, bucket_kind, bucket_start)
);

alter table public.checkout_public_links enable row level security;
alter table public.checkout_public_rate_windows enable row level security;

create policy "owner reads their checkout public link"
  on public.checkout_public_links for select to authenticated
  using (
    exists (
      select 1 from public.shops s
      where s.id = shop_id and s.owner_id = (select auth.uid())
    )
  );

revoke insert, update, delete on public.checkout_public_links from anon, authenticated;
revoke select, insert, update, delete on public.checkout_public_rate_windows
  from anon, authenticated;

-- Read link status without creating or changing it.
create or replace function public.get_checkout_public_link(p_shop_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_link public.checkout_public_links%rowtype;
begin
  if v_actor is null then
    raise exception 'Authentification requise' using errcode = '28000';
  end if;
  if p_shop_id is null or not exists (
    select 1 from public.shops s
    where s.id = p_shop_id and s.owner_id = v_actor
  ) then
    raise exception 'Accès à cette boutique refusé' using errcode = '42501';
  end if;
  select * into v_link from public.checkout_public_links
  where shop_id = p_shop_id;
  if not found then return null; end if;
  return jsonb_build_object('publicToken',v_link.public_token,'enabled',v_link.enabled);
end;
$function$;

-- A link is a random bearer capability for *submitting requests only*.
-- Owning the link does not authorize approval, stock edits or payments.
create or replace function public.configure_checkout_public_link(
  p_shop_id uuid, p_enabled boolean
)
returns jsonb language plpgsql security definer set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_link public.checkout_public_links%rowtype;
begin
  if v_actor is null then
    raise exception 'Authentification requise' using errcode = '28000';
  end if;
  if p_shop_id is null or p_enabled is null or not exists (
    select 1 from public.shops s
    where s.id = p_shop_id and s.owner_id = v_actor
  ) then
    raise exception 'Accès à cette boutique refusé' using errcode = '42501';
  end if;

  insert into public.checkout_public_links (shop_id, enabled)
  values (p_shop_id, p_enabled)
  on conflict (shop_id)
  do update set enabled = excluded.enabled, updated_at = now()
  returning * into v_link;

  return jsonb_build_object(
    'publicToken', v_link.public_token,
    'enabled', v_link.enabled
  );
end;
$function$;

-- Old links can be invalidated if they were shared accidentally or abused.
create or replace function public.rotate_checkout_public_link(p_shop_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_link public.checkout_public_links%rowtype;
begin
  if v_actor is null then
    raise exception 'Authentification requise' using errcode = '28000';
  end if;
  if p_shop_id is null or not exists (
    select 1 from public.shops s
    where s.id = p_shop_id and s.owner_id = v_actor
  ) then
    raise exception 'Accès à cette boutique refusé' using errcode = '42501';
  end if;
  update public.checkout_public_links
  set public_token = gen_random_uuid(), updated_at = now()
  where shop_id = p_shop_id returning * into v_link;
  if not found then
    raise exception 'Aucun lien à renouveler';
  end if;
  return jsonb_build_object('publicToken', v_link.public_token, 'enabled', v_link.enabled);
end;
$function$;

-- Public visitors may see ONLY broad available categories, not stock counts,
-- costs, owner data, customer details or other shops.
create or replace function public.get_checkout_public_catalog(p_token uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $function$
declare
  v_shop_id uuid;
  v_name text;
  v_categories jsonb;
begin
  select s.id, s.name into v_shop_id, v_name
  from public.checkout_public_links l
  join public.shops s on s.id = l.shop_id
  where l.public_token = p_token and l.enabled = true;

  if not found then raise exception 'Ce lien de commande est indisponible'; end if;

  select coalesce(jsonb_agg(
      jsonb_build_object('id', c.id, 'label', c.display_name)
      order by c.display_name, c.id
    ), '[]'::jsonb)
    into v_categories
  from public.stock_categories c
  where c.shop_id = v_shop_id and c.is_test = false
    and c.quantity_on_hand > c.quantity_reserved;

  return jsonb_build_object('shopName', v_name, 'categories', v_categories);
end;
$function$;

create or replace function public.submit_checkout_public_order(
  p_token uuid,
  p_channel text,
  p_operation_id uuid,
  p_lines jsonb,
  p_customer_phone text default null,
  p_customer_note text default null,
  p_fulfillment text default 'pickup'
)
returns jsonb language plpgsql security definer set search_path = ''
as $function$
declare
  v_shop_id uuid;
  v_canonical jsonb;
  v_payload jsonb;
  v_total numeric;
  v_phone text := nullif(btrim(p_customer_phone), '');
  v_note text := nullif(btrim(p_customer_note), '');
  v_order public.checkout_orders%rowtype;
  v_line record;
  v_bucket timestamptz;
begin
  select shop_id into v_shop_id from public.checkout_public_links
  where public_token = p_token and enabled = true;
  if not found then
    raise exception 'Ce lien de commande est indisponible';
  end if;

  if p_operation_id is null or p_channel not in ('qr','social')
     or p_channel is null or p_fulfillment not in ('pickup','delivery')
     or p_fulfillment is null then
    raise exception 'Paramètres de commande invalides';
  end if;

  if char_length(v_phone) > 32 or char_length(v_note) > 500
    or coalesce(v_phone ~ '[[:cntrl:]]',false)
    or coalesce(v_note ~ '[[:cntrl:]]',false)
    or (p_fulfillment = 'delivery' and v_phone is null) then
    raise exception 'Téléphone requis pour une livraison, ou coordonnées invalides';
  end if;

  if jsonb_typeof(p_lines) is distinct from 'array' then
    raise exception 'Le panier doit être une liste';
  end if;
  if jsonb_array_length(p_lines) < 1 or jsonb_array_length(p_lines) > 20 then
    raise exception 'Une commande publique contient entre 1 et 20 lignes';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_lines) as e(item)
    where jsonb_typeof(item) is distinct from 'object'
      or jsonb_typeof(item->'categoryId') is distinct from 'string'
      or coalesce((item->>'categoryId') !~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', true)
      or jsonb_typeof(item->'quantity') is distinct from 'number'
      or coalesce((item->>'quantity') !~ '^([1-9]|1[0-9]|20)$',true)
      or jsonb_typeof(item->'unitPriceXaf') is distinct from 'number'
      or coalesce((item->>'unitPriceXaf') !~ '^[1-9][0-9]{0,8}$',true)
  ) then
    raise exception 'Catégorie, quantité ou prix invalide';
  end if;

  select jsonb_agg(jsonb_build_object(
    'categoryId', t.category_id, 'quantity', t.qty, 'unitPriceXaf', t.price
    ) order by t.category_id, t.price),
    sum(t.qty::numeric * t.price)
    into v_canonical, v_total
  from (
    select (item->>'categoryId')::uuid as category_id,
      sum((item->>'quantity')::integer)::bigint as qty,
      (item->>'unitPriceXaf')::bigint as price
    from jsonb_array_elements(p_lines) as e(item)
    group by (item->>'categoryId')::uuid, (item->>'unitPriceXaf')::bigint
  ) as t;

  if v_total > 2000000000 or exists(
    select 1 from (
      select sum((item->>'quantity')::integer) as qty
      from jsonb_array_elements(v_canonical) as e(item)
      group by (item->>'categoryId')::uuid
    ) summed where summed.qty > 20
  ) then
    raise exception 'Montant ou quantité publique hors limite';
  end if;

  -- No availability count is published, but server verifies all categories.
  if exists (
    select 1
    from (
      select (item->>'categoryId')::uuid as id,
        sum((item->>'quantity')::integer) as qty
      from jsonb_array_elements(v_canonical) as e(item)
      group by (item->>'categoryId')::uuid
    ) requested
    left join public.stock_categories c
      on c.id = requested.id and c.shop_id = v_shop_id and c.is_test = false
    where c.id is null or c.quantity_on_hand - c.quantity_reserved < requested.qty
  ) then
    raise exception 'Une catégorie est indisponible, demandez au vendeur';
  end if;

  v_payload := jsonb_build_object(
    'channel',p_channel, 'lines',v_canonical, 'isTest',false,
    'customerPhone',v_phone, 'customerNote',v_note, 'fulfillment',p_fulfillment
  );

  -- Exactly-one order on retries, even if two anonymous sessions race.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'covi:public-order:' || v_shop_id::text || ':' || p_operation_id::text, 0
    )
  );

  select * into v_order from public.checkout_orders o
  where o.shop_id = v_shop_id and o.creation_operation_id = p_operation_id;
  if found then
    if v_order.channel = p_channel and v_order.creation_payload = v_payload then
      return jsonb_build_object(
        'orderId',v_order.id, 'status',v_order.status,
        'amountXaf',v_order.amount_xaf
      );
    end if;
    raise exception 'Cet identifiant de commande a déjà été utilisé';
  end if;

  -- Transactional, shop-wide rate ceilings: 60/minute and 1000/day.
  -- These are anti-spam guardrails, NOT a replacement for IP/edge protection.
  v_bucket := date_trunc('minute', clock_timestamp());
  insert into public.checkout_public_rate_windows
    (shop_id,bucket_kind,bucket_start,submissions)
  values (v_shop_id,'minute',v_bucket,1)
  on conflict (shop_id,bucket_kind,bucket_start)
    do update set submissions = public.checkout_public_rate_windows.submissions + 1
    where public.checkout_public_rate_windows.submissions < 60;
  if not found then raise exception 'Trop de demandes, réessayez plus tard'; end if;

  v_bucket := date_trunc('day', clock_timestamp());
  insert into public.checkout_public_rate_windows
    (shop_id,bucket_kind,bucket_start,submissions)
  values (v_shop_id,'day',v_bucket,1)
  on conflict (shop_id,bucket_kind,bucket_start)
    do update set submissions = public.checkout_public_rate_windows.submissions + 1
    where public.checkout_public_rate_windows.submissions < 1000;
  if not found then raise exception 'Trop de demandes, réessayez demain'; end if;

  insert into public.checkout_orders (
    shop_id,channel,status,is_test,customer_phone,customer_note,
    fulfillment,amount_xaf,creation_operation_id,creation_payload
  ) values (
    v_shop_id,p_channel,'submitted',false,v_phone,v_note,
    p_fulfillment,v_total,p_operation_id,v_payload
  ) returning * into v_order;

  for v_line in
    select (item->>'categoryId')::uuid as category_id,
      (item->>'quantity')::integer as qty,
      (item->>'unitPriceXaf')::bigint as price
    from jsonb_array_elements(v_canonical) as e(item)
  loop
    insert into public.checkout_order_lines
      (shop_id,order_id,category_id,quantity,negotiated_unit_price_xaf)
    values (v_shop_id,v_order.id,v_line.category_id,v_line.qty,v_line.price);
  end loop;

  return jsonb_build_object(
    'orderId',v_order.id,'status',v_order.status,'amountXaf',v_order.amount_xaf
  );
end;
$function$;

-- No open access to link configuration or token rotation.
revoke all on function public.get_checkout_public_link(uuid)
  from public, anon;
grant execute on function public.get_checkout_public_link(uuid)
  to authenticated;


revoke all on function public.configure_checkout_public_link(uuid,boolean)
  from public, anon;
grant execute on function public.configure_checkout_public_link(uuid,boolean)
  to authenticated;

revoke all on function public.rotate_checkout_public_link(uuid)
  from public, anon;
grant execute on function public.rotate_checkout_public_link(uuid)
  to authenticated;

-- Public can only read broad non-sensitive category names and submit requests.
revoke all on function public.get_checkout_public_catalog(uuid) from public;
grant execute on function public.get_checkout_public_catalog(uuid)
  to anon, authenticated;

revoke all on function public.submit_checkout_public_order(
  uuid,text,uuid,jsonb,text,text,text
) from public;
grant execute on function public.submit_checkout_public_order(
  uuid,text,uuid,jsonb,text,text,text
) to anon, authenticated;
commit;

-- BLOCKING gates for any deployment:
-- A valid token must never be used as owner authentication.
-- Integrate edge WAF/IP throttling and monitor abuse in addition to SQL quotas.
-- Rotate links on abuse; owners must inspect/approve customer-quoted prices.
-- Do not expose customer contact data or exact inventory publicly.
-- Clean up obsolete rate windows periodically after approval.
-- No payment API or public paid-status mutation exists here.
