-- COVI Salon professionnel — fondation (lot 2/1).
--
-- Migration ADDITIVE : aucune table, colonne ou donnée existante n'est supprimée ni modifiée
-- (seules des colonnes facultatives sont ajoutées à salon_services). Les commerces et
-- restaurants ne sont pas concernés : chaque objet ci-dessous exige shops.business_kind='salon'.
--
-- Principe de sécurité du module : les nouvelles tables n'ont AUCUN droit direct pour anon ni
-- authenticated. Lectures et écritures passent par des fonctions SECURITY DEFINER qui vérifient
-- côté serveur le rôle de l'appelant dans CE salon (salon_require). Le shop_id envoyé par le
-- navigateur n'est jamais une preuve : il est toujours confronté à auth.uid().
--
-- Rôles : propriétaire (shops.owner_id), responsable (manager), coiffeur (stylist),
-- caissier (cashier). Les collaborateurs sans compte COVI restent de simples fiches
-- (employees + salon_staff_profiles) : ils reçoivent des rendez-vous et des commissions
-- mais n'ont aucun accès.

-- 1. Réglages du salon ---------------------------------------------------------------------
create table public.salon_settings (
  shop_id uuid primary key references public.shops(id) on delete cascade,
  salon_type text not null default 'mixed'
    check (salon_type in ('men', 'women', 'mixed', 'barber', 'beauty')),
  owner_name text check (owner_name is null or char_length(btrim(owner_name)) between 2 and 120),
  business_phone text check (business_phone is null or business_phone ~ '^[+]?[0-9]{6,20}$'),
  expected_staff_count integer check (expected_staff_count is null or expected_staff_count between 0 and 200),
  time_zone text not null default 'Africa/Brazzaville'
    check (time_zone in ('Africa/Brazzaville', 'Africa/Douala', 'Africa/Libreville',
                         'Africa/Ndjamena', 'Africa/Bangui', 'Africa/Malabo', 'Africa/Kinshasa',
                         'Africa/Lubumbashi', 'Africa/Abidjan', 'Africa/Dakar', 'UTC')),
  updated_at timestamptz not null default now()
);

-- Horaires d'ouverture : une plage par jour ISO (1 = lundi … 7 = dimanche). Jour absent = fermé.
-- Aucun horaire saisi = pas de contrôle d'ouverture (le salon n'a pas encore configuré).
create table public.salon_opening_hours (
  shop_id uuid not null references public.shops(id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 7),
  opens_at time not null,
  closes_at time not null,
  primary key (shop_id, weekday),
  check (closes_at > opens_at)
);

-- 2. Catalogue : colonnes facultatives ajoutées aux prestations existantes ---------------------
alter table public.salon_services
  add column if not exists category text
    check (category is null or char_length(btrim(category)) between 2 and 60),
  add column if not exists description text
    check (description is null or char_length(description) <= 500),
  add column if not exists direct_cost_xaf bigint not null default 0
    check (direct_cost_xaf between 0 and 1000000000),
  add column if not exists updated_at timestamptz not null default now();

-- 3. Collaborateurs ---------------------------------------------------------------------------
-- La fiche employé générique (employees) reste la référence RH ; le profil salon porte
-- uniquement ce qui sert au salon : règle de commission, téléphone pro, couleur d'agenda.
create unique index if not exists employees_shop_id_id_key on public.employees (shop_id, id);

