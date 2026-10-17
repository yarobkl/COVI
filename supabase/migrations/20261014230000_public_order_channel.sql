-- COVI : canal client par QR code / lien WhatsApp-TikTok, commandes reçues et confirmation
-- manuelle du règlement en caisse.
--
-- Principes (migration uniquement additive : aucune vente, aucun stock, aucune boutique modifiés) :
--   * Le client n'a pas de compte. Il ne parle jamais directement à la base : la fonction Edge
--     « public-checkout » (anti-robot Turnstile, quotas) appelle les fonctions *_public_* avec la
--     clé serveur. Les rôles anon et authenticated n'ont AUCUN droit sur ces fonctions.
--   * Un lien de boutique est un jeton aléatoire qui permet seulement de CONSULTER les articles
--     publiés et de DÉPOSER une demande. Il ne permet ni de valider, ni d'encaisser, ni de modifier
--     le stock. Il est désactivé par défaut et peut être coupé ou renouvelé à tout moment.
--   * Le stock ne bouge qu'à la confirmation du règlement, en caisse : celle-ci passe par
--     record_cart_sale avec la session PIN du caissier (attribution, remise maximale, verrou
--     produit, idempotence). Une commande ne peut être encaissée qu'une fois.
--   * Aucun règlement n'est jamais présumé : le choix du client (Mobile Money, carte…) est une
--     intention. Seul un caissier, après vérification, confirme le règlement réellement reçu.

