-- Run after bootstrap.sql and the native migration, in a disposable database.
begin;
insert into auth.users values
 ('00000000-0000-4000-8000-000000000001'),
 ('00000000-0000-4000-8000-000000000002'),
 ('00000000-0000-4000-8000-000000000003');
insert into auth.sessions values
 ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001', null),
 ('10000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000002', null),
 ('10000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000003', null);
insert into covi_native.establishments (id, owner_id) values
 ('20000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001'),
 ('20000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000003');
insert into covi_native.memberships(establishment_id, account_id, role) values
 ('20000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002', 'cashier');

do $$
declare
    shop constant uuid := '20000000-0000-4000-8000-000000000001';
    owner constant uuid := '00000000-0000-4000-8000-000000000001';
    employee constant uuid := '00000000-0000-4000-8000-000000000002';
    stranger constant uuid := '00000000-0000-4000-8000-000000000003';
begin
    perform set_config('request.jwt.claims', jsonb_build_object('sub', owner,
        'session_id', '10000000-0000-4000-8000-000000000001')::text, true);
    assert covi_native.current_staff_role(shop) = 'owner', 'Owner access';
    assert covi_native.current_staff_role('20000000-0000-4000-8000-000000000002') is null, 'Cross-owner isolation';
    insert into covi_native.memberships (establishment_id, account_id, role)
        values (shop, owner, 'cashier'),
            ('20000000-0000-4000-8000-000000000002', owner, 'reception');
    assert (select count(*) from covi_native.list_active_establishment_access()) = 2,
        'Owned and assigned establishments appear once';
    assert (select role from covi_native.list_active_establishment_access()
        where establishment_id = shop) = 'owner', 'Ownership takes precedence';
    assert (select role from covi_native.list_active_establishment_access()
        where establishment_id <> shop) = 'reception', 'Additional staff access is preserved';

    perform set_config('request.jwt.claims', jsonb_build_object('sub', employee,
        'session_id', '10000000-0000-4000-8000-000000000002',
        'user_metadata', jsonb_build_object('role', 'owner'))::text, true);
    assert covi_native.current_staff_role(shop) = 'cashier', 'User metadata cannot elevate access';
    assert (select role from covi_native.list_active_establishment_access()) = 'cashier',
        'Directory isolates staff to the assigned establishment and ignores metadata';
    update covi_native.memberships set role = 'kitchen' where account_id = employee;
    assert covi_native.current_staff_role(shop) = 'kitchen', 'Role reread with existing JWT';
    assert (select role from covi_native.list_active_establishment_access()) = 'kitchen',
        'Directory rereads the assigned role';
    update covi_native.memberships set revoked_at = now() where account_id = employee;
    assert covi_native.current_staff_role(shop) is null, 'Membership revoked';
    assert not exists (select 1 from covi_native.list_active_establishment_access()),
        'Revoked membership disappears from the directory';
    update covi_native.memberships set revoked_at = null where account_id = employee;
    delete from auth.sessions where user_id = employee;
    assert covi_native.current_staff_role(shop) is null, 'Session revoked despite same JWT';
    begin
        perform covi_native.list_active_establishment_access();
        raise exception 'Directory accepted a revoked session';
    exception when insufficient_privilege then null;
    end;

    perform set_config('request.jwt.claims', jsonb_build_object('sub', owner,
        'session_id', '10000000-0000-4000-8000-000000000003')::text, true);
    assert covi_native.current_staff_role(shop) is null, 'Session belongs to another account';
    perform set_config('request.jwt.claims', jsonb_build_object('sub', owner)::text, true);
    assert covi_native.current_staff_role(shop) is null, 'Missing session refused';
    perform set_config('request.jwt.claims', '{}', true);
    assert covi_native.current_staff_role(shop) is null, 'Anonymous refused';

    perform set_config('request.jwt.claims', jsonb_build_object('sub', owner,
        'session_id', '10000000-0000-4000-8000-000000000001')::text, true);
    update auth.sessions set not_after = now() - interval '1 second' where user_id = owner;
    assert covi_native.current_staff_role(shop) is null, 'Expired session refused';
    begin
        perform covi_native.list_active_establishment_access();
        raise exception 'Directory accepted an expired session';
    exception when insufficient_privilege then null;
    end;
    update auth.sessions set not_after = null where user_id = owner;
    update covi_native.establishments set archived_at = now() where id = shop;
    assert covi_native.current_staff_role(shop) is null, 'Archived establishment refused';
    assert not exists (select 1 from covi_native.list_active_establishment_access()
        where establishment_id = shop), 'Archived establishment disappears from the directory';
    update covi_native.establishments set archived_at = null where id = shop;

    insert into covi_native.establishments(id, owner_id) values (gen_random_uuid(), owner), (gen_random_uuid(), owner);
    begin
        insert into covi_native.establishments(id, owner_id) values (gen_random_uuid(), owner);
        raise exception 'Fourth establishment accepted';
    exception when check_violation then null;
    end;
    insert into covi_native.establishments(id, owner_id, archived_at) values
        ('20000000-0000-4000-8000-000000000004', owner, now());
    begin
        update covi_native.establishments set archived_at = null where id = '20000000-0000-4000-8000-000000000004';
        raise exception 'Fourth active establishment reactivated';
    exception when check_violation then null;
    end;
    begin
        update covi_native.establishments set owner_id = stranger where id = shop;
        raise exception 'Owner silently reassigned';
    exception when check_violation then null;
    end;
    assert not has_schema_privilege('anon', 'covi_native', 'USAGE'), 'Anonymous schema inaccessible';
    assert not has_table_privilege('authenticated', 'covi_native.memberships', 'SELECT'), 'No direct membership reads';
    assert not has_table_privilege('authenticated', 'covi_native.memberships', 'UPDATE'), 'No direct role writes';
    assert not has_function_privilege('authenticated', 'covi_native.current_staff_role(uuid)', 'EXECUTE'), 'Private role resolver';
    assert not has_function_privilege('authenticated', 'covi_native.list_active_establishment_access()', 'EXECUTE'),
        'Authenticated clients cannot bypass the gateway';
    assert not has_function_privilege('anon', 'covi_native.list_active_establishment_access()', 'EXECUTE'),
        'Anonymous clients cannot call the directory';
    assert (select bool_and(relrowsecurity) from pg_class where oid in
        ('covi_native.establishments'::regclass, 'covi_native.memberships'::regclass)), 'RLS enabled';
    raise notice 'PASS: team authority assertions';
end
$$;
rollback;
