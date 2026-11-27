-- Private database role for an authenticated server gateway. The gateway
-- verifies the access token and sets request.jwt.claims transaction-locally.
-- Do not grant this role to client roles or to the Data API authenticator.
create role covi_native_team_gateway nologin noinherit;
grant usage on schema covi_native to covi_native_team_gateway;

-- These entry points read Auth sessions and the team's private tables on
-- behalf of the caller. Each checks its existing session or ownership rules.
-- Their fixed search path and lack of dynamic SQL are part of this boundary.
alter function covi_native.list_active_establishment_access() security definer;
alter function covi_native.issue_team_invitation(uuid, text) security definer;
alter function covi_native.revoke_team_invitation(uuid, uuid) security definer;
alter function covi_native.redeem_team_invitation(uuid) security definer;

grant execute on function
    covi_native.list_active_establishment_access(),
    covi_native.issue_team_invitation(uuid, text),
    covi_native.revoke_team_invitation(uuid, uuid),
    covi_native.redeem_team_invitation(uuid)
    to covi_native_team_gateway;
