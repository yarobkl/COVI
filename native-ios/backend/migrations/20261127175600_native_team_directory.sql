-- Private read model for the native team's authenticated gateway.
create index establishments_active_owner
    on covi_native.establishments (owner_id) where archived_at is null;
create index memberships_active_account
    on covi_native.memberships (account_id) where revoked_at is null;

create function covi_native.list_active_establishment_access()
returns table (establishment_id uuid, role text)
language plpgsql stable
set search_path = ''
as $$
declare
    actor uuid := covi_native.current_account_id();
begin
    if actor is null then
        raise exception 'Authenticated session required' using errcode = '42501';
    end if;

    return query
        select e.id, 'owner'::text
        from covi_native.establishments e
        where e.owner_id = actor and e.archived_at is null
        union all
        select e.id, m.role
        from covi_native.memberships m
        join covi_native.establishments e on e.id = m.establishment_id
        where m.account_id = actor and m.revoked_at is null
          and e.archived_at is null and e.owner_id <> actor
        order by 1;
end
$$;
revoke all on function covi_native.list_active_establishment_access()
    from public, anon, authenticated;
