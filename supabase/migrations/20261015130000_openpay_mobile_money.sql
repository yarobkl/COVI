-- Paiement Mobile Money (MTN, Airtel) des commandes en ligne via OpenPay (openpay.cg).
--
-- Chaque boutique encaisse sur SON compte OpenPay : COVI ne touche jamais l'argent. La clé API de
-- la boutique est chiffrée dans Supabase Vault ; elle n'est jamais relue par le navigateur, seule
-- la fonction Edge « openpay » (clé serveur) la lit pour appeler OpenPay.
--
-- Déroulé : la boutique demande le paiement d'une commande (montant, numéro, opérateur) ; le client
-- valide sur son téléphone ; OpenPay prévient COVI (callback) et COVI RELIT toujours le statut chez
-- OpenPay avant de l'enregistrer (le callback n'est pas signé). Un paiement « success » est une
-- preuve réelle, mais la vente reste confirmée en caisse (articles du stock, PIN) : aucun stock ne
-- bouge ici. Aucune vente, aucun stock, aucune boutique existante n'est modifié.

create table public.shop_openpay_settings (
  shop_id uuid primary key references public.shops(id) on delete cascade,
  secret_id uuid not null,
  key_hint text not null check (char_length(key_hint) between 1 and 8),
  enabled boolean not null default true,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);
alter table public.shop_openpay_settings enable row level security;
revoke all on public.shop_openpay_settings from anon, authenticated;

create table public.public_order_payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.public_orders(id) on delete cascade,
  shop_id uuid not null references public.shops(id) on delete cascade,
  provider text not null check (provider in ('MTN', 'AIRTEL')),
  phone text not null check (phone ~ '^242[0-9]{9}$'),
  amount numeric(14, 0) not null check (amount > 0 and amount <= 10000000),
  status text not null default 'requested'
    check (status in ('requested', 'pending', 'success', 'failed', 'cancelled', 'error')),
  openpay_reference text unique
    check (openpay_reference is null or char_length(openpay_reference) between 1 and 120),
  message text check (message is null or char_length(message) <= 300),
  requested_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index public_order_payments_order_idx on public.public_order_payments(order_id, created_at desc);
create index public_order_payments_shop_idx on public.public_order_payments(shop_id, created_at desc);
create trigger public_order_payments_touch_updated_at
  before update on public.public_order_payments
  for each row execute function public.touch_updated_at();

alter table public.public_order_payments enable row level security;
revoke all on public.public_order_payments from anon, authenticated;
grant select on public.public_order_payments to authenticated;
create policy "COVI owners read their order payments"
on public.public_order_payments for select to authenticated
using (exists (select 1 from public.shops s
               where s.id = public_order_payments.shop_id and s.owner_id = (select auth.uid())));

-- Propriétaire : enregistrer / remplacer la clé API (jamais relisible), activer ou couper. -------
create or replace function public.get_shop_openpay(p_shop_id uuid)
returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
declare
  v_row public.shop_openpay_settings%rowtype;
begin
  perform public.assert_shop_owner(p_shop_id);
  select * into v_row from public.shop_openpay_settings where shop_id = p_shop_id;
  if not found then
    return pg_catalog.jsonb_build_object('configured', false, 'enabled', false, 'keyHint', null);
  end if;
  return pg_catalog.jsonb_build_object('configured', true, 'enabled', v_row.enabled,
    'keyHint', v_row.key_hint, 'updatedAt', v_row.updated_at);
end;
$fn$;

create or replace function public.set_shop_openpay_key(p_shop_id uuid, p_api_key text)
returns jsonb language plpgsql security definer set search_path to ''
as $fn$
declare
  v_key text := pg_catalog.btrim(p_api_key);
  v_row public.shop_openpay_settings%rowtype;
  v_secret uuid;