-- Tables ----------------------------------------------------------------------------------------
create table public.public_order_channels (
  shop_id uuid primary key references public.shops(id) on delete cascade,
  token uuid not null unique default gen_random_uuid(),
  enabled boolean not null default false,
  show_catalog boolean not null default true,
  public_message text check (public_message is null or char_length(public_message) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger public_order_channels_touch_updated_at
  before update on public.public_order_channels
  for each row execute function public.touch_updated_at();

create table public.public_orders (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  reference text not null unique check (reference ~ '^C-[0-9A-HJKMNP-TV-Z]{6}$'),
  tracking_token uuid not null unique default gen_random_uuid(),
  operation_id uuid not null,
  channel text not null check (channel in ('qr', 'social')),
  status text not null default 'new'
    check (status in ('new', 'accepted', 'paid', 'rejected')),
  customer_name text not null check (char_length(customer_name) between 1 and 60),
  customer_phone text not null check (char_length(customer_phone) between 6 and 32),
  fulfillment text not null check (fulfillment in ('pickup', 'delivery')),
  delivery_address text check (delivery_address is null or char_length(delivery_address) <= 240),
  payment_method text not null
    check (payment_method in ('cash', 'mobile_money', 'card', 'bank_transfer')),
  note text check (note is null or char_length(note) <= 500),
  reference_image_path text,
  requested_total numeric(14, 2) not null default 0 check (requested_total >= 0),
  -- Renseigné uniquement par la confirmation en caisse.
  sale_id uuid references public.sales(id),
  paid_method text check (paid_method in ('cash', 'mobile_money', 'card', 'bank_transfer')),
  payment_reference text check (payment_reference is null or char_length(payment_reference) <= 64),
  confirmed_at timestamptz,
  confirmed_by uuid references auth.users(id),
  cashier_profile_id uuid references public.shop_cashier_profiles(id),
  decided_at timestamptz,
  reject_reason text check (reject_reason is null or char_length(reject_reason) <= 240),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, operation_id),
  check ((status = 'paid') = (sale_id is not null and confirmed_at is not null and paid_method is not null))
);
create index public_orders_shop_status_idx on public.public_orders(shop_id, status, created_at desc);
create trigger public_orders_touch_updated_at
  before update on public.public_orders
  for each row execute function public.touch_updated_at();

create table public.public_order_lines (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.public_orders(id) on delete cascade,
  shop_id uuid not null references public.shops(id) on delete cascade,
  position smallint not null check (position between 1 and 20),
  -- Article du stock choisi par le client, ou description libre (boutique sans catalogue publié).
  product_id uuid references public.products(id),
  description text check (description is null or char_length(description) between 1 and 120),
  quantity integer not null check (quantity between 1 and 20),
  listed_unit_price numeric(14, 2) check (listed_unit_price is null or listed_unit_price >= 0),
  proposed_unit_price numeric(14, 2) check (proposed_unit_price is null or proposed_unit_price > 0),
  unique (order_id, position),
  check (product_id is not null or description is not null)
);
create index public_order_lines_order_idx on public.public_order_lines(order_id);

-- Quotas de la passerelle : compteurs par empreinte (HMAC, jamais l'adresse IP en clair).
create table public.public_order_quota (
  digest text not null check (char_length(digest) between 16 and 128),
  kind text not null,
  window_start timestamptz not null,
  hits integer not null default 0,
  primary key (digest, kind, window_start)
);

alter table public.public_order_channels enable row level security;
alter table public.public_orders enable row level security;
alter table public.public_order_lines enable row level security;
alter table public.public_order_quota enable row level security;

revoke all on public.public_order_channels, public.public_orders, public.public_order_lines,
  public.public_order_quota from public, anon, authenticated;

-- Lecture directe réservée au propriétaire : nécessaire au temps réel (Realtime applique la RLS).
-- Aucune écriture directe : tout passe par les fonctions ci-dessous.
grant select on public.public_orders, public.public_order_lines to authenticated;
create policy public_orders_owner_select on public.public_orders
  for select to authenticated
  using (exists (select 1 from public.shops s
                 where s.id = shop_id and s.owner_id = (select auth.uid())));
create policy public_order_lines_owner_select on public.public_order_lines
  for select to authenticated
  using (exists (select 1 from public.shops s
                 where s.id = shop_id and s.owner_id = (select auth.uid())));

-- Notifications temps réel (si la publication Supabase existe : pas dans la base de test).
do $realtime$
begin
  if exists (select 1 from pg_catalog.pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.public_orders;
  end if;
end
$realtime$;

-- Photo de référence facultative (capture de statut WhatsApp, live TikTok…) : privée.
-- Seule la passerelle (clé serveur) dépose ; seul le propriétaire de la boutique lit.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('covi-order-references', 'covi-order-references', false, 400000,
        array['image/jpeg']::text[])
on conflict (id) do nothing;

create policy "COVI owners read order reference images"
on storage.objects for select to authenticated
using (
  bucket_id = 'covi-order-references'
  and exists (
    select 1 from public.shops s
    where s.id::text = (storage.foldername(name))[1]
      and s.owner_id = (select auth.uid())
  )
);

-- Outils internes ---------------------------------------------------------------------------------
create or replace function public.public_order_reference_code()
returns text language plpgsql volatile set search_path to ''
as $fn$
declare
  c_alphabet constant text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  v_bytes bytea := extensions.gen_random_bytes(6);
  v_code text := 'C-';
begin
  for i in 0 .. 5 loop
    v_code := v_code || pg_catalog.substr(c_alphabet, (pg_catalog.get_byte(v_bytes, i) % 32) + 1, 1);
  end loop;
  return v_code;
end;
$fn$;

-- Quota atomique par fenêtre (minute, heure ou jour). Renvoie false quand le plafond est atteint.
create or replace function public.consume_public_order_quota(p_digest text, p_kind text)
returns boolean language plpgsql security definer set search_path to ''
as $fn$
declare
  v_limit integer;
  v_unit text;
  v_window timestamptz;
  v_hits integer;
begin
  select l.max_hits, l.unit into v_limit, v_unit
  from (values
    ('catalog_source_minute', 30, 'minute'),
    ('catalog_link_minute', 300, 'minute'),
    ('status_source_minute', 30, 'minute'),
    ('status_token_minute', 30, 'minute'),
    ('order_source_minute', 3, 'minute'),
    ('order_source_day', 30, 'day'),
    ('order_link_minute', 20, 'minute'),
    ('order_link_day', 500, 'day')
  ) as l(kind, max_hits, unit)
  where l.kind = p_kind;
  if v_limit is null or p_digest is null or p_digest !~ '^[0-9a-f]{16,128}$' then
    raise exception 'Invalid quota request';
  end if;
  v_window := pg_catalog.date_trunc(v_unit, pg_catalog.clock_timestamp());
  insert into public.public_order_quota (digest, kind, window_start, hits)
  values (p_digest, p_kind, v_window, 1)
  on conflict (digest, kind, window_start)
    do update set hits = public.public_order_quota.hits + 1
  returning hits into v_hits;
  -- Ménage léger : les fenêtres de plus de deux jours ne servent plus.
  if pg_catalog.random() < 0.02 then
    delete from public.public_order_quota
    where window_start < pg_catalog.clock_timestamp() - interval '2 days';
  end if;
  return v_hits <= v_limit;
end;
$fn$;

-- Catalogue public : articles réellement en stock (ni test, ni archivés, ni vendus), prix affiché,
-- quantité commandable plafonnée. Jamais : coût d'achat, arrivage, fournisseur, stock exact au-delà
-- de 20, ventes ou autres boutiques.
create or replace function public.get_public_order_catalog(p_token uuid)
returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
declare
  v_channel public.public_order_channels%rowtype;
  v_shop public.shops%rowtype;
  v_products jsonb := '[]'::jsonb;
begin
  select * into v_channel from public.public_order_channels c
  where c.token = p_token and c.enabled;
  if not found then return null; end if;
  select * into v_shop from public.shops s where s.id = v_channel.shop_id;
  if v_channel.show_catalog then
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', p.id, 'name', p.name, 'category', p.category, 'brand', p.brand, 'size', p.size,
        'priceXaf', p.initial_sale_price,
        'maxQuantity', case when p.is_unique_piece then 1 else least(p.quantity_on_hand, 20) end)
        order by p.category nulls last, p.name, p.id), '[]'::jsonb)
      into v_products
    from (
      select * from public.products p
      where p.shop_id = v_channel.shop_id and p.status = 'active' and not p.is_test
        and p.quantity_on_hand > 0
      order by p.category nulls last, p.name, p.id
      limit 500
    ) p;
  end if;
  return pg_catalog.jsonb_build_object(
    'shopName', v_shop.name, 'city', v_shop.city, 'neighborhood', v_shop.neighborhood,
    'message', v_channel.public_message, 'showCatalog', v_channel.show_catalog,
    'products', v_products);
