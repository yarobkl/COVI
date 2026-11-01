-- WhatsApp Business foundation: one isolated connection and notification queue per shop.
create table if not exists public.whatsapp_connections (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  waba_id text,
  phone_number_id text,
  display_phone_number text,
  status text not null default 'disconnected' check (status in ('pending', 'connected', 'disconnected', 'error')),
  connected_at timestamptz,
  disconnected_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id),
  unique (phone_number_id)
);

create table if not exists public.whatsapp_notification_preferences (
  shop_id uuid primary key references public.shops(id) on delete cascade,
  enabled boolean not null default false,
  daily_report_enabled boolean not null default true,
  daily_report_time time not null default '21:30',
  timezone text not null default 'Africa/Brazzaville',
  low_stock_enabled boolean not null default true,
  low_stock_threshold integer not null default 3 check (low_stock_threshold >= 0),
  orders_enabled boolean not null default true,
  appointments_enabled boolean not null default true,
  cash_anomalies_enabled boolean not null default true,
  recipient_phone text,
  updated_at timestamptz not null default now()
);

create table if not exists public.whatsapp_outbox (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  event_type text not null,
  idempotency_key text not null,
  recipient_phone text not null,
  template_name text,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (status in ('queued', 'sending', 'sent', 'delivered', 'read', 'failed')),
  provider_message_id text,
  attempts integer not null default 0 check (attempts >= 0),
  last_error text,
  available_at timestamptz not null default now(),
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  unique (shop_id, idempotency_key)
);

create index if not exists whatsapp_outbox_ready_idx
  on public.whatsapp_outbox (status, available_at);

create table if not exists public.whatsapp_daily_reports (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  report_date date not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (status in ('queued', 'sent', 'failed')),
  provider_message_id text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  unique (shop_id, report_date)
);

create table if not exists public.whatsapp_webhook_events (
  id uuid primary key default gen_random_uuid(),
  event_id text not null unique,
  phone_number_id text,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  processed_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.whatsapp_connections enable row level security;
alter table public.whatsapp_notification_preferences enable row level security;
alter table public.whatsapp_outbox enable row level security;
alter table public.whatsapp_daily_reports enable row level security;
alter table public.whatsapp_webhook_events enable row level security;

create policy whatsapp_connections_owner on public.whatsapp_connections
  for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy whatsapp_preferences_member on public.whatsapp_notification_preferences
  for all to authenticated using (public.shop_role(shop_id) = 'owner') with check (public.shop_role(shop_id) = 'owner');

create policy whatsapp_outbox_owner on public.whatsapp_outbox
  for select to authenticated using (public.shop_role(shop_id) = 'owner');

create policy whatsapp_reports_member on public.whatsapp_daily_reports
  for select to authenticated using (public.shop_role(shop_id) is not null);

revoke all on public.whatsapp_webhook_events from anon, authenticated;
