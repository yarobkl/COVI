-- Disposable PostgreSQL only. Minimal Auth contract, never run in Supabase.
create role anon;
create role authenticated;
create schema auth;
create table auth.users (id uuid primary key);
create table auth.sessions (
    id uuid primary key,
    user_id uuid not null references auth.users(id),
    not_after timestamptz
);
create function auth.jwt() returns jsonb language sql stable as $$
    select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;
create function auth.uid() returns uuid language sql stable as $$
    select (auth.jwt() ->> 'sub')::uuid
$$;
