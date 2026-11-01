-- COVI Salon professionnel — caisse, produits/consommables et commissions (lot 5).
--
-- Règles :
--   * Un ticket (note du client) est payé en une fois, éventuellement avec plusieurs moyens
--     (espèces + Mobile Money…). Le paiement partiel à crédit n'est pas pris en charge (v1).
--   * Le paiement Mobile Money / carte est CONFIRMÉ MANUELLEMENT par la caisse (confirmation =
--     'manual') : COVI n'interroge aucun opérateur et ne prétend jamais le contraire.
--   * Le stock, les coûts et les commissions sont figés AU PAIEMENT, une seule fois par ligne
--     (contraintes d'unicité) : un double clic ou une relance réseau ne compte rien deux fois
--     (clé d'opération idempotente).
--   * Un remboursement ajoute une écriture négative ; rien n'est effacé.

-- 1. Produits et consommables -------------------------------------------------------------------
create table public.salon_supplies (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 2 and 120),
  category text check (category is null or char_length(btrim(category)) between 2 and 60),
  unit text not null default 'piece' check (unit in ('piece', 'ml', 'l', 'g', 'kg')),
  usage text not null default 'both' check (usage in ('sale', 'consumption', 'both')),
  quantity_on_hand numeric(14,3) not null default 0 check (quantity_on_hand >= 0),
  alert_threshold numeric(14,3) not null default 0 check (alert_threshold >= 0),
  unit_cost_xaf numeric(14,2) not null default 0 check (unit_cost_xaf >= 0),
  sale_price_xaf bigint check (sale_price_xaf is null or sale_price_xaf between 0 and 1000000000),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, id),
  constraint salon_supply_sale_price check (usage = 'consumption' or sale_price_xaf is not null),
  constraint salon_supply_piece_integer check (unit <> 'piece' or quantity_on_hand = trunc(quantity_on_hand))
);
create index salon_supplies_by_shop on public.salon_supplies (shop_id, active, name);

create table public.salon_supply_movements (
  id bigint generated always as identity primary key,
  shop_id uuid not null references public.shops(id) on delete cascade,
  supply_id uuid not null,
  delta numeric(14,3) not null check (delta <> 0),
  quantity_after numeric(14,3) not null check (quantity_after >= 0),
  reason text not null check (reason in (
    'purchase', 'sale', 'consumption', 'return', 'loss', 'correction', 'refund_restock')),
  unit_cost_xaf numeric(14,2) not null default 0,
  ticket_id uuid,
  line_id uuid,
  shortfall numeric(14,3) not null default 0 check (shortfall >= 0),
  operation_key text check (operation_key is null or char_length(operation_key) between 8 and 80),
  note text check (note is null or char_length(note) <= 200),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  foreign key (shop_id, supply_id) references public.salon_supplies (shop_id, id)
);
create index salon_supply_movements_by_supply on public.salon_supply_movements (supply_id, created_at desc);
create index salon_supply_movements_by_shop on public.salon_supply_movements (shop_id, created_at desc);
-- Une ligne de ticket ne décrémente jamais deux fois le même produit pour la même raison.
create unique index salon_supply_movement_once_per_line
  on public.salon_supply_movements (line_id, supply_id, reason) where line_id is not null;
create unique index salon_supply_movement_operation
  on public.salon_supply_movements (shop_id, operation_key) where operation_key is not null;

-- Quantité consommée par défaut pour une prestation (ex. 30 ml de shampoing).
create table public.salon_service_consumables (
  shop_id uuid not null references public.shops(id) on delete cascade,
  service_id uuid not null,
  supply_id uuid not null,
  quantity numeric(14,3) not null check (quantity > 0 and quantity <= 100000),
  primary key (service_id, supply_id),
  foreign key (shop_id, service_id) references public.salon_services (shop_id, id) on delete cascade,
  foreign key (shop_id, supply_id) references public.salon_supplies (shop_id, id) on delete cascade
);

-- 2. Tickets, lignes, paiements ------------------------------------------------------------------
create table public.salon_tickets (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  appointment_id uuid,
  client_id uuid,
  client_name text check (client_name is null or char_length(btrim(client_name)) between 1 and 160),
  status text not null default 'open'
    check (status in ('open', 'paid', 'partially_refunded', 'refunded', 'cancelled')),
  subtotal_xaf bigint not null default 0 check (subtotal_xaf >= 0),
  discount_xaf bigint not null default 0 check (discount_xaf >= 0),
  total_xaf bigint not null default 0 check (total_xaf >= 0),
  paid_xaf bigint not null default 0 check (paid_xaf >= 0),
  refunded_xaf bigint not null default 0 check (refunded_xaf >= 0 and refunded_xaf <= paid_xaf),
  operation_key text not null check (char_length(operation_key) between 8 and 80),
  opened_by uuid references auth.users(id) on delete set null,
  opened_at timestamptz not null default now(),
  paid_at timestamptz,
  cancelled_at timestamptz,
  unique (shop_id, id),
  unique (shop_id, operation_key),
  foreign key (shop_id, appointment_id) references public.salon_appointments (shop_id, id),
  foreign key (shop_id, client_id) references public.salon_clients (shop_id, id),
  check (discount_xaf <= subtotal_xaf),
  check ((status = 'open') = (paid_at is null and cancelled_at is null) or status = 'cancelled')
);
create unique index salon_ticket_one_per_appointment on public.salon_tickets (appointment_id)
  where appointment_id is not null and status <> 'cancelled';
create index salon_tickets_by_paid on public.salon_tickets (shop_id, paid_at);
create index salon_tickets_open on public.salon_tickets (shop_id, opened_at) where status = 'open';