create table public.salon_staff_profiles (
  employee_id uuid primary key,
  shop_id uuid not null references public.shops(id) on delete cascade,
  phone text check (phone is null or phone ~ '^[+]?[0-9]{6,20}$'),
  commission_mode text not null default 'none'
    check (commission_mode in ('none', 'percent', 'fixed')),
  commission_percent numeric(5,2) not null default 0 check (commission_percent between 0 and 100),
  commission_fixed_xaf bigint not null default 0 check (commission_fixed_xaf between 0 and 100000000),
  agenda_color text not null default '#17408b' check (agenda_color ~ '^#[0-9a-fA-F]{6}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, employee_id),
  foreign key (shop_id, employee_id) references public.employees (shop_id, id) on delete cascade,
  constraint salon_commission_consistent check (
    (commission_mode = 'none' and commission_percent = 0 and commission_fixed_xaf = 0)
    or (commission_mode = 'percent' and commission_fixed_xaf = 0)
    or (commission_mode = 'fixed' and commission_percent = 0)
  )
);

-- Habilitations : une prestation SANS aucune ligne ici peut être faite par tout collaborateur
-- actif ; dès qu'une ligne existe, seuls les collaborateurs listés sont habilités.
create table public.salon_staff_services (
  shop_id uuid not null references public.shops(id) on delete cascade,
  employee_id uuid not null,
  service_id uuid not null,
  primary key (employee_id, service_id),
  foreign key (shop_id, employee_id) references public.employees (shop_id, id) on delete cascade,
  foreign key (shop_id, service_id) references public.salon_services (shop_id, id) on delete cascade
);
create index salon_staff_services_by_service on public.salon_staff_services (shop_id, service_id);

-- Horaires de travail : jour sans ligne = repos. Aucun horaire saisi = suit l'ouverture du salon.
create table public.salon_staff_hours (
  shop_id uuid not null references public.shops(id) on delete cascade,
  employee_id uuid not null,
  weekday smallint not null check (weekday between 1 and 7),
  starts_at time not null,
  ends_at time not null,
  primary key (employee_id, weekday),
  foreign key (shop_id, employee_id) references public.employees (shop_id, id) on delete cascade,
  check (ends_at > starts_at)
);

-- Absences ponctuelles (congé, maladie) : bloquent toute prise de rendez-vous ce jour-là.
create table public.salon_staff_absences (
  shop_id uuid not null references public.shops(id) on delete cascade,
  employee_id uuid not null,
  day date not null,
  reason text check (reason is null or char_length(reason) <= 120),
  primary key (employee_id, day),
  foreign key (shop_id, employee_id) references public.employees (shop_id, id) on delete cascade
);

-- 4. Comptes d'accès des collaborateurs (rôles) -------------------------------------------------
create table public.salon_staff_members (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  employee_id uuid,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 80),
  role text not null check (role in ('manager', 'stylist', 'cashier')),
  active boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  disabled_at timestamptz,
  unique (shop_id, user_id),
  foreign key (shop_id, employee_id) references public.employees (shop_id, id),
  constraint salon_member_active_consistent check (active or disabled_at is not null),
  -- Un coiffeur voit « ses » rendez-vous : il doit être relié à sa fiche collaborateur.
  constraint salon_stylist_has_employee check (role <> 'stylist' or employee_id is not null)
);
create index salon_staff_members_by_user on public.salon_staff_members (user_id, active);

create table public.salon_staff_invites (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  code_digest bytea not null unique,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 80),
  role text not null check (role in ('manager', 'stylist', 'cashier')),
  employee_id uuid,
  created_by uuid not null references auth.users(id),
  expires_at timestamptz not null,
  used_by uuid references auth.users(id),
  used_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key (shop_id, employee_id) references public.employees (shop_id, id),
  constraint salon_invite_stylist_has_employee check (role <> 'stylist' or employee_id is not null)
);

create table public.salon_staff_invite_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  successful boolean not null,
  created_at timestamptz not null default now()
);
create index salon_invite_attempts_by_user on public.salon_staff_invite_attempts (user_id, created_at desc);