end;
$fn$;

-- Dépôt d'une demande client (via la passerelle uniquement). Idempotent par operation_id.
create or replace function public.submit_public_order(
  p_token uuid,
  p_channel text,
  p_operation_id uuid,
  p_customer_name text,
  p_customer_phone text,
  p_fulfillment text,
  p_delivery_address text,
  p_payment_method text,
  p_note text,
  p_lines jsonb
)
returns jsonb language plpgsql security definer set search_path to ''
as $fn$
declare
  c_uuid_re constant text :=
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_channel public.public_order_channels%rowtype;
  v_name text := pg_catalog.btrim(p_customer_name);
  v_phone text := pg_catalog.btrim(p_customer_phone);
  v_address text := nullif(pg_catalog.btrim(p_delivery_address), '');
  v_note text := nullif(pg_catalog.btrim(p_note), '');
  v_order public.public_orders%rowtype;
  v_count integer;
  v_item jsonb;
  v_product public.products%rowtype;
  v_qty integer;
  v_proposed numeric;
  v_desc text;
  v_total numeric := 0;
  v_seen uuid[] := '{}';
  v_reference text;
begin
  select * into v_channel from public.public_order_channels c
  where c.token = p_token and c.enabled;
  if not found then raise exception 'Order link unavailable' using errcode = '42501'; end if;

  if p_operation_id is null or p_channel is null or p_channel not in ('qr', 'social')
     or p_fulfillment is null or p_fulfillment not in ('pickup', 'delivery')
     or p_payment_method is null
     or p_payment_method not in ('cash', 'mobile_money', 'card', 'bank_transfer') then
    raise exception 'Invalid order parameters';
  end if;
  if v_name is null or char_length(v_name) not between 1 and 60 or v_name ~ '[[:cntrl:]]'
     or v_phone is null or v_phone !~ '^\+?[0-9 ().-]{6,32}$'
     or char_length(coalesce(v_address, '')) > 240 or coalesce(v_address ~ '[[:cntrl:]]', false)
     or char_length(coalesce(v_note, '')) > 500 or coalesce(v_note ~ '[\x01-\x09\x0b-\x1f\x7f]', false)
     or (p_fulfillment = 'delivery' and v_address is null) then
    raise exception 'Invalid customer details';
  end if;
  if p_lines is null or pg_catalog.jsonb_typeof(p_lines) <> 'array' then
    raise exception 'Invalid order lines';
  end if;
  v_count := pg_catalog.jsonb_array_length(p_lines);
  if v_count < 1 or v_count > 20 then raise exception 'Invalid order lines'; end if;

  -- Une seule commande par operation_id, même si deux envois se croisent.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'covi:public-order:' || v_channel.shop_id::text || ':' || p_operation_id::text, 0));
  select * into v_order from public.public_orders o
  where o.shop_id = v_channel.shop_id and o.operation_id = p_operation_id;
  if found then
    return pg_catalog.jsonb_build_object(
      'orderId', v_order.id, 'reference', v_order.reference,
      'trackingToken', v_order.tracking_token, 'status', v_order.status,
      'amountXaf', v_order.requested_total, 'shopId', v_order.shop_id);
  end if;

  loop
    v_reference := public.public_order_reference_code();
    exit when not exists (select 1 from public.public_orders o where o.reference = v_reference);
  end loop;

  insert into public.public_orders (
    shop_id, reference, operation_id, channel, customer_name, customer_phone, fulfillment,
    delivery_address, payment_method, note)
  values (v_channel.shop_id, v_reference, p_operation_id, p_channel, v_name, v_phone,
    p_fulfillment, case when p_fulfillment = 'delivery' then v_address end,
    p_payment_method, v_note)
  returning * into v_order;

  for i in 0 .. v_count - 1 loop
    v_item := p_lines -> i;
    if pg_catalog.jsonb_typeof(v_item) <> 'object'
       or exists (select 1 from pg_catalog.jsonb_object_keys(v_item) k
                  where k not in ('productId', 'description', 'quantity', 'proposedUnitPriceXaf'))
       or pg_catalog.jsonb_typeof(v_item -> 'quantity') is distinct from 'number'
       or (v_item ->> 'quantity') !~ '^([1-9]|1[0-9]|20)$' then
      raise exception 'Invalid order lines';
    end if;
    v_qty := (v_item ->> 'quantity')::integer;
    v_proposed := null;
    if v_item ? 'proposedUnitPriceXaf' and pg_catalog.jsonb_typeof(v_item -> 'proposedUnitPriceXaf') <> 'null' then
      if pg_catalog.jsonb_typeof(v_item -> 'proposedUnitPriceXaf') <> 'number'
         or (v_item ->> 'proposedUnitPriceXaf') !~ '^[1-9][0-9]{0,8}$' then
        raise exception 'Invalid order lines';
      end if;
      v_proposed := (v_item ->> 'proposedUnitPriceXaf')::numeric;
    end if;

    if v_item ? 'productId' and pg_catalog.jsonb_typeof(v_item -> 'productId') <> 'null' then
      if not v_channel.show_catalog
         or pg_catalog.jsonb_typeof(v_item -> 'productId') <> 'string'
         or (v_item ->> 'productId') !~ c_uuid_re then
        raise exception 'Invalid order lines';
      end if;
      select * into v_product from public.products p
      where p.id = (v_item ->> 'productId')::uuid and p.shop_id = v_channel.shop_id
        and p.status = 'active' and not p.is_test;
      if not found or v_product.id = any(v_seen) then
        raise exception 'Product unavailable';
      end if;
      if v_product.quantity_on_hand < v_qty or (v_product.is_unique_piece and v_qty <> 1) then
        raise exception 'Insufficient stock';
      end if;
      v_seen := v_seen || v_product.id;
      insert into public.public_order_lines (order_id, shop_id, position, product_id, quantity,
        listed_unit_price, proposed_unit_price)
      values (v_order.id, v_order.shop_id, i + 1, v_product.id, v_qty,
        v_product.initial_sale_price, v_proposed);
      v_total := v_total + v_qty * coalesce(v_proposed, v_product.initial_sale_price);
    else
      v_desc := pg_catalog.btrim(v_item ->> 'description');
      if pg_catalog.jsonb_typeof(v_item -> 'description') is distinct from 'string'
         or v_desc is null or char_length(v_desc) not between 1 and 120
         or v_desc ~ '[[:cntrl:]]' then
        raise exception 'Invalid order lines';
      end if;
      insert into public.public_order_lines (order_id, shop_id, position, description, quantity,
        proposed_unit_price)
      values (v_order.id, v_order.shop_id, i + 1, v_desc, v_qty, v_proposed);
      v_total := v_total + v_qty * coalesce(v_proposed, 0);
    end if;
  end loop;

  update public.public_orders set requested_total = v_total where id = v_order.id
  returning * into v_order;

  return pg_catalog.jsonb_build_object(
    'orderId', v_order.id, 'reference', v_order.reference,
    'trackingToken', v_order.tracking_token, 'status', v_order.status,
    'amountXaf', v_order.requested_total, 'shopId', v_order.shop_id);