create table public.salon_ticket_lines (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  ticket_id uuid not null,
  kind text not null check (kind in ('service', 'product')),
  service_id uuid,
  supply_id uuid,
  employee_id uuid,
  label text not null check (char_length(btrim(label)) between 1 and 120),
  quantity numeric(14,3) not null default 1 check (quantity > 0 and quantity <= 1000),
  list_price_xaf bigint not null check (list_price_xaf >= 0),
  unit_price_xaf bigint not null check (unit_price_xaf between 0 and 1000000000),
  line_total_xaf bigint not null check (line_total_xaf >= 0),
  net_xaf bigint check (net_xaf is null or net_xaf >= 0),
  direct_cost_xaf bigint not null default 0 check (direct_cost_xaf >= 0),
  commission_xaf bigint not null default 0 check (commission_xaf >= 0),
  refunded_at timestamptz,
  created_at timestamptz not null default now(),
  unique (shop_id, id),
  foreign key (shop_id, ticket_id) references public.salon_tickets (shop_id, id) on delete cascade,
  foreign key (shop_id, service_id) references public.salon_services (shop_id, id),
  foreign key (shop_id, supply_id) references public.salon_supplies (shop_id, id),
  foreign key (shop_id, employee_id) references public.employees (shop_id, id),
  constraint salon_line_kind check (
    (kind = 'service' and service_id is not null and supply_id is null and employee_id is not null)
    or (kind = 'product' and supply_id is not null and service_id is null)
  )
);
create index salon_ticket_lines_by_ticket on public.salon_ticket_lines (ticket_id);
create index salon_ticket_lines_by_employee on public.salon_ticket_lines (shop_id, employee_id);

create table public.salon_payments (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  ticket_id uuid not null,
  kind text not null check (kind in ('payment', 'refund')),
  method text not null check (method in ('cash', 'mobile_money', 'card', 'other')),
  amount_xaf bigint not null check (amount_xaf > 0 and amount_xaf <= 1000000000),
  reference text check (reference is null or char_length(reference) <= 80),
  confirmation text not null default 'manual' check (confirmation = 'manual'),
  operation_key text not null check (char_length(operation_key) between 8 and 80),
  seq smallint not null default 1 check (seq between 1 and 5),
  note text check (note is null or char_length(note) <= 200),
  recorded_by uuid references auth.users(id) on delete set null,
  recorded_at timestamptz not null default now(),
  unique (shop_id, operation_key, seq),
  foreign key (shop_id, ticket_id) references public.salon_tickets (shop_id, id)
);
create index salon_payments_by_shop on public.salon_payments (shop_id, recorded_at);

create table public.salon_commission_payouts (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  employee_id uuid not null,
  amount_xaf bigint not null check (amount_xaf > 0 and amount_xaf <= 1000000000),
  method text not null check (method in ('cash', 'mobile_money', 'card', 'other')),
  note text check (note is null or char_length(note) <= 200),
  operation_key text not null check (char_length(operation_key) between 8 and 80),
  recorded_by uuid references auth.users(id) on delete set null,
  recorded_at timestamptz not null default now(),
  unique (shop_id, operation_key),
  foreign key (shop_id, employee_id) references public.employees (shop_id, id)
);
create index salon_payouts_by_employee on public.salon_commission_payouts (shop_id, employee_id, recorded_at);

alter table public.salon_supplies enable row level security;
alter table public.salon_supply_movements enable row level security;
alter table public.salon_service_consumables enable row level security;
alter table public.salon_tickets enable row level security;
alter table public.salon_ticket_lines enable row level security;
alter table public.salon_payments enable row level security;
alter table public.salon_commission_payouts enable row level security;
revoke all on public.salon_supplies, public.salon_supply_movements, public.salon_service_consumables,
  public.salon_tickets, public.salon_ticket_lines, public.salon_payments,
  public.salon_commission_payouts
  from public, anon, authenticated;
create trigger immutable_shop_salon_supply before update on public.salon_supplies
  for each row execute function public.prevent_sector_shop_reassignment();
create trigger immutable_shop_salon_ticket before update on public.salon_tickets
  for each row execute function public.prevent_sector_shop_reassignment();

-- 3. Produits : catalogue et mouvements ----------------------------------------------------------
create function public.salon_supplies_list(p_shop uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'read_catalog');
  v_costs boolean := public.salon_allowed(v_role, 'supplies');
begin
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', s.id, 'name', s.name, 'category', s.category, 'unit', s.unit, 'usage', s.usage,
      'quantity_on_hand', s.quantity_on_hand, 'alert_threshold', s.alert_threshold,
      'low', s.quantity_on_hand <= s.alert_threshold,
      'unit_cost_xaf', case when v_costs then s.unit_cost_xaf end,
      'sale_price_xaf', s.sale_price_xaf, 'active', s.active)
      order by s.active desc, s.name)
    from public.salon_supplies s
    where s.shop_id = p_shop and (v_costs or (s.active and s.usage in ('sale', 'both')))), '[]'::jsonb);
end;
$$;

create function public.salon_supply_save(
  p_shop uuid, p_id uuid, p_name text, p_category text, p_unit text, p_usage text,
  p_alert_threshold numeric, p_unit_cost_xaf numeric, p_sale_price_xaf bigint, p_active boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'supplies');
  v_id uuid := p_id;
