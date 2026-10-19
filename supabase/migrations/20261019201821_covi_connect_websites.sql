-- COVI Connect V1: one server-side credential per merchant website.
-- Keys are generated as 256-bit secrets; only SHA-256 digests are persisted.
-- Orders from websites are REQUESTS, not paid sales; cashier confirms actual payment.
create table public.website_connections (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  label text not null check (char_length(label) between 1 and 80),
  site_url text not null check (char_length(site_url) between 12 and 255),
  key_hash text not null unique check (key_hash ~ '^[0-9a-f]{64}$'),
  key_prefix text not null check (char_length(key_prefix) between 8 and 32),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at timestamptz
);
create index website_connections_shop_idx on public.website_connections(shop_id,created_at desc);
alter table public.website_connections enable row level security;
revoke all on public.website_connections from public,anon,authenticated;

create table public.website_order_map (
  connection_id uuid not null references public.website_connections(id) on delete cascade,
  external_order_id text not null check (char_length(external_order_id) between 1 and 100),
  order_id uuid not null unique references public.public_orders(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (connection_id, external_order_id)
);
alter table public.website_order_map enable row level security;
revoke all on public.website_order_map from public,anon,authenticated;

create table public.website_api_quota (
  connection_id uuid not null references public.website_connections(id) on delete cascade,
  action text not null check (action in ('products','orders','status')),
  window_start timestamptz not null,
  hits integer not null default 0 check (hits >= 0),
  primary key(connection_id,action,window_start)
);
alter table public.website_api_quota enable row level security;
revoke all on public.website_api_quota from public,anon,authenticated;

-- The website uses a separate request channel; never bypass the cash register.
alter table public.public_orders drop constraint if exists public_orders_channel_check;
alter table public.public_orders add constraint public_orders_channel_check
  check (channel in ('qr','social','website'));

create function public.create_website_connection(
  p_shop_id uuid, p_label text, p_site_url text
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare
 v_token text := 'covi_site_' || pg_catalog.encode(extensions.gen_random_bytes(32),'hex');
 v_row public.website_connections%rowtype;
 v_label text := pg_catalog.btrim(p_label);
 v_url text := pg_catalog.btrim(p_site_url);
begin
 perform public.assert_shop_owner(p_shop_id);
 if v_label is null or char_length(v_label) not between 1 and 80
    or v_label ~ '[[:cntrl:]]'
    or v_url is null or char_length(v_url) not between 12 and 255
    or v_url !~ '^https://[A-Za-z0-9][A-Za-z0-9.-]+(:[0-9]{2,5})?(/[^[:cntrl:]]*)?$'
    or v_url ~ '@'
    or exists(select 1 from public.website_connections c where c.shop_id=p_shop_id and c.active
              having count(*) >= 10) then
   raise exception 'Invalid website connection' using errcode='22023';
 end if;
 insert into public.website_connections(shop_id,label,site_url,key_hash,key_prefix)
 values(p_shop_id,v_label,v_url,pg_catalog.encode(extensions.digest(v_token,'sha256'),'hex'),
        pg_catalog.substr(v_token,1,22))
 returning * into v_row;
 perform public.shop_audit(p_shop_id,'website_connection_created',v_row.id::text,
   pg_catalog.jsonb_build_object('label',v_label));
 return pg_catalog.jsonb_build_object('id',v_row.id,'label',v_row.label,
   'siteUrl',v_row.site_url,'secret',v_token,'createdAt',v_row.created_at);
end;
$$;

create function public.list_website_connections(p_shop_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_result jsonb;
begin
 perform public.assert_shop_owner(p_shop_id);
 select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
   'id', c.id, 'label',c.label,'siteUrl',c.site_url,
   'keyPrefix',c.key_prefix,'active',c.active,
   'createdAt',c.created_at,'lastUsedAt',c.last_used_at)
   order by c.created_at desc),'[]'::jsonb)
 into v_result from public.website_connections c where c.shop_id=p_shop_id;
 return v_result;
end;
$$;