end;
$fn$;

-- Rattache la photo déposée par la passerelle (chemin imposé : <boutique>/<commande>/reference.jpg).
create or replace function public.attach_public_order_reference(
  p_token uuid, p_order_id uuid, p_operation_id uuid)
returns text language plpgsql security definer set search_path to ''
as $fn$
declare
  v_order public.public_orders%rowtype;
  v_path text;
begin
  select o.* into v_order from public.public_orders o
  join public.public_order_channels c on c.shop_id = o.shop_id
  where o.id = p_order_id and o.operation_id = p_operation_id and c.token = p_token and c.enabled
    and o.status = 'new' and o.created_at > now() - interval '10 minutes';
  if not found then return null; end if;
  v_path := v_order.shop_id::text || '/' || v_order.id::text || '/reference.jpg';
  update public.public_orders set reference_image_path = v_path where id = v_order.id;
  return v_path;
end;
$fn$;

-- Suivi par le client : uniquement avec le jeton de suivi propre à sa commande.
create or replace function public.get_public_order_status(p_tracking_token uuid)
returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
declare
  v_order public.public_orders%rowtype;
  v_shop_name text;
  v_lines jsonb;
  v_receipt jsonb;
begin
  select * into v_order from public.public_orders o where o.tracking_token = p_tracking_token;
  if not found then return null; end if;
  select s.name into v_shop_name from public.shops s where s.id = v_order.shop_id;
  if v_order.status = 'paid' then
    select pg_catalog.jsonb_build_object(
      'receiptNumber', pg_catalog.upper(pg_catalog.substr(v.id::text, 1, 8)),
      'confirmedAt', v_order.confirmed_at,
      'method', v_order.paid_method,
      'totalXaf', v.total_amount,
      'cashierName', (select c.display_name from public.shop_cashier_profiles c
                      where c.id = v_order.cashier_profile_id),
      'lines', (select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                  'label', p.name, 'quantity', i.quantity, 'unitPriceXaf', i.sold_unit_price)
                  order by p.name), '[]'::jsonb)
                from public.sale_items i join public.products p on p.id = i.product_id
                where i.sale_id = v.id))
      into v_receipt
    from public.sales v where v.id = v_order.sale_id;
  end if;
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'label', coalesce(p.name, l.description), 'quantity', l.quantity,
      'unitPriceXaf', coalesce(l.proposed_unit_price, l.listed_unit_price))
      order by l.position), '[]'::jsonb)
    into v_lines
  from public.public_order_lines l left join public.products p on p.id = l.product_id
  where l.order_id = v_order.id;
  return pg_catalog.jsonb_build_object(
    'shopName', v_shop_name, 'reference', v_order.reference, 'status', v_order.status,
    'createdAt', v_order.created_at, 'fulfillment', v_order.fulfillment,
    'paymentMethod', v_order.payment_method, 'amountXaf', v_order.requested_total,
    'lines', v_lines, 'rejectReason', v_order.reject_reason, 'receipt', v_receipt);