begin
  if p_id is null then
    insert into public.salon_supplies (shop_id, name, category, unit, usage, alert_threshold,
                                       unit_cost_xaf, sale_price_xaf, active)
    values (p_shop, btrim(coalesce(p_name, '')), nullif(btrim(p_category), ''),
            coalesce(p_unit, 'piece'), coalesce(p_usage, 'both'), coalesce(p_alert_threshold, 0),
            coalesce(p_unit_cost_xaf, 0),
            case when coalesce(p_usage, 'both') = 'consumption' then null else p_sale_price_xaf end,
            coalesce(p_active, true))
    returning id into v_id;
  else
    -- L'unité ne change plus une fois du stock enregistré (les quantités perdraient leur sens).
    if exists (select 1 from public.salon_supply_movements m where m.supply_id = p_id)
       and exists (select 1 from public.salon_supplies s where s.id = p_id and s.unit <> coalesce(p_unit, s.unit)) then
      raise exception 'Unit cannot change once stock is recorded' using errcode = '22023';
    end if;
    update public.salon_supplies set name = btrim(coalesce(p_name, '')),
      category = nullif(btrim(p_category), ''), unit = coalesce(p_unit, unit),
      usage = coalesce(p_usage, usage), alert_threshold = coalesce(p_alert_threshold, 0),
      unit_cost_xaf = coalesce(p_unit_cost_xaf, unit_cost_xaf),
      sale_price_xaf = case when coalesce(p_usage, usage) = 'consumption' then null else p_sale_price_xaf end,
      active = coalesce(p_active, true), updated_at = now()
    where id = p_id and shop_id = p_shop;
    if not found then raise exception 'Product not found' using errcode = '42501'; end if;
  end if;
  perform public.salon_log(p_shop, v_role, 'supply_saved', v_id, '{}'::jsonb);
  return v_id;
end;
$$;

-- p_reason : purchase (entrée, coût moyen pondéré mis à jour), return (retour fournisseur
-- annulé / reprise en stock), loss (perte, casse), correction (p_quantity = nouvelle quantité).
create function public.salon_supply_adjust(
  p_shop uuid, p_supply uuid, p_reason text, p_quantity numeric, p_unit_cost_xaf numeric,
  p_note text, p_operation_key text
)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'supplies');
  v_s public.salon_supplies%rowtype;
  v_delta numeric;
  v_after numeric;
  v_cost numeric;
begin
  if p_operation_key is null or char_length(p_operation_key) not between 8 and 80 then
    raise exception 'Operation key required' using errcode = '22023';
  end if;
  select quantity_after into v_after from public.salon_supply_movements
  where shop_id = p_shop and operation_key = p_operation_key;
  if found then return v_after; end if;
  select * into v_s from public.salon_supplies where id = p_supply and shop_id = p_shop for update;
  if not found then raise exception 'Product not found' using errcode = '42501'; end if;
  if p_quantity is null or p_quantity < 0 or p_quantity > 1000000 then
    raise exception 'Invalid quantity' using errcode = '22023';
  end if;
  v_delta := case p_reason
    when 'purchase' then p_quantity
    when 'return' then p_quantity
    when 'loss' then -p_quantity
    when 'correction' then p_quantity - v_s.quantity_on_hand
    else null end;
  if v_delta is null then raise exception 'Invalid reason' using errcode = '22023'; end if;
  if v_delta = 0 then raise exception 'Stock unchanged' using errcode = '22023'; end if;
  v_after := v_s.quantity_on_hand + v_delta;
  if v_after < 0 then raise exception 'Not enough stock' using errcode = '22023'; end if;
  v_cost := v_s.unit_cost_xaf;
  if p_reason = 'purchase' and p_unit_cost_xaf is not null then
    if p_unit_cost_xaf < 0 then raise exception 'Invalid cost' using errcode = '22023'; end if;
    -- Coût moyen pondéré : (stock × ancien coût + entrée × coût d'achat) / nouveau stock.
    v_cost := round((v_s.quantity_on_hand * v_s.unit_cost_xaf + p_quantity * p_unit_cost_xaf) / v_after, 2);
  end if;
  update public.salon_supplies set quantity_on_hand = v_after, unit_cost_xaf = v_cost, updated_at = now()
  where id = p_supply;
  insert into public.salon_supply_movements (shop_id, supply_id, delta, quantity_after, reason,
    unit_cost_xaf, operation_key, note, created_by)
  values (p_shop, p_supply, v_delta, v_after, p_reason,
    case when p_reason = 'purchase' then coalesce(p_unit_cost_xaf, v_s.unit_cost_xaf) else v_s.unit_cost_xaf end,
    p_operation_key, nullif(btrim(p_note), ''), auth.uid());
  perform public.salon_log(p_shop, v_role, 'supply_adjusted', p_supply,
    jsonb_build_object('reason', p_reason, 'delta', v_delta, 'after', v_after));
  return v_after;
end;
$$;

-- p_items : [{"supply_id":"…","quantity":30}] (remplace la liste).
create function public.salon_service_consumables_set(p_shop uuid, p_service uuid, p_items jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'catalog');
begin
  if not exists (select 1 from public.salon_services where id = p_service and shop_id = p_shop) then
    raise exception 'Service not found' using errcode = '42501';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 20 then
    raise exception 'Invalid consumables' using errcode = '22023';
  end if;
  delete from public.salon_service_consumables where service_id = p_service and shop_id = p_shop;
  insert into public.salon_service_consumables (shop_id, service_id, supply_id, quantity)
  select p_shop, p_service, (i ->> 'supply_id')::uuid, (i ->> 'quantity')::numeric
  from jsonb_array_elements(p_items) i;
  if exists (select 1 from public.salon_service_consumables c
             join public.salon_supplies s on s.id = c.supply_id
             where c.service_id = p_service and s.usage = 'sale') then
    raise exception 'A product for sale only cannot be consumed' using errcode = '22023';
  end if;
  perform public.salon_log(p_shop, v_role, 'service_consumables_set', p_service, '{}'::jsonb);
end;
$$;

create function public.salon_service_consumables_get(p_shop uuid, p_service uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'catalog');
begin
  return coalesce((select jsonb_agg(jsonb_build_object('supply_id', c.supply_id, 'name', s.name,
      'unit', s.unit, 'quantity', c.quantity) order by s.name)
    from public.salon_service_consumables c join public.salon_supplies s on s.id = c.supply_id
    where c.service_id = p_service and c.shop_id = p_shop), '[]'::jsonb);
end;
$$;

-- 4. Caisse ----------------------------------------------------------------------------------
create function public.salon_ticket_view(p_shop uuid, p_ticket uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', t.id, 'status', t.status, 'appointment_id', t.appointment_id,
    'client_id', t.client_id, 'client_name', t.client_name,
    'subtotal_xaf', t.subtotal_xaf, 'discount_xaf', t.discount_xaf, 'total_xaf', t.total_xaf,
    'paid_xaf', t.paid_xaf, 'refunded_xaf', t.refunded_xaf,
    'opened_at', t.opened_at, 'paid_at', t.paid_at,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'kind', l.kind,
        'service_id', l.service_id, 'supply_id', l.supply_id, 'employee_id', l.employee_id,
        'employee_name', e.full_name, 'label', l.label, 'quantity', l.quantity,
        'list_price_xaf', l.list_price_xaf, 'unit_price_xaf', l.unit_price_xaf,
        'line_total_xaf', l.line_total_xaf, 'net_xaf', l.net_xaf,
        'refunded', l.refunded_at is not null) order by l.created_at)
      from public.salon_ticket_lines l left join public.employees e on e.id = l.employee_id
      where l.ticket_id = t.id), '[]'::jsonb),
    'payments', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'kind', p.kind,
        'method', p.method, 'amount_xaf', p.amount_xaf, 'reference', p.reference,
        'confirmation', p.confirmation, 'recorded_at', p.recorded_at) order by p.recorded_at, p.seq)
      from public.salon_payments p where p.ticket_id = t.id), '[]'::jsonb))
  from public.salon_tickets t where t.id = p_ticket and t.shop_id = p_shop
