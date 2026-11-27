-- Private invitation lifecycle for the native team authority.
-- Provision a reviewed gateway in preproduction before exposing any action.
create table covi_native.team_invitations (
    id uuid primary key default pg_catalog.gen_random_uuid(),
    establishment_id uuid not null references covi_native.establishments(id),
    issued_by uuid not null references auth.users(id),
    role text not null check (role in (
        'manager', 'seller', 'cashier', 'waiter', 'kitchen', 'stylist', 'reception'
    )),
    code_digest bytea not null unique check (pg_catalog.octet_length(code_digest) = 32),
    issued_at timestamptz not null,
    expires_at timestamptz not null check (expires_at > issued_at),
    revoked_at timestamptz,
    redeemed_at timestamptz,
    redeemed_by uuid references auth.users(id),
    check ((redeemed_at is null) = (redeemed_by is null)),
    check (revoked_at is null or redeemed_at is null)
);
alter table covi_native.team_invitations enable row level security;
revoke all on covi_native.team_invitations from public, anon, authenticated;

create function covi_native.current_account_id()
returns uuid
language sql stable
set search_path = ''
as $$
    select s.user_id
    from auth.sessions s
    where s.user_id = auth.uid()
      and s.id::text = (auth.jwt() ->> 'session_id')
      and (s.not_after is null or s.not_after > pg_catalog.now())
$$;
revoke all on function covi_native.current_account_id() from public, anon, authenticated;

create or replace function covi_native.current_staff_role(target_establishment uuid)
returns text
language sql stable security definer
set search_path = ''
as $$
    select case when e.owner_id = account.id then 'owner' else m.role end
    from covi_native.establishments e
    cross join (select covi_native.current_account_id() id) account
    left join covi_native.memberships m
      on m.establishment_id = e.id
     and m.account_id = account.id
     and m.revoked_at is null
    where e.id = target_establishment and e.archived_at is null and account.id is not null
$$;
revoke all on function covi_native.current_staff_role(uuid) from public, anon, authenticated;

create function covi_native.issue_team_invitation(target_establishment uuid, target_role text)
returns table (invitation_id uuid, code uuid, expires_at timestamptz)
language plpgsql
set search_path = ''
as $$
declare
    actor uuid := covi_native.current_account_id();
    raw_code uuid := pg_catalog.gen_random_uuid();
    issued timestamptz;
begin
    perform 1 from covi_native.establishments e
     where e.id = target_establishment and e.archived_at is null for update;
    if not found or covi_native.current_staff_role(target_establishment) is distinct from 'owner' then
        raise exception 'Invitation authority required' using errcode = '42501';
    end if;
    issued := pg_catalog.clock_timestamp();
    return query
        insert into covi_native.team_invitations as i
            (establishment_id, issued_by, role, code_digest, issued_at, expires_at)
        values
            (target_establishment, actor, target_role,
             pg_catalog.sha256(pg_catalog.convert_to(raw_code::text, 'UTF8')), issued, issued + interval '24 hours')
        returning i.id, raw_code, i.expires_at;
end
$$;
revoke all on function covi_native.issue_team_invitation(uuid, text) from public, anon, authenticated;

create function covi_native.revoke_team_invitation(target_establishment uuid, target_invitation uuid)
returns boolean
language plpgsql
set search_path = ''
as $$
begin
    perform 1 from covi_native.establishments e
     where e.id = target_establishment and e.archived_at is null for update;
    if not found or covi_native.current_staff_role(target_establishment) is distinct from 'owner' then
        raise exception 'Invitation authority required' using errcode = '42501';
    end if;
    update covi_native.team_invitations i
       set revoked_at = pg_catalog.clock_timestamp()
     where i.id = target_invitation and i.establishment_id = target_establishment
       and i.revoked_at is null and i.redeemed_at is null;
    return found;
end
$$;
revoke all on function covi_native.revoke_team_invitation(uuid, uuid) from public, anon, authenticated;

create function covi_native.redeem_team_invitation(code uuid)
returns table (establishment_id uuid, role text)
language plpgsql
set search_path = ''
as $$
declare
    actor uuid := covi_native.current_account_id();
    digest bytea := pg_catalog.sha256(pg_catalog.convert_to(code::text, 'UTF8'));
    target uuid;
    invitation covi_native.team_invitations%rowtype;
    redeemed timestamptz;
begin
    if actor is null then
        raise exception 'Authenticated session required' using errcode = '42501';
    end if;
    select i.establishment_id into target from covi_native.team_invitations i
     where i.code_digest = digest;
    -- Match the lock order used by issue and revoke.
    perform 1 from covi_native.establishments e
     where e.id = target and e.archived_at is null and e.owner_id <> actor for update;
    if not found then
        raise exception 'Invitation unavailable' using errcode = '22023';
    end if;

    select i.* into invitation from covi_native.team_invitations i
     where i.code_digest = digest and i.establishment_id = target for update;
    redeemed := pg_catalog.clock_timestamp();
    if not found or invitation.revoked_at is not null or invitation.redeemed_at is not null
        or invitation.expires_at <= redeemed then
        raise exception 'Invitation unavailable' using errcode = '22023';
    end if;

    insert into covi_native.memberships as m
        (establishment_id, account_id, role, granted_at)
    values (target, actor, invitation.role, redeemed)
    on conflict on constraint memberships_pkey do update
      set role = excluded.role, granted_at = excluded.granted_at, revoked_at = null
    where m.revoked_at is not null;
    if not found then
        raise exception 'Invitation unavailable' using errcode = '22023';
    end if;
    update covi_native.team_invitations i
       set redeemed_at = redeemed, redeemed_by = actor
     where i.id = invitation.id;
    return query select target, invitation.role;
end
$$;
revoke all on function covi_native.redeem_team_invitation(uuid) from public, anon, authenticated;