end;
$fn$;

-- Administration du canal (propriétaire) -----------------------------------------------------------
create or replace function public.get_public_order_channel(p_shop_id uuid)
returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
declare
  v_channel public.public_order_channels%rowtype;
begin
  perform public.assert_shop_owner(p_shop_id);
  select * into v_channel from public.public_order_channels c where c.shop_id = p_shop_id;
  if not found then return null; end if;
  return pg_catalog.jsonb_build_object('token', v_channel.token, 'enabled', v_channel.enabled,
    'showCatalog', v_channel.show_catalog, 'message', v_channel.public_message);
end;
$fn$;

create or replace function public.configure_public_order_channel(
  p_shop_id uuid, p_enabled boolean, p_show_catalog boolean, p_message text)
returns jsonb language plpgsql security definer set search_path to ''
as $fn$
declare
  v_message text := nullif(pg_catalog.btrim(p_message), '');
begin
  perform public.assert_shop_owner(p_shop_id);
  if p_enabled is null or p_show_catalog is null
     or char_length(coalesce(v_message, '')) > 500
     or coalesce(v_message ~ '[\x01-\x09\x0b-\x1f\x7f]', false) then
    raise exception 'Invalid channel settings';
  end if;
  insert into public.public_order_channels (shop_id, enabled, show_catalog, public_message)
  values (p_shop_id, p_enabled, p_show_catalog, v_message)
  on conflict (shop_id) do update
    set enabled = excluded.enabled, show_catalog = excluded.show_catalog,
        public_message = excluded.public_message;
  perform public.shop_audit(p_shop_id, 'public_order_channel_configured', null,
    pg_catalog.jsonb_build_object('enabled', p_enabled, 'show_catalog', p_show_catalog));
  return public.get_public_order_channel(p_shop_id);