-- 5. Clients (CRM) ----------------------------------------------------------------------------
-- Données minimales. Les préférences ne sont gardées qu'avec le consentement du client.
-- L'anonymisation efface l'identité mais garde l'historique chiffré (visites, montants).
create table public.salon_clients (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  first_name text not null check (char_length(btrim(first_name)) between 1 and 80),
  last_name text check (last_name is null or char_length(btrim(last_name)) between 1 and 80),
  phone text check (phone is null or phone ~ '^[+]?[0-9]{6,20}$'),
  phone_key text,
  email text check (email is null or (char_length(email) <= 160 and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')),
  preferences text check (preferences is null or char_length(preferences) <= 500),
  preferences_consent boolean not null default false,
  reminder_consent boolean not null default false,
  consent_recorded_at timestamptz,
  anonymized_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, id),
  constraint salon_preferences_need_consent check (preferences is null or preferences_consent)
);
create index salon_clients_by_phone on public.salon_clients (shop_id, phone_key) where anonymized_at is null;
create index salon_clients_by_name on public.salon_clients (shop_id, lower(first_name), lower(coalesce(last_name, '')));

-- 6. Journal des opérations sensibles -----------------------------------------------------------
create table public.salon_events (
  id bigint generated always as identity primary key,
  shop_id uuid not null references public.shops(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  actor_role text not null,
  event_type text not null check (char_length(event_type) between 3 and 60),
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  at timestamptz not null default now()
);
create index salon_events_by_shop on public.salon_events (shop_id, at desc);

-- 7. Verrouillage : RLS partout, aucun droit direct -------------------------------------------
alter table public.salon_settings enable row level security;
alter table public.salon_opening_hours enable row level security;
alter table public.salon_staff_profiles enable row level security;
alter table public.salon_staff_services enable row level security;
alter table public.salon_staff_hours enable row level security;
alter table public.salon_staff_absences enable row level security;
alter table public.salon_staff_members enable row level security;
alter table public.salon_staff_invites enable row level security;
alter table public.salon_staff_invite_attempts enable row level security;
alter table public.salon_clients enable row level security;
alter table public.salon_events enable row level security;

revoke all on public.salon_settings, public.salon_opening_hours, public.salon_staff_profiles,
  public.salon_staff_services, public.salon_staff_hours, public.salon_staff_absences,
  public.salon_staff_members, public.salon_staff_invites, public.salon_staff_invite_attempts,
  public.salon_clients, public.salon_events
  from public, anon, authenticated;

-- Les lignes ne changent jamais de salon (même défense que les autres secteurs).
create trigger immutable_shop_salon_settings before update on public.salon_settings
  for each row execute function public.prevent_sector_shop_reassignment();
create trigger immutable_shop_salon_staff_profile before update on public.salon_staff_profiles
  for each row execute function public.prevent_sector_shop_reassignment();
create trigger immutable_shop_salon_member before update on public.salon_staff_members
  for each row execute function public.prevent_sector_shop_reassignment();
create trigger immutable_shop_salon_client before update on public.salon_clients
  for each row execute function public.prevent_sector_shop_reassignment();

-- 8. Rôle et permissions ----------------------------------------------------------------------
-- Rôle de l'utilisateur connecté dans ce salon, ou null.
create function public.salon_role(p_shop uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when auth.uid() is null or p_shop is null then null
    when exists (select 1 from public.shops s
                 where s.id = p_shop and s.owner_id = auth.uid() and s.business_kind = 'salon')
      then 'owner'
    else (select m.role from public.salon_staff_members m
          join public.shops s on s.id = m.shop_id and s.business_kind = 'salon'
          where m.shop_id = p_shop and m.user_id = auth.uid() and m.active)
  end
$$;

-- Matrice des droits. Toute fonction du module appelle salon_require avant d'agir.
--   owner   : tout.
--   manager : tout sauf réglages, accès des collaborateurs et paiement des commissions.
--   cashier : agenda complet, clients, caisse (pas de remboursement, pas de remise).
--   stylist : ses propres rendez-vous seulement (contrôlé dans chaque fonction).
create function public.salon_allowed(p_role text, p_action text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when p_role is null then false
    when p_role = 'owner' then true
    when p_action in ('settings', 'staff_access', 'commission_payout') then false
    when p_role = 'manager' then true
    when p_role = 'cashier' then p_action in ('agenda_all', 'agenda_write', 'clients', 'checkout', 'read_catalog', 'agenda_own')
    when p_role = 'stylist' then p_action in ('agenda_own', 'read_catalog')
    else false
  end
$$;

create function public.salon_require(p_shop uuid, p_action text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_role(p_shop);
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.salon_allowed(v_role, p_action) then
    raise exception 'Access denied' using errcode = '42501';
  end if;
  return v_role;
end;
$$;

-- Fiche collaborateur reliée au compte connecté (coiffeur), ou null.
create function public.salon_my_employee(p_shop uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.employee_id from public.salon_staff_members m
  where m.shop_id = p_shop and m.user_id = auth.uid() and m.active
$$;

create function public.salon_log(p_shop uuid, p_role text, p_type text, p_entity uuid, p_details jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.salon_events (shop_id, actor_id, actor_role, event_type, entity_id, details)
  values (p_shop, auth.uid(), coalesce(p_role, 'system'), p_type, p_entity, coalesce(p_details, '{}'::jsonb))
$$;

-- Clé de téléphone pour repérer les doublons : 9 derniers chiffres (numéros nationaux CEMAC).
create function public.salon_phone_key(p_phone text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 9), '')
$$;

revoke all on function public.salon_role(uuid), public.salon_allowed(text, text),
  public.salon_require(uuid, text), public.salon_my_employee(uuid),
  public.salon_log(uuid, text, text, uuid, jsonb), public.salon_phone_key(text)
  from public, anon;
-- salon_role est utile au front pour choisir l'interface ; les autres restent internes.
grant execute on function public.salon_role(uuid) to authenticated;
revoke all on function public.salon_allowed(text, text), public.salon_require(uuid, text),
  public.salon_my_employee(uuid), public.salon_log(uuid, text, text, uuid, jsonb),
  public.salon_phone_key(text)
  from authenticated;
