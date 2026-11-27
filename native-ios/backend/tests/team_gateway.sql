-- Disposable PostgreSQL fixture. Request claims stand in for verified tokens.
begin;
insert into auth.users (id) values
    ('01000000-0000-4000-8000-000000000001'),
    ('01000000-0000-4000-8000-000000000002');
insert into auth.sessions (id, user_id) values
    ('11000000-0000-4000-8000-000000000001', '01000000-0000-4000-8000-000000000001'),
    ('11000000-0000-4000-8000-000000000002', '01000000-0000-4000-8000-000000000002');
insert into covi_native.establishments (id, owner_id) values
    ('21000000-0000-4000-8000-000000000001', '01000000-0000-4000-8000-000000000001');

do $$
declare gateway constant name := 'covi_native_team_gateway';
begin
    assert not (select rolcanlogin or rolsuper or rolbypassrls from pg_catalog.pg_roles
        where rolname = gateway), 'Gateway role is not a login or RLS bypass role';
    assert not pg_has_role('authenticated', gateway, 'MEMBER'), 'No authenticated membership';
    assert not pg_has_role('anon', gateway, 'MEMBER'), 'No anonymous membership';
    assert not has_table_privilege(gateway, 'auth.sessions', 'SELECT'), 'No direct session reads';
    assert not has_table_privilege(gateway, 'covi_native.establishments', 'INSERT'),
        'No direct establishment creation';
    assert not has_table_privilege(gateway, 'covi_native.memberships', 'UPDATE'), 'No direct role writes';
    assert not has_table_privilege(gateway, 'covi_native.team_invitations', 'SELECT'),
        'No direct invitation reads';
    assert not has_function_privilege(gateway, 'covi_native.current_account_id()', 'EXECUTE'),
        'No direct execution of session helpers';
end
$$;

set local role covi_native_team_gateway;
do $$
declare
    shop constant uuid := '21000000-0000-4000-8000-000000000001';
    first_invite record;
    revoked_invite record;
    accepted record;
begin
    begin
        perform covi_native.list_active_establishment_access();
        raise exception 'Gateway listed establishments without a session';
    exception when insufficient_privilege then null;
    end;

    perform set_config('request.jwt.claims',
        '{"sub":"01000000-0000-4000-8000-000000000001","session_id":"11000000-0000-4000-8000-000000000001"}',
        true);
    assert (select role from covi_native.list_active_establishment_access()
        where establishment_id = shop) = 'owner', 'Owner directory through gateway role';
    select * into first_invite from covi_native.issue_team_invitation(shop, 'cashier');
    select * into revoked_invite from covi_native.issue_team_invitation(shop, 'cashier');
    assert covi_native.revoke_team_invitation(shop, revoked_invite.invitation_id),
        'Owner can revoke through the gateway role';

    perform set_config('request.jwt.claims',
        '{"sub":"01000000-0000-4000-8000-000000000002","session_id":"11000000-0000-4000-8000-000000000002"}',
        true);
    assert not exists (select 1 from covi_native.list_active_establishment_access()),
        'Another account cannot list the owner establishment before joining';
    begin
        perform covi_native.issue_team_invitation(shop, 'manager');
        raise exception 'Gateway granted invitation authority to another account';
    exception when insufficient_privilege then null;
    end;
    begin
        perform covi_native.redeem_team_invitation(revoked_invite.code);
        raise exception 'Gateway accepted a revoked invitation';
    exception when invalid_parameter_value then null;
    end;
    select * into accepted from covi_native.redeem_team_invitation(first_invite.code);
    assert accepted.establishment_id = shop and accepted.role = 'cashier', 'Gateway accepts valid invitation';
    assert (select role from covi_native.list_active_establishment_access()
        where establishment_id = shop) = 'cashier', 'New membership appears through the same gateway role';
    raise notice 'PASS: private team gateway role';
end
$$;
rollback;