end;
$fn$;

-- Invalide l'ancien lien et l'ancien QR (lien partagé par erreur, abus).
create or replace function public.rotate_public_order_channel(p_shop_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $fn$
begin
  perform public.assert_shop_owner(p_shop_id);
  update public.public_order_channels set token = gen_random_uuid() where shop_id = p_shop_id;
  if not found then raise exception 'No order channel'; end if;
  perform public.shop_audit(p_shop_id, 'public_order_channel_rotated', null, '{}'::jsonb);
  return public.get_public_order_channel(p_shop_id);
end;
$fn$;

-- Commandes reçues (propriétaire / compte de gestion partagé) ---------------------------------------
create or replace function public.list_public_orders(p_shop_id uuid, p_include_closed boolean default false)
returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
begin
  perform public.assert_shop_owner(p_shop_id);
  return coalesce((
    select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'id', o.id, 'reference', o.reference, 'status', o.status, 'channel', o.channel,
      'createdAt', o.created_at, 'customerName', o.customer_name,
      'customerPhone', o.customer_phone, 'fulfillment', o.fulfillment,
      'deliveryAddress', o.delivery_address, 'paymentMethod', o.payment_method,
      'note', o.note, 'referenceImagePath', o.reference_image_path,
      'requestedTotalXaf', o.requested_total, 'saleId', o.sale_id, 'paidMethod', o.paid_method,
      'paymentReference', o.payment_reference, 'confirmedAt', o.confirmed_at,
      'cashierName', (select c.display_name from public.shop_cashier_profiles c
                      where c.id = o.cashier_profile_id),
      'rejectReason', o.reject_reason,
      'lines', (select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', l.id, 'productId', l.product_id, 'description', l.description,
          'productName', p.name, 'quantity', l.quantity,
          'listedUnitPriceXaf', l.listed_unit_price,
          'proposedUnitPriceXaf', l.proposed_unit_price,
          'currentPriceXaf', p.initial_sale_price,
          'availableQuantity', case when p.status = 'active' then p.quantity_on_hand else 0 end)
          order by l.position), '[]'::jsonb)
        from public.public_order_lines l left join public.products p on p.id = l.product_id
        where l.order_id = o.id))
      order by (o.status in ('new', 'accepted')) desc, o.created_at desc)
    from (
      select * from public.public_orders o
      where o.shop_id = p_shop_id
        and (p_include_closed or o.status in ('new', 'accepted')
             or o.updated_at > now() - interval '2 days')
      order by o.created_at desc
      limit 200
    ) o), '[]'::jsonb);
end;
$fn$;

create or replace function public.accept_public_order(p_order_id uuid)
returns text language plpgsql security definer set search_path to ''
as $fn$
declare
  v_order public.public_orders%rowtype;
