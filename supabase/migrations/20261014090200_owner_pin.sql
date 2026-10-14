-- Caisse multi-caissiers (4/4) : code du responsable et « mode comptoir » sur l'appareil partagé.
--
-- Problème : sur un appareil partagé connecté au compte du PROPRIÉTAIRE, après « Changer de
-- caissier », n'importe qui pouvait revenir à « Vous (responsable) » et ouvrir Stock, Bilan,
-- Charges… sans code. Décision du propriétaire : un code PIN du responsable est exigé pour
-- quitter le mode comptoir.
--
--   - owner_pins : un code par boutique (celui du propriétaire de la boutique), haché en bcrypt
--     (extensions.crypt + gen_salt('bf', 10)), jamais en clair, jamais renvoyé, jamais écrit dans
--     le journal. Mêmes règles que les PIN des caissiers : 4 à 6 chiffres, codes triviaux
--     refusés (member_pin_assert_strength), 5 échecs → verrouillage 15 minutes ;
--   - open_till_session exige désormais que le responsable ait choisi son code : sans lui, le
--     mode comptoir ne pourrait pas être quitté de façon sûre ('Owner PIN required') ;
--   - leave_counter_mode(boutique, code, jeton) vérifie le code du responsable PUIS ferme la
--     session de caisse ; unlock_till_session(boutique, jeton, PIN) rouvre la caisse verrouillée
--     après 5 minutes d'inactivité avec le PIN du caissier de la session ;
--   - open_till_session renvoie aussi user_id et can_view_shop_sales du caissier (filtre « ses
--     ventes » de l'écran du comptoir).
--
-- Limite assumée : le mode comptoir est une restriction de l'APPLICATION sur l'appareil du
-- propriétaire, dont la session Supabase reste ouverte. Le code du responsable est vérifié par la
-- base (et compté), mais quelqu'un qui sait utiliser les outils de développement du navigateur
-- pourrait appeler l'API avec la session du propriétaire. Pour un caissier en qui l'on n'a pas
-- confiance : son propre téléphone et son propre compte (cas a).
--
-- Les échecs de code ne lèvent PAS d'exception (elle annulerait l'incrément du compteur et le
-- journal) : statut jsonb 'ok' | 'invalid' | 'locked' | 'not_set'.
--
-- Migration non destructive : une table, des fonctions ; open_till_session est remplacée (même
-- signature, même retour plus deux champs).

-- 1. Table ------------------------------------------------------------------------------------
create table if not exists public.owner_pins (
  shop_id uuid primary key references public.shops(id) on delete cascade,
  pin_hash text not null check (pin_hash like '$2_$%'),
  failed_attempts integer not null default 0 check (failed_attempts >= 0),
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);

drop trigger if exists owner_pins_touch_updated_at on public.owner_pins;
create trigger owner_pins_touch_updated_at
  before update on public.owner_pins
  for each row execute function public.touch_updated_at();

-- RLS active SANS politique, aucun privilège : même le propriétaire ne lit pas l'empreinte.
alter table public.owner_pins enable row level security;
revoke all on public.owner_pins from public, anon, authenticated;