create function public.revoke_website_connection(p_connection_id uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_shop uuid;
begin
 select c.shop_id into v_shop from public.website_connections c where c.id=p_connection_id;
 if v_shop is null then raise exception 'Connection not found' using errcode='42501'; end if;
 perform public.assert_shop_owner(v_shop);
 update public.website_connections
   set active=false,revoked_at=now()
   where id=p_connection_id and active;
 if found then
   perform public.shop_audit(v_shop,'website_connection_revoked',p_connection_id::text,'{}'::jsonb);
 end if;
 return true;
end;
$$;

-- Called ONLY with a server-side service_role, never an anonymous frontend.
create function public.authorize_website_connection(p_secret text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_row public.website_connections%rowtype;
begin
 if p_secret is null or p_secret !~ '^covi_site_[0-9a-f]{64}$' then return null; end if;
 select * into v_row from public.website_connections c
   where c.key_hash=pg_catalog.encode(extensions.digest(p_secret,'sha256'),'hex')
     and c.active;
 if not found then return null; end if;
 update public.website_connections set last_used_at=now() where id=v_row.id;
 return pg_catalog.jsonb_build_object('id',v_row.id,'shopId',v_row.shop_id);
end;
$$;

create function public.consume_website_api_quota(p_connection_id uuid,p_action text)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_limit int; v_hits int; v_window timestamptz;
begin
 v_limit := case p_action when 'products' then 120 when 'orders' then 30
                        when 'status' then 120 else null end;
 if v_limit is null then return false; end if;
 v_window := pg_catalog.date_trunc('minute',pg_catalog.clock_timestamp());
 insert into public.website_api_quota(connection_id,action,window_start,hits)
 values(p_connection_id,p_action,v_window,1)
 on conflict(connection_id,action,window_start) do update
 set hits=public.website_api_quota.hits+1 returning hits into v_hits;
 return v_hits<=v_limit;
end;
$$;

-- Idempotent website order creation. A website is NOT a trusted payment processor.
-- No writes to sales or products take place here.
create function public.import_website_order(
 p_connection_id uuid, p_external_order_id text,
 p_customer_name text, p_customer_phone text,
 p_payment_method text, p_fulfillment text, p_delivery_address text,
 p_lines jsonb
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare
 v_shop uuid;
 v_order_id uuid;
 v_ref text;
 v_name text := pg_catalog.btrim(p_customer_name);
 v_phone text := pg_catalog.btrim(p_customer_phone);
 v_address text := nullif(pg_catalog.btrim(p_delivery_address),'');
 v_external text := pg_catalog.btrim(p_external_order_id);
 v_count int;
 v_item jsonb;
 v_product public.products%rowtype;
 v_qty int;
 v_total numeric := 0;
 v_seen uuid[] := '{}';
 v_state text;
begin
 select c.shop_id into v_shop from public.website_connections c
   where c.id=p_connection_id and c.active;
 if v_shop is null then raise exception 'Website access denied' using errcode='42501'; end if;
 if v_external is null or char_length(v_external) not between 1 and 100
    or v_external ~ '[[:cntrl:]]'
    or v_name is null or char_length(v_name) not between 1 and 60 or v_name ~ '[[:cntrl:]]'
    or v_phone is null or v_phone !~ '^\+?[0-9 ().-]{6,32}$'
    or p_payment_method not in ('cash','mobile_money','card','bank_transfer')
    or p_payment_method is null
    or p_fulfillment not in ('pickup','delivery') or p_fulfillment is null
    or char_length(coalesce(v_address,''))>240
    or coalesce(v_address ~ '[[:cntrl:]]',false)
    or (p_fulfillment='delivery' and v_address is null) then
   raise exception 'Invalid website order' using errcode='22023';
 end if;
 if p_lines is null or pg_catalog.jsonb_typeof(p_lines)<>'array' then
   raise exception 'Invalid website lines' using errcode='22023'; end if;
 v_count:=pg_catalog.jsonb_array_length(p_lines);
 if v_count<1 or v_count>20 then raise exception 'Invalid website lines' using errcode='22023'; end if;
 perform pg_catalog.pg_advisory_xact_lock(
   pg_catalog.hashtextextended('covi:website:'||p_connection_id::text||':'||v_external,0));
 select m.order_id into v_order_id from public.website_order_map m
 where m.connection_id=p_connection_id and m.external_order_id=v_external;
 if v_order_id is not null then
   select o.status into v_state from public.public_orders o where o.id=v_order_id;
   return pg_catalog.jsonb_build_object('orderId',v_order_id,'status',v_state,'alreadyImported',true);
 end if;
 loop
   v_ref:=public.public_order_reference_code();
   exit when not exists(select 1 from public.public_orders o where o.reference=v_ref);
 end loop;
 insert into public.public_orders(
  shop_id,reference,operation_id,channel,customer_name,customer_phone,
  fulfillment,delivery_address,payment_method,note
 ) values (v_shop,v_ref,gen_random_uuid(),'website',v_name,v_phone,p_fulfillment,
   case when p_fulfillment='delivery' then v_address end,p_payment_method,
   'Commande issue du site internet')
 returning id into v_order_id;

 for i in 0..v_count-1 loop
   v_item:=p_lines->i;
   if pg_catalog.jsonb_typeof(v_item)<>'object'
      or exists(select 1 from pg_catalog.jsonb_object_keys(v_item) k
                where k not in ('productId','quantity'))
      or pg_catalog.jsonb_typeof(v_item->'productId')<>'string'
      or (v_item->>'productId') !~ '^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$'
      or pg_catalog.jsonb_typeof(v_item->'quantity')<>'number'
      or (v_item->>'quantity') !~ '^([1-9]|1[0-9]|20)$' then
     raise exception 'Invalid website lines' using errcode='22023';
   end if;
   v_qty := (v_item->>'quantity')::int;
   select * into v_product from public.products p
     where p.id=(v_item->>'productId')::uuid and p.shop_id=v_shop
       and p.status='active' and not p.is_test;
   if not found or v_product.id=any(v_seen) then
     raise exception 'Product unavailable' using errcode='22023';
   end if;
   if v_product.quantity_on_hand<v_qty or (v_product.is_unique_piece and v_qty<>1) then
     raise exception 'Insufficient stock' using errcode='22023';
   end if;
   v_seen:=v_seen||v_product.id;
   insert into public.public_order_lines(
    order_id,shop_id,position,product_id,quantity,listed_unit_price)
   values(v_order_id,v_shop,i+1,v_product.id,v_qty,v_product.initial_sale_price);
   v_total:=v_total+v_qty*v_product.initial_sale_price;
 end loop;
 update public.public_orders set requested_total=v_total where id=v_order_id;
 insert into public.website_order_map(connection_id,external_order_id,order_id)
 values(p_connection_id,v_external,v_order_id);
 perform public.shop_audit(v_shop,'website_order_received',v_order_id::text,
   pg_catalog.jsonb_build_object('connection_id',p_connection_id));
 return pg_catalog.jsonb_build_object(
   'orderId',v_order_id,'reference',v_ref,'status','new',
   'amountXaf',v_total,'alreadyImported',false);
end;
$$;

create function public.get_website_order_state(p_connection_id uuid,p_external_order_id text)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_result jsonb;
begin
 select pg_catalog.jsonb_build_object(
  'orderId',o.id,'reference',o.reference,'status',o.status,
  'amountXaf',o.requested_total,'updatedAt',o.updated_at)
 into v_result from public.website_order_map m
 join public.public_orders o on o.id=m.order_id
 join public.website_connections c on c.id=m.connection_id and c.shop_id=o.shop_id
 where m.connection_id=p_connection_id and c.active and m.external_order_id=p_external_order_id;
 return v_result;
end;
$$;

-- Locks on the API surface. SECURITY DEFINER routines never inherit PUBLIC EXECUTE.
revoke all on function public.create_website_connection(uuid,text,text) from public,anon,authenticated;
revoke all on function public.list_website_connections(uuid) from public,anon,authenticated;
revoke all on function public.revoke_website_connection(uuid) from public,anon,authenticated;
revoke all on function public.authorize_website_connection(text) from public,anon,authenticated;
revoke all on function public.consume_website_api_quota(uuid,text) from public,anon,authenticated;
revoke all on function public.import_website_order(uuid,text,text,text,text,text,text,jsonb)
 from public,anon,authenticated;
revoke all on function public.get_website_order_state(uuid,text) from public,anon,authenticated;
grant execute on function public.create_website_connection(uuid,text,text) to authenticated;
grant execute on function public.list_website_connections(uuid) to authenticated;
grant execute on function public.revoke_website_connection(uuid) to authenticated;
grant execute on function public.authorize_website_connection(text) to service_role;
grant execute on function public.consume_website_api_quota(uuid,text) to service_role;
grant execute on function public.import_website_order(uuid,text,text,text,text,text,text,jsonb) to service_role;
grant execute on function public.get_website_order_state(uuid,text) to service_role;