begin
  select * into v_order from public.public_orders where id = p_order_id for update;
  if not found then raise exception 'Order not found' using errcode = '42501'; end if;
  perform public.assert_shop_owner(v_order.shop_id);
  if v_order.status = 'accepted' then return 'accepted'; end if;
  if v_order.status <> 'new' then raise exception 'Order already closed'; end if;
  update public.public_orders set status = 'accepted', decided_at = now() where id = p_order_id;
  return 'accepted';
end;
$fn$;

create or replace function public.reject_public_order(p_order_id uuid, p_reason text)
returns text language plpgsql security definer set search_path to ''
as $fn$
declare
  v_order public.public_orders%rowtype;
  v_reason text := nullif(pg_catalog.btrim(p_reason), '');
begin
  select * into v_order from public.public_orders where id = p_order_id for update;
  if not found then raise exception 'Order not found' using errcode = '42501'; end if;
  perform public.assert_shop_owner(v_order.shop_id);
  if v_order.status = 'rejected' then return 'rejected'; end if;
  if v_order.status not in ('new', 'accepted') then raise exception 'Order already closed'; end if;
  if char_length(coalesce(v_reason, '')) > 240 or coalesce(v_reason ~ '[[:cntrl:]]', false) then
    raise exception 'Invalid reason';
  end if;
  update public.public_orders
  set status = 'rejected', decided_at = now(), reject_reason = v_reason
  where id = p_order_id;
  return 'rejected';
end;
$fn$;

-- Confirmation du règlement réellement reçu, en caisse.
-- p_lines : [{ lineId, productId, unitPriceXaf }] pour CHAQUE ligne de la commande : le caissier
-- confirme l'article du stock (obligatoire pour une description libre) et le prix final.
-- La vente passe par record_cart_sale : PIN du caissier (p_till_session), remise maximale,
-- verrou et contrôle du stock, attribution au caissier. Clé d'idempotence = id de la commande :
-- un second clic, un double appareil ou un nouvel essai réseau ne crée jamais une seconde vente.
create or replace function public.confirm_public_order_payment(
  p_order_id uuid,
  p_paid_method text,
  p_payment_reference text,
  p_payment_verified boolean,
  p_lines jsonb,
  p_till_session text default null
)
returns jsonb language plpgsql security definer set search_path to ''
as $fn$
declare
  c_uuid_re constant text :=
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_order public.public_orders%rowtype;
  v_ref text := nullif(pg_catalog.btrim(p_payment_reference), '');
  v_items jsonb := '[]'::jsonb;
  v_line public.public_order_lines%rowtype;
  v_item jsonb;
  v_product_id uuid;
  v_price numeric;
  v_sale_id uuid;
  v_sale public.sales%rowtype;