$$;

create function public.salon_ticket_recompute(p_ticket uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.salon_tickets t set
    subtotal_xaf = coalesce((select sum(l.line_total_xaf) from public.salon_ticket_lines l
                             where l.ticket_id = t.id), 0),
    discount_xaf = least(t.discount_xaf, coalesce((select sum(l.line_total_xaf)
                   from public.salon_ticket_lines l where l.ticket_id = t.id), 0)),
    total_xaf = coalesce((select sum(l.line_total_xaf) from public.salon_ticket_lines l
                          where l.ticket_id = t.id), 0)
                - least(t.discount_xaf, coalesce((select sum(l.line_total_xaf)
                   from public.salon_ticket_lines l where l.ticket_id = t.id), 0))
  where t.id = p_ticket and t.status = 'open'
$$;

-- Ouvre la note d'un client (depuis un rendez-vous, ou visite sans rendez-vous / vente produit).
create function public.salon_ticket_open(
  p_shop uuid, p_appointment uuid, p_client_id uuid, p_client_name text, p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'checkout');
  v_a public.salon_appointments%rowtype;
  v_id uuid;
begin
  if p_operation_key is null or char_length(p_operation_key) not between 8 and 80 then
    raise exception 'Operation key required' using errcode = '22023';
  end if;
  select id into v_id from public.salon_tickets where shop_id = p_shop and operation_key = p_operation_key;
  if found then return public.salon_ticket_view(p_shop, v_id); end if;
  if p_appointment is not null then
    select * into v_a from public.salon_appointments
    where id = p_appointment and shop_id = p_shop for update;
    if not found then raise exception 'Appointment not found' using errcode = '42501'; end if;
    if v_a.status in ('cancelled', 'no_show', 'pending') then
      raise exception 'This appointment cannot be checked out' using errcode = '22023';
    end if;
    select id into v_id from public.salon_tickets
    where appointment_id = p_appointment and status <> 'cancelled';
    if found then return public.salon_ticket_view(p_shop, v_id); end if;
    insert into public.salon_tickets (shop_id, appointment_id, client_id, client_name,
                                      operation_key, opened_by)
    values (p_shop, p_appointment, v_a.client_id, v_a.client_name, p_operation_key, auth.uid())
    returning id into v_id;
    insert into public.salon_ticket_lines (shop_id, ticket_id, kind, service_id, employee_id,
      label, quantity, list_price_xaf, unit_price_xaf, line_total_xaf)
    select p_shop, v_id, 'service', s.service_id, v_a.employee_id, s.name, 1,
      s.price_xaf, s.price_xaf, s.price_xaf
    from public.salon_appointment_services s where s.appointment_id = p_appointment
    order by s.position;
  else
    if p_client_id is not null and not exists (
        select 1 from public.salon_clients c where c.id = p_client_id and c.shop_id = p_shop) then
      raise exception 'Client not found' using errcode = '22023';
    end if;
    insert into public.salon_tickets (shop_id, client_id, client_name, operation_key, opened_by)
    values (p_shop, p_client_id,
      coalesce(nullif(btrim(p_client_name), ''),
               (select btrim(c.first_name || ' ' || coalesce(c.last_name, ''))
                from public.salon_clients c where c.id = p_client_id)),
      p_operation_key, auth.uid())
    returning id into v_id;
  end if;
  perform public.salon_ticket_recompute(v_id);
  perform public.salon_log(p_shop, v_role, 'ticket_opened', v_id,
    jsonb_build_object('appointment_id', p_appointment));
  return public.salon_ticket_view(p_shop, v_id);
end;
$$;

create function public.salon_ticket_add_line(
  p_shop uuid, p_ticket uuid, p_kind text, p_item uuid, p_employee uuid,
  p_quantity numeric, p_unit_price_xaf bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'checkout');
  v_name text;
  v_list bigint;
  v_price bigint;
  v_qty numeric := coalesce(p_quantity, 1);
  v_unit text;
begin
  perform 1 from public.salon_tickets where id = p_ticket and shop_id = p_shop and status = 'open' for update;
  if not found then raise exception 'Ticket is not open' using errcode = '22023'; end if;
  if v_qty <= 0 or v_qty > 1000 then raise exception 'Invalid quantity' using errcode = '22023'; end if;
  if p_kind = 'service' then
    select name, price_xaf into v_name, v_list from public.salon_services
    where id = p_item and shop_id = p_shop and active;
    if not found then raise exception 'Service unavailable' using errcode = '22023'; end if;
    if not exists (select 1 from public.employees e join public.salon_staff_profiles p on p.employee_id = e.id
                   where e.id = p_employee and e.shop_id = p_shop and e.active) then
      raise exception 'Collaborator unavailable' using errcode = '22023';
    end if;
    if exists (select 1 from public.salon_staff_services ss where ss.service_id = p_item)
       and not exists (select 1 from public.salon_staff_services ss
                       where ss.service_id = p_item and ss.employee_id = p_employee) then
      raise exception 'Collaborator not qualified for this service' using errcode = '22023';
    end if;
    if v_qty <> trunc(v_qty) then raise exception 'Invalid quantity' using errcode = '22023'; end if;
  elsif p_kind = 'product' then
    select name, sale_price_xaf, unit into v_name, v_list, v_unit from public.salon_supplies
    where id = p_item and shop_id = p_shop and active and usage in ('sale', 'both');
    if not found then raise exception 'Product unavailable' using errcode = '22023'; end if;
    if v_unit = 'piece' and v_qty <> trunc(v_qty) then
      raise exception 'Invalid quantity' using errcode = '22023';
    end if;
  else
    raise exception 'Invalid line' using errcode = '22023';
  end if;
  v_price := coalesce(p_unit_price_xaf, v_list);
  -- Prix différent du catalogue (geste commercial, supplément) : responsable ou propriétaire.
  if v_price <> v_list and not public.salon_allowed(v_role, 'discount') then
    raise exception 'Only a manager can change a price' using errcode = '42501';
  end if;
  if v_price < 0 or v_price > 1000000000 then raise exception 'Invalid price' using errcode = '22023'; end if;
  insert into public.salon_ticket_lines (shop_id, ticket_id, kind, service_id, supply_id, employee_id,
    label, quantity, list_price_xaf, unit_price_xaf, line_total_xaf)
  values (p_shop, p_ticket, p_kind,
    case when p_kind = 'service' then p_item end, case when p_kind = 'product' then p_item end,
    case when p_kind = 'service' then p_employee
         else (select e.id from public.employees e where e.id = p_employee and e.shop_id = p_shop) end,
    v_name, v_qty, v_list, v_price, round(v_price * v_qty)::bigint);
  perform public.salon_ticket_recompute(p_ticket);
  return public.salon_ticket_view(p_shop, p_ticket);
end;
$$;

create function public.salon_ticket_remove_line(p_shop uuid, p_ticket uuid, p_line uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'checkout');
begin
  perform 1 from public.salon_tickets where id = p_ticket and shop_id = p_shop and status = 'open' for update;
  if not found then raise exception 'Ticket is not open' using errcode = '22023'; end if;
  delete from public.salon_ticket_lines where id = p_line and ticket_id = p_ticket and shop_id = p_shop;
  perform public.salon_ticket_recompute(p_ticket);
  return public.salon_ticket_view(p_shop, p_ticket);
end;
$$;

create function public.salon_ticket_set_discount(p_shop uuid, p_ticket uuid, p_discount_xaf bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'discount');
  v_sub bigint;
begin
  select subtotal_xaf into v_sub from public.salon_tickets
  where id = p_ticket and shop_id = p_shop and status = 'open' for update;
  if not found then raise exception 'Ticket is not open' using errcode = '22023'; end if;
  if p_discount_xaf is null or p_discount_xaf < 0 or p_discount_xaf > v_sub then
    raise exception 'Invalid discount' using errcode = '22023';
  end if;
  update public.salon_tickets set discount_xaf = p_discount_xaf where id = p_ticket;
  perform public.salon_ticket_recompute(p_ticket);
  perform public.salon_log(p_shop, v_role, 'ticket_discount', p_ticket,
    jsonb_build_object('discount_xaf', p_discount_xaf));
  return public.salon_ticket_view(p_shop, p_ticket);
end;
$$;

create function public.salon_ticket_cancel(p_shop uuid, p_ticket uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'checkout');
begin
  update public.salon_tickets set status = 'cancelled', cancelled_at = now()
  where id = p_ticket and shop_id = p_shop and status = 'open' and paid_xaf = 0;
  if not found then raise exception 'Only an unpaid open ticket can be cancelled' using errcode = '22023'; end if;
  perform public.salon_log(p_shop, v_role, 'ticket_cancelled', p_ticket, '{}'::jsonb);
  return public.salon_ticket_view(p_shop, p_ticket);
end;
$$;

-- Encaissement. p_payments : [{"method":"cash","amount_xaf":5000,"reference":null}, …]
create function public.salon_ticket_pay(
  p_shop uuid, p_ticket uuid, p_payments jsonb, p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'checkout');
  v_t public.salon_tickets%rowtype;
  v_sum bigint := 0;
  v_item jsonb;
  v_seq smallint := 0;
  v_line record;
  v_need record;
  v_left bigint;
  v_biggest uuid;
  v_alloc bigint;
  v_cost numeric;
  v_take numeric;
  v_after numeric;
  v_prof public.salon_staff_profiles%rowtype;
begin
  if p_operation_key is null or char_length(p_operation_key) not between 8 and 80 then
    raise exception 'Operation key required' using errcode = '22023';
  end if;
  if exists (select 1 from public.salon_payments where shop_id = p_shop and operation_key = p_operation_key
             and ticket_id <> p_ticket) then
    raise exception 'Operation key already used' using errcode = '22023';
  end if;
  -- Relance du même encaissement (réseau, double clic) : on renvoie l'état, sans rien recompter.
  if exists (select 1 from public.salon_payments where shop_id = p_shop and operation_key = p_operation_key)
     or exists (select 1 from public.salon_tickets where id = p_ticket and shop_id = p_shop
                and status <> 'open' and paid_at is not null
                and exists (select 1 from public.salon_events ev where ev.entity_id = p_ticket
                            and ev.event_type = 'ticket_paid' and ev.details ->> 'operation_key' = p_operation_key)) then
    return public.salon_ticket_view(p_shop, p_ticket);
  end if;
  select * into v_t from public.salon_tickets where id = p_ticket and shop_id = p_shop for update;
  if not found then raise exception 'Ticket not found' using errcode = '42501'; end if;
  if v_t.status <> 'open' then raise exception 'Ticket is not open' using errcode = '22023'; end if;
  if not exists (select 1 from public.salon_ticket_lines where ticket_id = p_ticket) then
    raise exception 'Empty ticket' using errcode = '22023';
  end if;
  perform public.salon_ticket_recompute(p_ticket);
  select * into v_t from public.salon_tickets where id = p_ticket;

  if p_payments is null or jsonb_typeof(p_payments) <> 'array' or jsonb_array_length(p_payments) > 5 then
    raise exception 'Invalid payments' using errcode = '22023';
  end if;
  for v_item in select value from jsonb_array_elements(p_payments) loop
    if (v_item ->> 'method') not in ('cash', 'mobile_money', 'card', 'other')
       or (v_item ->> 'amount_xaf') !~ '^[0-9]{1,10}$' or (v_item ->> 'amount_xaf')::bigint <= 0 then
      raise exception 'Invalid payments' using errcode = '22023';
    end if;
    v_sum := v_sum + (v_item ->> 'amount_xaf')::bigint;
  end loop;
  if v_sum <> v_t.total_xaf then
    raise exception 'Payments must equal the total' using errcode = '22023';
  end if;

  -- Produits vendus : stock suffisant obligatoire (verrou par produit, ordre fixe).
  for v_need in
    select l.supply_id, sum(l.quantity) as qty from public.salon_ticket_lines l
    where l.ticket_id = p_ticket and l.kind = 'product' group by l.supply_id order by l.supply_id
  loop
    perform 1 from public.salon_supplies where id = v_need.supply_id for update;
    if (select quantity_on_hand from public.salon_supplies where id = v_need.supply_id) < v_need.qty then
      raise exception 'Not enough stock for %', (select name from public.salon_supplies where id = v_need.supply_id)
        using errcode = '22023';
    end if;
  end loop;

  -- Répartition de la remise au prorata (le reste d'arrondi va à la plus grosse ligne).
  v_left := v_t.discount_xaf;
  select id into v_biggest from public.salon_ticket_lines where ticket_id = p_ticket
  order by line_total_xaf desc, created_at, id limit 1;
  for v_line in select * from public.salon_ticket_lines where ticket_id = p_ticket order by created_at, id loop
    v_alloc := case when v_t.subtotal_xaf = 0 then 0
                    else floor(v_t.discount_xaf::numeric * v_line.line_total_xaf / v_t.subtotal_xaf)::bigint end;
    v_left := v_left - v_alloc;
    update public.salon_ticket_lines set net_xaf = line_total_xaf - v_alloc where id = v_line.id;
  end loop;
  update public.salon_ticket_lines set net_xaf = net_xaf - v_left where id = v_biggest;

  for v_line in select * from public.salon_ticket_lines where ticket_id = p_ticket order by created_at, id loop
    v_cost := 0;
    if v_line.kind = 'product' then
      select unit_cost_xaf into v_cost from public.salon_supplies where id = v_line.supply_id;
      update public.salon_supplies set quantity_on_hand = quantity_on_hand - v_line.quantity, updated_at = now()
      where id = v_line.supply_id returning quantity_on_hand into v_after;
      insert into public.salon_supply_movements (shop_id, supply_id, delta, quantity_after, reason,
        unit_cost_xaf, ticket_id, line_id, created_by)
      values (p_shop, v_line.supply_id, -v_line.quantity, v_after, 'sale', v_cost, p_ticket, v_line.id, auth.uid());
      v_cost := round(v_cost * v_line.quantity);
    else
      -- Consommables : quantité configurée × quantité de prestations, jamais plus que le stock.
      for v_need in
        select c.supply_id, c.quantity * v_line.quantity as qty, s.unit_cost_xaf, s.quantity_on_hand
        from public.salon_service_consumables c join public.salon_supplies s on s.id = c.supply_id
        where c.service_id = v_line.service_id order by c.supply_id
      loop
        perform 1 from public.salon_supplies where id = v_need.supply_id for update;
        v_take := least(v_need.qty, (select quantity_on_hand from public.salon_supplies where id = v_need.supply_id));
        if v_take > 0 then
          update public.salon_supplies set quantity_on_hand = quantity_on_hand - v_take, updated_at = now()
          where id = v_need.supply_id returning quantity_on_hand into v_after;
        else
          select quantity_on_hand into v_after from public.salon_supplies where id = v_need.supply_id;
        end if;
        if v_take > 0 or v_need.qty > 0 then
          insert into public.salon_supply_movements (shop_id, supply_id, delta, quantity_after, reason,
            unit_cost_xaf, ticket_id, line_id, shortfall, created_by)
          select p_shop, v_need.supply_id, -v_take, v_after, 'consumption', v_need.unit_cost_xaf,
                 p_ticket, v_line.id, v_need.qty - v_take, auth.uid()
          where v_take > 0;
          if v_need.qty > v_take then
            perform public.salon_log(p_shop, v_role, 'stock_shortfall', v_need.supply_id,
              jsonb_build_object('ticket_id', p_ticket, 'missing', v_need.qty - v_take));
          end if;
        end if;
        v_cost := v_cost + v_take * v_need.unit_cost_xaf;
      end loop;
      if not exists (select 1 from public.salon_service_consumables c where c.service_id = v_line.service_id) then
        v_cost := (select direct_cost_xaf from public.salon_services where id = v_line.service_id) * v_line.quantity;
      end if;
      v_cost := round(v_cost);
    end if;
    -- Commission figée au paiement, sur le montant net de la ligne (après remise).
    select * into v_prof from public.salon_staff_profiles where employee_id = v_line.employee_id;
    update public.salon_ticket_lines set direct_cost_xaf = v_cost::bigint,
      commission_xaf = case
        when v_line.kind <> 'service' or v_prof.employee_id is null then 0
        when v_prof.commission_mode = 'percent' then round(net_xaf * v_prof.commission_percent / 100)::bigint
        when v_prof.commission_mode = 'fixed' then round(v_prof.commission_fixed_xaf * v_line.quantity)::bigint
        else 0 end
    where id = v_line.id;
  end loop;

  for v_item in select value from jsonb_array_elements(p_payments) loop
    v_seq := v_seq + 1;
    insert into public.salon_payments (shop_id, ticket_id, kind, method, amount_xaf, reference,
      operation_key, seq, recorded_by)
    values (p_shop, p_ticket, 'payment', v_item ->> 'method', (v_item ->> 'amount_xaf')::bigint,
      nullif(btrim(v_item ->> 'reference'), ''), p_operation_key, v_seq, auth.uid());
  end loop;
  update public.salon_tickets set status = 'paid', paid_xaf = v_t.total_xaf, paid_at = now()
  where id = p_ticket;
  if v_t.appointment_id is not null then
    update public.salon_appointments set status = 'completed', updated_at = now()
    where id = v_t.appointment_id and status in ('confirmed', 'arrived', 'in_progress');
  end if;
  perform public.salon_log(p_shop, v_role, 'ticket_paid', p_ticket,
    jsonb_build_object('total_xaf', v_t.total_xaf, 'operation_key', p_operation_key));
  return public.salon_ticket_view(p_shop, p_ticket);
end;
$$;

-- Remboursement de lignes entières. Les consommables utilisés ne reviennent pas en stock ;
-- un produit vendu peut être remis en stock (p_restock).
create function public.salon_ticket_refund(
  p_shop uuid, p_ticket uuid, p_line_ids uuid[], p_method text, p_restock boolean,
  p_reason text, p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'refund');
  v_t public.salon_tickets%rowtype;
  v_amount bigint;
  v_line record;
  v_after numeric;
begin
  if p_operation_key is null or char_length(p_operation_key) not between 8 and 80 then
    raise exception 'Operation key required' using errcode = '22023';
  end if;
  if exists (select 1 from public.salon_payments where shop_id = p_shop and operation_key = p_operation_key
             and ticket_id <> p_ticket) then
    raise exception 'Operation key already used' using errcode = '22023';
  end if;
  if exists (select 1 from public.salon_payments where shop_id = p_shop and operation_key = p_operation_key) then
    return public.salon_ticket_view(p_shop, p_ticket);
  end if;
  if p_reason is null or char_length(btrim(p_reason)) not between 3 and 200 then
    raise exception 'A reason is required' using errcode = '22023';
  end if;
  if p_method not in ('cash', 'mobile_money', 'card', 'other') then
    raise exception 'Invalid method' using errcode = '22023';
  end if;
  select * into v_t from public.salon_tickets where id = p_ticket and shop_id = p_shop for update;
  if not found then raise exception 'Ticket not found' using errcode = '42501'; end if;
  if v_t.status not in ('paid', 'partially_refunded') then
    raise exception 'Only a paid ticket can be refunded' using errcode = '22023';
  end if;
  if p_line_ids is null or cardinality(p_line_ids) = 0 or exists (
      select 1 from unnest(p_line_ids) x(id) where not exists (
        select 1 from public.salon_ticket_lines l
        where l.id = x.id and l.ticket_id = p_ticket and l.refunded_at is null)) then
    raise exception 'Invalid lines to refund' using errcode = '22023';
  end if;
  select coalesce(sum(net_xaf), 0) into v_amount from public.salon_ticket_lines
  where ticket_id = p_ticket and id = any(p_line_ids);
  if v_amount > v_t.paid_xaf - v_t.refunded_xaf then
    raise exception 'Refund exceeds amount paid' using errcode = '22023';
  end if;
  update public.salon_ticket_lines set refunded_at = now() where ticket_id = p_ticket and id = any(p_line_ids);
  if v_amount > 0 then
    insert into public.salon_payments (shop_id, ticket_id, kind, method, amount_xaf, operation_key,
                                       seq, note, recorded_by)
    values (p_shop, p_ticket, 'refund', p_method, v_amount, p_operation_key, 1, btrim(p_reason), auth.uid());
  end if;
  if coalesce(p_restock, false) then
    for v_line in select * from public.salon_ticket_lines
                  where ticket_id = p_ticket and id = any(p_line_ids) and kind = 'product' order by id loop
      update public.salon_supplies set quantity_on_hand = quantity_on_hand + v_line.quantity, updated_at = now()
      where id = v_line.supply_id returning quantity_on_hand into v_after;
      insert into public.salon_supply_movements (shop_id, supply_id, delta, quantity_after, reason,
        unit_cost_xaf, ticket_id, line_id, created_by)
      values (p_shop, v_line.supply_id, v_line.quantity, v_after, 'refund_restock',
        (select unit_cost_xaf from public.salon_supplies where id = v_line.supply_id),
        p_ticket, v_line.id, auth.uid());
    end loop;
  end if;
  update public.salon_tickets set refunded_xaf = refunded_xaf + v_amount,
    status = case when exists (select 1 from public.salon_ticket_lines
                               where ticket_id = p_ticket and refunded_at is null)
                  then 'partially_refunded' else 'refunded' end
  where id = p_ticket;
  perform public.salon_log(p_shop, v_role, 'ticket_refunded', p_ticket,
    jsonb_build_object('amount_xaf', v_amount, 'lines', cardinality(p_line_ids),
                       'restock', coalesce(p_restock, false), 'reason', btrim(p_reason)));
  return public.salon_ticket_view(p_shop, p_ticket);
end;
$$;

create function public.salon_ticket_get(p_shop uuid, p_ticket uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'checkout');
  v jsonb := public.salon_ticket_view(p_shop, p_ticket);
begin
  if v is null then raise exception 'Ticket not found' using errcode = '42501'; end if;
  return v;
end;
$$;

-- Notes du jour (ouvertes et payées), pour la caisse.
create function public.salon_tickets_recent(p_shop uuid, p_days integer default 1)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'checkout');
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'status', t.status,
      'client_name', t.client_name, 'total_xaf', t.total_xaf, 'paid_xaf', t.paid_xaf,
      'refunded_xaf', t.refunded_xaf, 'opened_at', t.opened_at, 'paid_at', t.paid_at,
      'appointment_id', t.appointment_id) order by t.opened_at desc)
    from public.salon_tickets t
    where t.shop_id = p_shop and (t.status = 'open'
      or t.opened_at >= now() - greatest(1, least(coalesce(p_days, 1), 31)) * interval '1 day')), '[]'::jsonb);