begin
  perform public.assert_shop_owner(p_shop_id);
  if v_key is null or char_length(v_key) not between 12 and 300 or v_key ~ '[[:space:][:cntrl:]]' then
    raise exception 'Invalid OpenPay key' using errcode = '22023';
  end if;
  select * into v_row from public.shop_openpay_settings where shop_id = p_shop_id for update;
  if found then
    perform vault.update_secret(v_row.secret_id, v_key);
    update public.shop_openpay_settings
    set key_hint = pg_catalog.right(v_key, 4), enabled = true, updated_by = auth.uid(), updated_at = now()
    where shop_id = p_shop_id;
  else
    v_secret := vault.create_secret(v_key, 'covi_openpay_' || p_shop_id::text,
                                    'Clé API OpenPay de la boutique COVI');
    insert into public.shop_openpay_settings (shop_id, secret_id, key_hint, enabled, updated_by)
    values (p_shop_id, v_secret, pg_catalog.right(v_key, 4), true, auth.uid());
  end if;
  perform public.shop_audit(p_shop_id, 'openpay_key_set', null, '{}'::jsonb);
  return public.get_shop_openpay(p_shop_id);
end;
$fn$;

create or replace function public.set_shop_openpay_enabled(p_shop_id uuid, p_enabled boolean)
returns jsonb language plpgsql security definer set search_path to ''
as $fn$
begin
  perform public.assert_shop_owner(p_shop_id);
  if p_enabled is null then raise exception 'Invalid value' using errcode = '22023'; end if;
  update public.shop_openpay_settings set enabled = p_enabled, updated_by = auth.uid(),
    updated_at = now() where shop_id = p_shop_id;
  if not found then raise exception 'OpenPay not configured' using errcode = '22023'; end if;
  perform public.shop_audit(p_shop_id, 'openpay_enabled', null,
    pg_catalog.jsonb_build_object('enabled', p_enabled));
  return public.get_shop_openpay(p_shop_id);
end;
$fn$;

-- Propriétaire : demander le paiement d'une commande (crée la ligne, la fonction Edge appelle
-- OpenPay ensuite). Une seule demande en cours à la fois, aucune après un paiement réussi.
create or replace function public.request_order_mobile_payment(
  p_order_id uuid, p_provider text, p_phone text, p_amount numeric)
returns uuid language plpgsql security definer set search_path to ''
as $fn$
declare
  v_order public.public_orders%rowtype;
  v_id uuid;
begin
  select * into v_order from public.public_orders where id = p_order_id for update;
  if not found then raise exception 'Order not found' using errcode = '42501'; end if;
  perform public.assert_shop_owner(v_order.shop_id);
  if v_order.status not in ('new', 'accepted') then raise exception 'Order already closed'; end if;
  if not exists (select 1 from public.shop_openpay_settings s
                 where s.shop_id = v_order.shop_id and s.enabled) then
    raise exception 'OpenPay not configured';
  end if;
  if p_provider is null or p_provider not in ('MTN', 'AIRTEL') then
    raise exception 'Invalid mobile money provider';
  end if;
  if p_phone is null or p_phone !~ '^242[0-9]{9}$' then
    raise exception 'Invalid mobile money phone';
  end if;
  if p_amount is null or p_amount <= 0 or p_amount > 10000000 or p_amount <> pg_catalog.round(p_amount) then
    raise exception 'Invalid mobile money amount';
  end if;
  if exists (select 1 from public.public_order_payments p
             where p.order_id = v_order.id and p.status = 'success') then
    raise exception 'Mobile payment already received';
  end if;
  if exists (select 1 from public.public_order_payments p
             where p.order_id = v_order.id and p.status in ('requested', 'pending')
               and p.created_at > now() - interval '3 minutes') then
    raise exception 'Mobile payment already pending';
  end if;
  insert into public.public_order_payments (order_id, shop_id, provider, phone, amount, requested_by)
  values (v_order.id, v_order.shop_id, p_provider, p_phone, p_amount, auth.uid())
  returning id into v_id;
  perform public.shop_audit(v_order.shop_id, 'mobile_payment_requested', v_order.id::text,
    pg_catalog.jsonb_build_object('payment_id', v_id, 'provider', p_provider, 'amount', p_amount));
  return v_id;
end;
$fn$;

-- Propriétaire : vérifier qu'un paiement lui appartient (avant une relecture du statut).
create or replace function public.assert_order_payment_owner(p_payment_id uuid)
returns boolean language plpgsql stable security definer set search_path to ''
as $fn$
declare
  v_shop uuid;
begin
  select shop_id into v_shop from public.public_order_payments where id = p_payment_id;
  if not found then raise exception 'Payment not found' using errcode = '42501'; end if;
  perform public.assert_shop_owner(v_shop);
  return true;
end;
$fn$;