begin
  select * into v_order from public.public_orders where id = p_order_id for update;
  if not found then raise exception 'Order not found' using errcode = '42501'; end if;
  perform public.assert_shop_owner(v_order.shop_id);
  if v_order.status = 'paid' then
    return pg_catalog.jsonb_build_object('status', 'paid', 'saleId', v_order.sale_id,
      'alreadyConfirmed', true);
  end if;
  if v_order.status not in ('new', 'accepted') then raise exception 'Order already closed'; end if;
  if p_payment_verified is not true then raise exception 'Payment not verified'; end if;
  if p_paid_method is null or p_paid_method not in ('cash', 'mobile_money', 'card', 'bank_transfer') then
    raise exception 'Invalid payment method';
  end if;
  if char_length(coalesce(v_ref, '')) > 64 or coalesce(v_ref ~ '[[:cntrl:]]', false) then
    raise exception 'Invalid payment reference';
  end if;
  if p_lines is null or pg_catalog.jsonb_typeof(p_lines) <> 'array'
     or pg_catalog.jsonb_array_length(p_lines)
        <> (select count(*) from public.public_order_lines l where l.order_id = v_order.id) then
    raise exception 'Every order line must be confirmed';
  end if;

  for v_line in select * from public.public_order_lines l where l.order_id = v_order.id
                order by l.position loop
    select e.value into v_item from pg_catalog.jsonb_array_elements(p_lines) e
    where e.value ->> 'lineId' = v_line.id::text;
    if v_item is null
       or (v_item ->> 'productId') is null or (v_item ->> 'productId') !~ c_uuid_re
       or pg_catalog.jsonb_typeof(v_item -> 'unitPriceXaf') is distinct from 'number' then
      raise exception 'Every order line must be confirmed';
    end if;
    v_product_id := (v_item ->> 'productId')::uuid;
    v_price := (v_item ->> 'unitPriceXaf')::numeric;
    if v_line.product_id is not null and v_line.product_id <> v_product_id then
      raise exception 'Order line product mismatch';
    end if;
    if not exists (select 1 from public.products p
                   where p.id = v_product_id and p.shop_id = v_order.shop_id) then
      raise exception 'Product unavailable';
    end if;
    v_items := v_items || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'product_id', v_product_id, 'quantity', v_line.quantity, 'sold_unit_price', v_price));
  end loop;

  -- Toutes les règles de la caisse s'appliquent (PIN, remise, stock, doublons d'article).
  v_sale_id := public.record_cart_sale(v_order.shop_id, v_items, p_paid_method, v_order.id,
                                       p_till_session);
  select * into v_sale from public.sales where id = v_sale_id;

  update public.public_orders
  set status = 'paid', sale_id = v_sale_id, paid_method = p_paid_method,
      payment_reference = v_ref, confirmed_at = now(), confirmed_by = auth.uid(),
      cashier_profile_id = v_sale.cashier_profile_id,
      decided_at = coalesce(decided_at, now())
  where id = v_order.id;
  update public.public_order_lines l set product_id = (e.value ->> 'productId')::uuid
  from pg_catalog.jsonb_array_elements(p_lines) e
  where l.order_id = v_order.id and e.value ->> 'lineId' = l.id::text and l.product_id is null;

  perform public.shop_audit(v_order.shop_id, 'public_order_paid', v_order.id::text,
    pg_catalog.jsonb_build_object('sale_id', v_sale_id, 'method', p_paid_method));
  return pg_catalog.jsonb_build_object('status', 'paid', 'saleId', v_sale_id,
    'alreadyConfirmed', false);
end;
$fn$;

-- Droits : rien pour anon. Passerelle (service_role) d'un côté, propriétaire de l'autre. ------------
revoke all on function public.public_order_reference_code() from public, anon, authenticated;
revoke all on function public.consume_public_order_quota(text, text) from public, anon, authenticated;
revoke all on function public.get_public_order_catalog(uuid) from public, anon, authenticated;
revoke all on function public.submit_public_order(uuid, text, uuid, text, text, text, text, text, text, jsonb)
  from public, anon, authenticated;
revoke all on function public.attach_public_order_reference(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.get_public_order_status(uuid) from public, anon, authenticated;
grant execute on function public.consume_public_order_quota(text, text) to service_role;
grant execute on function public.get_public_order_catalog(uuid) to service_role;
grant execute on function public.submit_public_order(uuid, text, uuid, text, text, text, text, text, text, jsonb)
  to service_role;
grant execute on function public.attach_public_order_reference(uuid, uuid, uuid) to service_role;
grant execute on function public.get_public_order_status(uuid) to service_role;

revoke all on function public.get_public_order_channel(uuid) from public, anon;
revoke all on function public.configure_public_order_channel(uuid, boolean, boolean, text) from public, anon;
revoke all on function public.rotate_public_order_channel(uuid) from public, anon;
revoke all on function public.list_public_orders(uuid, boolean) from public, anon;
revoke all on function public.accept_public_order(uuid) from public, anon;
revoke all on function public.reject_public_order(uuid, text) from public, anon;
revoke all on function public.confirm_public_order_payment(uuid, text, text, boolean, jsonb, text)
  from public, anon;
grant execute on function public.get_public_order_channel(uuid) to authenticated;
grant execute on function public.configure_public_order_channel(uuid, boolean, boolean, text) to authenticated;
grant execute on function public.rotate_public_order_channel(uuid) to authenticated;
grant execute on function public.list_public_orders(uuid, boolean) to authenticated;
grant execute on function public.accept_public_order(uuid) to authenticated;
grant execute on function public.reject_public_order(uuid, text) to authenticated;
grant execute on function public.confirm_public_order_payment(uuid, text, text, boolean, jsonb, text)
  to authenticated;