end;
$$;

-- 5. Commissions --------------------------------------------------------------------------------
-- Dû = commissions des lignes payées et non remboursées ; versé = paiements de commissions.
create function public.salon_commission_balances(p_shop uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'reports');
begin
  return coalesce((select jsonb_agg(jsonb_build_object('employee_id', e.id, 'full_name', e.full_name,
      'earned_xaf', x.earned, 'paid_xaf', x.paid, 'balance_xaf', x.earned - x.paid) order by e.full_name)
    from public.employees e
    join public.salon_staff_profiles p on p.employee_id = e.id
    cross join lateral (select
      coalesce((select sum(l.commission_xaf) from public.salon_ticket_lines l
                join public.salon_tickets t on t.id = l.ticket_id
                where l.employee_id = e.id and t.status in ('paid', 'partially_refunded', 'refunded')
                  and l.refunded_at is null), 0)::bigint as earned,
      coalesce((select sum(c.amount_xaf) from public.salon_commission_payouts c
                where c.employee_id = e.id), 0)::bigint as paid) x
    where e.shop_id = p_shop), '[]'::jsonb);
end;
$$;

create function public.salon_commission_pay(
  p_shop uuid, p_employee uuid, p_amount_xaf bigint, p_method text, p_note text, p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'commission_payout');
  v_balance bigint;
