-- COVI native team authority. Apply to a dedicated development project first.
create schema covi_native;
revoke all on schema covi_native from public, anon, authenticated;

create table covi_native.establishments (
    id uuid primary key,
    owner_id uuid not null references auth.users (id),
    archived_at timestamptz
);

create table covi_native.memberships (
    establishment_id uuid not null references covi_native.establishments (id),
    account_id uuid not null references auth.users (id),
    role text not null check (role in (
        'manager', 'seller', 'cashier', 'waiter', 'kitchen', 'stylist', 'reception'
    )),
    granted_at timestamptz not null default now(),
    revoked_at timestamptz,
    primary key (establishment_id, account_id)
);

alter table covi_native.establishments enable row level security;
alter table covi_native.memberships enable row level security;
revoke all on all tables in schema covi_native from public, anon, authenticated;

-- Used by trusted database operations to resolve authorization at execution
-- time. Revocations take effect even while a previously issued JWT is valid.
create function covi_native.current_staff_role(target_establishment uuid)
returns text
language sql stable security definer
set search_path = ''
as $$
    select case when e.owner_id = auth.uid() then 'owner' else m.role end
    from covi_native.establishments e
    left join covi_native.memberships m
      on m.establishment_id = e.id
     and m.account_id = auth.uid()
     and m.revoked_at is null
    where e.id = target_establishment and e.archived_at is null
$$;

revoke all on function covi_native.current_staff_role(uuid) from public, anon, authenticated;
