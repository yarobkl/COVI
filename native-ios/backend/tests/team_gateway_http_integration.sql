-- Disposable PostgreSQL service only. This login is never provisioned in Supabase.
create role covi_http_test_login login noinherit password 'covi-http-disposable-only';
grant covi_native_team_gateway to covi_http_test_login;

insert into auth.users (id) values
    ('02000000-0000-4000-8000-000000000001'),
    ('02000000-0000-4000-8000-000000000002');
insert into auth.sessions (id, user_id) values
    ('12000000-0000-4000-8000-000000000001', '02000000-0000-4000-8000-000000000001'),
    ('12000000-0000-4000-8000-000000000002', '02000000-0000-4000-8000-000000000002');
insert into covi_native.establishments (id, owner_id) values
    ('22000000-0000-4000-8000-000000000001', '02000000-0000-4000-8000-000000000001');