begin
  if p_operation_key is null or char_length(p_operation_key) not between 8 and 80 then
    raise exception 'Operation key required' using errcode = '22023';
  end if;
  if exists (select 1 from public.salon_commission_payouts where shop_id = p_shop and operation_key = p_operation_key) then
    return public.salon_commission_balances(p_shop);
  end if;
  perform 1 from public.employees where id = p_employee and shop_id = p_shop for update;
  if not found then raise exception 'Collaborator not found' using errcode = '42501'; end if;
  select (b ->> 'balance_xaf')::bigint into v_balance
  from jsonb_array_elements(public.salon_commission_balances(p_shop)) b
  where (b ->> 'employee_id')::uuid = p_employee;
  if p_amount_xaf is null or p_amount_xaf <= 0 or p_amount_xaf > coalesce(v_balance, 0) then
    raise exception 'Amount exceeds commission due' using errcode = '22023';
  end if;
  insert into public.salon_commission_payouts (shop_id, employee_id, amount_xaf, method, note,
                                               operation_key, recorded_by)
  values (p_shop, p_employee, p_amount_xaf, p_method, nullif(btrim(p_note), ''), p_operation_key, auth.uid());
  perform public.salon_log(p_shop, v_role, 'commission_paid', p_employee,
    jsonb_build_object('amount_xaf', p_amount_xaf));
  return public.salon_commission_balances(p_shop);
