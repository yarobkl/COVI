-- Stubs Supabase minimaux pour rejouer les migrations COVI sur un PostgreSQL vierge.
-- Ce fichier n'est JAMAIS appliqué en production : il remplace seulement, pour les tests
-- locaux et la CI, ce que la plateforme Supabase fournit déjà (rôles, schémas auth et storage,
-- privilèges par défaut).

-- Rôles d'API Supabase. Les privilèges par défaut ci-dessous reproduisent ceux de Supabase :
-- anon, authenticated et service_role reçoivent tous les droits sur les objets de public,
-- la RLS et les REVOKE des migrations faisant le reste.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end
$$;

grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;

-- Extensions : comme sur Supabase, pgcrypto vit dans le schéma `extensions` (la migration
-- 20261005234321 fait `create extension if not exists pgcrypto`, sans effet si elle est déjà là).
-- Les fonctions PIN (20261014090050) appellent extensions.crypt / extensions.gen_salt.
create schema if not exists extensions;
grant usage on schema extensions to anon, authenticated, service_role;
create extension if not exists pgcrypto with schema extensions;

-- Schéma auth : seule la table des utilisateurs (clé étrangère de shops.owner_id) et auth.uid().
create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;

create table if not exists auth.users (id uuid primary key);

-- Même définition que Supabase : le sujet du JWT, lu dans les réglages de la requête.
create or replace function auth.uid() returns uuid
language sql stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;
grant execute on function auth.uid() to anon, authenticated, service_role;

-- Schéma storage : tables et fonction utilisées par les politiques des photos produits.
create schema if not exists storage;
grant usage on schema storage to anon, authenticated, service_role;

create table if not exists storage.buckets (
  id text primary key,
  name text not null,
  owner uuid,
  public boolean default false,
  file_size_limit bigint,
  allowed_mime_types text[],
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text,
  owner uuid,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  last_accessed_at timestamptz default now(),
  metadata jsonb
);
alter table storage.objects enable row level security;
grant select, insert, update, delete on storage.objects to authenticated, service_role;
grant select on storage.buckets to authenticated, service_role;

-- Même définition que Supabase : tous les segments du chemin sauf le dernier.
create or replace function storage.foldername(name text) returns text[]
language plpgsql immutable
as $$
declare
  _parts text[];
begin
  select string_to_array(name, '/') into _parts;
  return _parts[1 : array_length(_parts, 1) - 1];
end
$$;
grant execute on function storage.foldername(text) to anon, authenticated, service_role;

-- Même définition que Supabase : extension du fichier (dernier segment, après le dernier point).
-- Utilisée par les politiques des photos de profil (migration 20261013045706).
create or replace function storage.extension(name text) returns text
language plpgsql immutable
as $$
declare
  _parts text[];
  _filename text;
begin
  select string_to_array(name, '/') into _parts;
  select _parts[array_length(_parts, 1)] into _filename;
  return reverse(split_part(reverse(_filename), '.', 1));
end
$$;
grant execute on function storage.extension(text) to anon, authenticated, service_role;

-- Supabase Vault : secrets chiffrés en production ; ici une table en clair suffit pour les tests.
-- Mêmes signatures que l'extension supabase_vault (create_secret, update_secret, decrypted_secrets).
create schema if not exists vault;
create table if not exists vault.secrets (
  id uuid primary key default gen_random_uuid(),
  name text unique,
  description text not null default '',
  secret text not null
);
create or replace view vault.decrypted_secrets as
  select id, name, description, secret as decrypted_secret from vault.secrets;
create or replace function vault.create_secret(
  new_secret text, new_name text default null, new_description text default '',
  new_key_id uuid default null) returns uuid
language sql as $$
  insert into vault.secrets (secret, name, description) values (new_secret, new_name, new_description)
  returning id
$$;
create or replace function vault.update_secret(
  secret_id uuid, new_secret text default null, new_name text default null,
  new_description text default null, new_key_id uuid default null) returns void
language sql as $$
  update vault.secrets set secret = coalesce(new_secret, secret), name = coalesce(new_name, name),
    description = coalesce(new_description, description) where id = secret_id
$$;
revoke all on schema vault from public;