-- Clé serveur (fonction Edge) uniquement. ------------------------------------------------------
create or replace function public.openpay_payment_context(p_payment_id uuid)
returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
declare
  v_pay public.public_order_payments%rowtype;
  v_order public.public_orders%rowtype;
  v_key text;
begin
  select * into v_pay from public.public_order_payments where id = p_payment_id;
  if not found then return null; end if;
  select * into v_order from public.public_orders where id = v_pay.order_id;
  select d.decrypted_secret into v_key
  from public.shop_openpay_settings s join vault.decrypted_secrets d on d.id = s.secret_id
  where s.shop_id = v_pay.shop_id and s.enabled;
  if v_key is null then return null; end if;
  return pg_catalog.jsonb_build_object('paymentId', v_pay.id, 'status', v_pay.status,
    'reference', v_pay.openpay_reference, 'provider', v_pay.provider, 'phone', v_pay.phone,
    'amount', v_pay.amount, 'orderId', v_order.id, 'orderReference', v_order.reference,
    'customerName', v_order.customer_name, 'createdAt', v_pay.created_at, 'apiKey', v_key);
end;
$fn$;

create or replace function public.openpay_payment_by_reference(p_reference text)
returns uuid language sql stable security definer set search_path to ''
as $fn$
  select id from public.public_order_payments where openpay_reference = p_reference
$fn$;

-- Statut relu chez OpenPay : seules les transitions depuis requested / pending sont possibles,
-- et un paiement réussi ne redevient jamais autre chose.
create or replace function public.record_openpay_status(
  p_payment_id uuid, p_reference text, p_status text, p_message text)
returns text language plpgsql security definer set search_path to ''
as $fn$
declare
  v_pay public.public_order_payments%rowtype;
  v_status text := pg_catalog.lower(coalesce(p_status, ''));
begin
  select * into v_pay from public.public_order_payments where id = p_payment_id for update;
  if not found then raise exception 'Payment not found'; end if;
  if v_status not in ('pending', 'success', 'failed', 'cancelled', 'error') then
    v_status := 'pending';
  end if;
  if v_pay.openpay_reference is not null and p_reference is not null
     and v_pay.openpay_reference <> p_reference then
    raise exception 'Payment reference mismatch';
  end if;
  if v_pay.status not in ('requested', 'pending') then
    return v_pay.status;
  end if;
  update public.public_order_payments
  set status = v_status,
      openpay_reference = coalesce(v_pay.openpay_reference, nullif(pg_catalog.left(p_reference, 120), '')),
      message = pg_catalog.left(p_message, 300)
  where id = v_pay.id;
  if v_status = 'success' then
    perform public.shop_audit(v_pay.shop_id, 'mobile_payment_received', v_pay.order_id::text,
      pg_catalog.jsonb_build_object('payment_id', v_pay.id, 'reference', p_reference,
                                    'amount', v_pay.amount));
  end if;
  return v_status;
end;
$fn$;

revoke all on function public.get_shop_openpay(uuid) from public, anon;
revoke all on function public.set_shop_openpay_key(uuid, text) from public, anon;
revoke all on function public.set_shop_openpay_enabled(uuid, boolean) from public, anon;
revoke all on function public.request_order_mobile_payment(uuid, text, text, numeric) from public, anon;
revoke all on function public.assert_order_payment_owner(uuid) from public, anon;
revoke all on function public.openpay_payment_context(uuid) from public, anon, authenticated;
revoke all on function public.openpay_payment_by_reference(text) from public, anon, authenticated;
revoke all on function public.record_openpay_status(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.get_shop_openpay(uuid) to authenticated;
grant execute on function public.set_shop_openpay_key(uuid, text) to authenticated;
grant execute on function public.set_shop_openpay_enabled(uuid, boolean) to authenticated;
grant execute on function public.request_order_mobile_payment(uuid, text, text, numeric) to authenticated;
grant execute on function public.assert_order_payment_owner(uuid) to authenticated;
grant execute on function public.openpay_payment_context(uuid) to service_role;
grant execute on function public.openpay_payment_by_reference(text) to service_role;
grant execute on function public.record_openpay_status(uuid, text, text, text) to service_role;

-- Les paiements apparaissent en direct dans « Commandes reçues ».
do $realtime$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.public_order_payments;
  end if;
end;
$realtime$;