end;
$$;

revoke all on function public.salon_ticket_view(uuid, uuid), public.salon_ticket_recompute(uuid)
  from public, anon, authenticated;
revoke all on function
  public.salon_supplies_list(uuid),
  public.salon_supply_save(uuid, uuid, text, text, text, text, numeric, numeric, bigint, boolean),
  public.salon_supply_adjust(uuid, uuid, text, numeric, numeric, text, text),
  public.salon_service_consumables_set(uuid, uuid, jsonb),
  public.salon_service_consumables_get(uuid, uuid),
  public.salon_ticket_open(uuid, uuid, uuid, text, text),
  public.salon_ticket_add_line(uuid, uuid, text, uuid, uuid, numeric, bigint),
  public.salon_ticket_remove_line(uuid, uuid, uuid),
  public.salon_ticket_set_discount(uuid, uuid, bigint),
  public.salon_ticket_cancel(uuid, uuid),
  public.salon_ticket_pay(uuid, uuid, jsonb, text),
  public.salon_ticket_refund(uuid, uuid, uuid[], text, boolean, text, text),
  public.salon_ticket_get(uuid, uuid),
  public.salon_tickets_recent(uuid, integer),
  public.salon_commission_balances(uuid),
  public.salon_commission_pay(uuid, uuid, bigint, text, text, text)
  from public, anon;
grant execute on function
  public.salon_supplies_list(uuid),
  public.salon_supply_save(uuid, uuid, text, text, text, text, numeric, numeric, bigint, boolean),
  public.salon_supply_adjust(uuid, uuid, text, numeric, numeric, text, text),
  public.salon_service_consumables_set(uuid, uuid, jsonb),
  public.salon_service_consumables_get(uuid, uuid),
  public.salon_ticket_open(uuid, uuid, uuid, text, text),
  public.salon_ticket_add_line(uuid, uuid, text, uuid, uuid, numeric, bigint),
  public.salon_ticket_remove_line(uuid, uuid, uuid),
  public.salon_ticket_set_discount(uuid, uuid, bigint),
  public.salon_ticket_cancel(uuid, uuid),
  public.salon_ticket_pay(uuid, uuid, jsonb, text),
  public.salon_ticket_refund(uuid, uuid, uuid[], text, boolean, text, text),
  public.salon_ticket_get(uuid, uuid),
  public.salon_tickets_recent(uuid, integer),
  public.salon_commission_balances(uuid),
  public.salon_commission_pay(uuid, uuid, bigint, text, text, text)
  to authenticated;
