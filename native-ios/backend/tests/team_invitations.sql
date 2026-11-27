-- Disposable PostgreSQL fixture. The trusted caller supplies verified JWT claims.
do $$
declare
    owner_id uuid := pg_catalog.gen_random_uuid();
    member_id uuid := pg_catalog.gen_random_uuid();
    outsider_id uuid := pg_catalog.gen_random_uuid();
    owner_session uuid := pg_catalog.gen_random_uuid();
    member_session uuid := pg_catalog.gen_random_uuid();
    outsider_session uuid := pg_catalog.gen_random_uuid();
    shop uuid := pg_catalog.gen_random_uuid();
    other_shop uuid := pg_catalog.gen_random_uuid();
    first_invitation record;
    replacement record;
    revoked record;
    expired record;
    redeemed record;
    owner_claims text;
    member_claims text;
    outsider_claims text;
begin
    insert into auth.users(id) values (owner_id), (member_id), (outsider_id);
    insert into auth.sessions(id, user_id, not_after) values
        (owner_session, owner_id, null), (member_session, member_id, null),
        (outsider_session, outsider_id, now() - interval '1 minute');
    insert into covi_native.establishments(id, owner_id) values (shop, owner_id), (other_shop, outsider_id);
    owner_claims := jsonb_build_object('sub', owner_id, 'session_id', owner_session)::text;
    member_claims := jsonb_build_object('sub', member_id, 'session_id', member_session)::text;
    outsider_claims := jsonb_build_object('sub', outsider_id, 'session_id', outsider_session)::text;

    if has_table_privilege('authenticated', 'covi_native.team_invitations', 'SELECT')
        or has_function_privilege('anon', 'covi_native.redeem_team_invitation(uuid)', 'EXECUTE')
        or has_function_privilege('authenticated', 'covi_native.issue_team_invitation(uuid,text)', 'EXECUTE')
        or has_function_privilege('authenticated', 'covi_native.redeem_team_invitation(uuid)', 'EXECUTE')
        or has_function_privilege('authenticated', 'covi_native.revoke_team_invitation(uuid,uuid)', 'EXECUTE') then
        raise exception 'Private invitation operations granted to a client';
    end if;

    perform set_config('request.jwt.claims', owner_claims, true);
    select * into first_invitation from covi_native.issue_team_invitation(shop, 'cashier');
    select * into replacement from covi_native.issue_team_invitation(shop, 'stylist');
    select * into revoked from covi_native.issue_team_invitation(shop, 'cashier');
    select * into expired from covi_native.issue_team_invitation(shop, 'cashier');
    if first_invitation.code is null or not exists (
        select 1 from covi_native.team_invitations i
        where i.id = first_invitation.invitation_id and i.issued_by = owner_id
          and i.expires_at - i.issued_at = interval '24 hours'
          and i.code_digest = sha256(convert_to(first_invitation.code::text, 'UTF8'))
    ) then
        raise exception 'Invitation is missing its digest, issuer, or expiry';
    end if;
    if not covi_native.revoke_team_invitation(shop, revoked.invitation_id) then
        raise exception 'Invitation was not revoked';
    end if;
    if covi_native.revoke_team_invitation(shop, revoked.invitation_id) then
        raise exception 'Invitation was revoked twice';
    end if;
    update covi_native.team_invitations set issued_at = now() - interval '2 days', expires_at = now() - interval '1 day'
        where id = expired.invitation_id;
    begin
        perform covi_native.issue_team_invitation(other_shop, 'cashier');
        raise exception 'Owner issued an invitation for another establishment';
    exception when insufficient_privilege then null;
    end;
    begin
        perform covi_native.issue_team_invitation(shop, 'owner');
        raise exception 'Invitation attempted to grant owner authority';
    exception when check_violation then null;
    end;
    begin
        perform covi_native.redeem_team_invitation(first_invitation.code);
        raise exception 'Owner redeemed their own invitation';
    exception when invalid_parameter_value then null;
    end;

    perform set_config('request.jwt.claims', outsider_claims, true);
    begin
        perform covi_native.redeem_team_invitation(first_invitation.code);
        raise exception 'Expired session redeemed an invitation';
    exception when insufficient_privilege then null;
    end;

    perform set_config('request.jwt.claims', member_claims, true);
    begin
        perform covi_native.redeem_team_invitation(revoked.code);
        raise exception 'Revoked invitation was redeemed';
    exception when invalid_parameter_value then null;
    end;
    begin
        perform covi_native.redeem_team_invitation(expired.code);
        raise exception 'Expired invitation was redeemed';
    exception when invalid_parameter_value then null;
    end;
    select * into redeemed from covi_native.redeem_team_invitation(first_invitation.code);
    if redeemed.establishment_id is distinct from shop or redeemed.role is distinct from 'cashier'
        or covi_native.current_staff_role(shop) is distinct from 'cashier' then
        raise exception 'Invitation did not grant its intended membership';
    end if;
    begin
        perform covi_native.redeem_team_invitation(first_invitation.code);
        raise exception 'Consumed invitation was replayed';
    exception when invalid_parameter_value then null;
    end;
    begin
        perform covi_native.redeem_team_invitation(replacement.code);
        raise exception 'A different invitation overwrote an active membership';
    exception when invalid_parameter_value then null;
    end;
    begin
        perform covi_native.issue_team_invitation(shop, 'cashier');
        raise exception 'Collaborator issued an invitation';
    exception when insufficient_privilege then null;
    end;

    update covi_native.memberships set revoked_at = now()
        where establishment_id = shop and account_id = member_id;
    if covi_native.current_staff_role(shop) is not null then
        raise exception 'Revocation left the prior role active';
    end if;
    perform covi_native.redeem_team_invitation(replacement.code);
    if covi_native.current_staff_role(shop) is distinct from 'stylist' or
        (select count(*) from covi_native.memberships where establishment_id = shop and account_id = member_id) <> 1 then
        raise exception 'Fresh invitation did not restore a unique membership with the new role';
    end if;
end
$$;
select 'PASS: native team invitation lifecycle' as evidence;