-- 2. Outil interne : vérification du code du responsable ------------------------------------------
-- Même logique que member_pin_check (compteur, verrouillage, remise à zéro). À appeler seulement
-- depuis une fonction qui a déjà vérifié que l'appelant est le propriétaire.
create or replace function public.owner_pin_check(p_shop_id uuid, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  c_max_failures constant integer := 5;
  c_lock constant interval := interval '15 minutes';
  v_row public.owner_pins%rowtype;
  v_failures integer;
begin
  select * into v_row from public.owner_pins o where o.shop_id = p_shop_id for update;
  if not found then
    return pg_catalog.jsonb_build_object('status', 'not_set');
  end if;
  if v_row.locked_until is not null and v_row.locked_until > pg_catalog.now() then
    return pg_catalog.jsonb_build_object('status', 'locked', 'retry_after', v_row.locked_until);
  end if;
  if p_pin is not null and p_pin ~ '^[0-9]{4,6}$'
     and extensions.crypt(p_pin, v_row.pin_hash) = v_row.pin_hash then
    if v_row.failed_attempts <> 0 or v_row.locked_until is not null then
      update public.owner_pins
      set failed_attempts = 0, locked_until = null
      where shop_id = p_shop_id;
    end if;
    return pg_catalog.jsonb_build_object('status', 'ok');
  end if;
  v_failures := case when v_row.locked_until is not null then 0 else v_row.failed_attempts end + 1;
  if v_failures >= c_max_failures then
    update public.owner_pins
    set failed_attempts = v_failures, locked_until = pg_catalog.now() + c_lock
    where shop_id = p_shop_id;
    return pg_catalog.jsonb_build_object('status', 'locked',
      'retry_after', pg_catalog.now() + c_lock);
  end if;
  update public.owner_pins
  set failed_attempts = v_failures, locked_until = null
  where shop_id = p_shop_id;
  return pg_catalog.jsonb_build_object('status', 'invalid',
    'attempts_left', c_max_failures - v_failures);
end;
$function$;

-- Journalise un échec du code du responsable (jamais le code).
create or replace function public.owner_pin_audit_failure(p_shop_id uuid, p_context text,
                                                          p_check jsonb)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if p_check ->> 'status' in ('invalid', 'locked') then
    perform public.shop_audit(p_shop_id, 'owner_pin_failed', null,
      pg_catalog.jsonb_build_object('context', p_context, 'result', p_check ->> 'status'));
  end if;
end;
$function$;

-- 3. RPC du propriétaire ---------------------------------------------------------------------------

-- État du code du responsable : {"pin_set": bool, "locked_until": ts|null}. Jamais le code.
create or replace function public.owner_pin_status(p_shop_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_row public.owner_pins%rowtype;
begin
  perform public.assert_shop_owner(p_shop_id);
  select * into v_row from public.owner_pins o where o.shop_id = p_shop_id;
  return pg_catalog.jsonb_build_object(
    'pin_set', found,
    'locked_until', case when v_row.locked_until > pg_catalog.now() then v_row.locked_until end);
end;
$function$;

-- Choisit ou change le code du responsable.
--   - premier code : p_current_pin ignoré ;
--   - changement : p_current_pin obligatoire et vérifié (compte comme un essai).
-- Retour : {"status": "ok"} | {"status": "invalid", "attempts_left"} | {"status": "locked",
-- "retry_after"}. Exceptions : 'Authentication required', 'Shop not found' (42501),
-- 'Invalid PIN format', 'PIN too simple' (22023).
create or replace function public.set_owner_pin(
  p_shop_id uuid,
  p_new_pin text,
  p_current_pin text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_check jsonb;
  v_had_pin boolean;
begin
  perform public.assert_shop_owner(p_shop_id);
  perform public.member_pin_assert_strength(p_new_pin);
  -- Sérialise les changements concurrents sur la boutique.
  perform 1 from public.shops s where s.id = p_shop_id for update;
  v_had_pin := exists (select 1 from public.owner_pins o where o.shop_id = p_shop_id);
  if v_had_pin then
    v_check := public.owner_pin_check(p_shop_id, p_current_pin);
    if v_check ->> 'status' <> 'ok' then
      perform public.owner_pin_audit_failure(p_shop_id, 'change', v_check);
      return v_check;
    end if;
    update public.owner_pins
    set pin_hash = extensions.crypt(p_new_pin, extensions.gen_salt('bf', 10)),
        failed_attempts = 0, locked_until = null
    where shop_id = p_shop_id;
  else
    insert into public.owner_pins (shop_id, pin_hash)
    values (p_shop_id, extensions.crypt(p_new_pin, extensions.gen_salt('bf', 10)));
  end if;
  perform public.shop_audit(p_shop_id,
    case when v_had_pin then 'owner_pin_changed' else 'owner_pin_set' end, null, '{}'::jsonb);
  return pg_catalog.jsonb_build_object('status', 'ok');
end;
$function$;

-- Code oublié : le propriétaire, dans l'espace complet (donc déjà reconnu, par exemple après
-- s'être reconnecté avec son mot de passe), efface son code puis en choisit un nouveau. Les
-- sessions de caisse ouvertes de la boutique sont fermées. Renvoie true si un code existait.
create or replace function public.reset_owner_pin(p_shop_id uuid)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_closed integer;
begin
  perform public.assert_shop_owner(p_shop_id);
  delete from public.owner_pins where shop_id = p_shop_id;
  if not found then
    return false;
  end if;
  update public.till_sessions
  set closed_at = pg_catalog.now()
  where shop_id = p_shop_id and closed_at is null;
  get diagnostics v_closed = row_count;
  perform public.shop_audit(p_shop_id, 'owner_pin_reset', null,
    pg_catalog.jsonb_build_object('till_sessions_closed', v_closed));
  return true;
end;
$function$;

-- Vérifie le code du responsable. Retour : 'ok' | 'invalid' | 'locked' | 'not_set'.
create or replace function public.verify_owner_pin(p_shop_id uuid, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_check jsonb;
begin
  perform public.assert_shop_owner(p_shop_id);
  v_check := public.owner_pin_check(p_shop_id, p_pin);
  perform public.owner_pin_audit_failure(p_shop_id, 'verify', v_check);
  return v_check;
end;
$function$;

-- Quitte le mode comptoir : code du responsable vérifié, PUIS fermeture de la session de caisse
-- donnée (si elle est encore ouverte). Retour : statut de owner_pin_check ; 'ok' seulement si le
-- code est bon. Un jeton inconnu, fermé ou d'une autre boutique n'empêche pas la sortie.
create or replace function public.leave_counter_mode(
  p_shop_id uuid,
  p_pin text,
  p_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_check jsonb;
  v_session public.till_sessions%rowtype;
begin
  perform public.assert_shop_owner(p_shop_id);
  v_check := public.owner_pin_check(p_shop_id, p_pin);
  if v_check ->> 'status' <> 'ok' then
    perform public.owner_pin_audit_failure(p_shop_id, 'leave_counter_mode', v_check);
    return v_check;
  end if;
  if p_token is not null and p_token ~ '^[0-9a-f]{64}$' then
    update public.till_sessions t
    set closed_at = pg_catalog.now()
    where t.token_hash = pg_catalog.sha256(pg_catalog.convert_to('covi-till:' || p_token, 'UTF8'))
      and t.shop_id = p_shop_id and t.closed_at is null
    returning * into v_session;
    if found then
      perform public.shop_audit(p_shop_id, 'till_session_closed', v_session.member_id::text,
        pg_catalog.jsonb_build_object('session_id', v_session.id));
    end if;
  end if;
  perform public.shop_audit(p_shop_id, 'counter_mode_left', null, '{}'::jsonb);
  return v_check;
end;
$function$;

-- Rouvre la caisse verrouillée (inactivité) avec le PIN du caissier de la session. Appelant :
-- propriétaire. Lève 'Till session invalid' (42501) si le jeton n'est plus valide (le front
-- revient alors au choix du caissier). Retour : statut de member_pin_check.
create or replace function public.unlock_till_session(p_shop_id uuid, p_token text, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_member public.shop_members%rowtype;
  v_check jsonb;
begin
  perform public.assert_shop_owner(p_shop_id);
  v_member := public.till_session_member(p_shop_id, p_token);
  v_check := public.member_pin_check(v_member.id, p_pin);
  if v_check ->> 'status' in ('invalid', 'locked') then
    perform public.shop_audit(p_shop_id, 'till_session_pin_failed', v_member.id::text,
      pg_catalog.jsonb_build_object('display_name', v_member.display_name,
        'result', v_check ->> 'status', 'context', 'unlock'));
  end if;
  return v_check;
end;
$function$;

-- 4. open_till_session : code du responsable obligatoire -----------------------------------------
-- Identique à 20261014090050_member_pins.sql, sauf :
--   - 'Owner PIN required' (42501) tant que le responsable n'a pas choisi son code ;
--   - le retour contient aussi user_id et can_view_shop_sales du caissier.
create or replace function public.open_till_session(
  p_shop_id uuid,
  p_member_id uuid,
  p_pin text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  c_duration constant interval := interval '12 hours';
  v_member public.shop_members%rowtype;
  v_check jsonb;
  v_token text;
  v_session public.till_sessions%rowtype;
begin
  perform public.assert_shop_owner(p_shop_id);
  if not exists (select 1 from public.owner_pins o where o.shop_id = p_shop_id) then
    raise exception 'Owner PIN required' using errcode = '42501';
  end if;
  select * into v_member from public.shop_members m
  where m.id = p_member_id and m.shop_id = p_shop_id and m.active;
  if not found then
    raise exception 'Member not found' using errcode = '42501';
  end if;
  v_check := public.member_pin_check(v_member.id, p_pin);
  if v_check ->> 'status' <> 'ok' then
    if v_check ->> 'status' in ('invalid', 'locked') then
      perform public.shop_audit(p_shop_id, 'till_session_pin_failed', v_member.id::text,
        pg_catalog.jsonb_build_object('display_name', v_member.display_name,
          'result', v_check ->> 'status'));
    end if;
    return v_check;
  end if;
  v_token := pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.till_sessions (shop_id, member_id, token_hash, opened_by, expires_at)
  values (p_shop_id, v_member.id,
          pg_catalog.sha256(pg_catalog.convert_to('covi-till:' || v_token, 'UTF8')),
          auth.uid(), pg_catalog.now() + c_duration)
  returning * into v_session;
  perform public.shop_audit(p_shop_id, 'till_session_opened', v_member.id::text,
    pg_catalog.jsonb_build_object('display_name', v_member.display_name,
      'session_id', v_session.id, 'expires_at', v_session.expires_at));
  return pg_catalog.jsonb_build_object('status', 'ok', 'token', v_token,
    'session_id', v_session.id, 'expires_at', v_session.expires_at,
    'member_id', v_member.id, 'user_id', v_member.user_id,
    'display_name', v_member.display_name,
    'max_discount_pct', v_member.max_discount_pct,
    'can_view_shop_sales', v_member.can_view_shop_sales);
end;
$function$;

-- 5. Droits EXECUTE ------------------------------------------------------------------------------
revoke execute on function public.owner_pin_check(uuid, text) from public, anon, authenticated;
revoke execute on function public.owner_pin_audit_failure(uuid, text, jsonb)
  from public, anon, authenticated;

revoke execute on function public.owner_pin_status(uuid) from public, anon;
revoke execute on function public.set_owner_pin(uuid, text, text) from public, anon;
revoke execute on function public.reset_owner_pin(uuid) from public, anon;
revoke execute on function public.verify_owner_pin(uuid, text) from public, anon;
revoke execute on function public.leave_counter_mode(uuid, text, text) from public, anon;
revoke execute on function public.unlock_till_session(uuid, text, text) from public, anon;
revoke execute on function public.open_till_session(uuid, uuid, text) from public, anon;
grant execute on function public.owner_pin_status(uuid) to authenticated;
grant execute on function public.set_owner_pin(uuid, text, text) to authenticated;
grant execute on function public.reset_owner_pin(uuid) to authenticated;
grant execute on function public.verify_owner_pin(uuid, text) to authenticated;
grant execute on function public.leave_counter_mode(uuid, text, text) to authenticated;
grant execute on function public.unlock_till_session(uuid, text, text) to authenticated;
grant execute on function public.open_till_session(uuid, uuid, text) to authenticated;
