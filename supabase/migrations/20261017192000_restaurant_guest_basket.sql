-- COVI Restaurant: protected collaborative guest baskets.
-- STAGED ONLY. Public browsers must pass the Edge gateway + Turnstile on join.
-- The table QR is a location identifier, NOT sufficient authorization to join:
-- the owner issues a time-limited group admission code for the open session.
create table public.restaurant_group_admissions (
  shop_id uuid not null,
  session_id uuid not null,
  secret_digest text not null check (secret_digest ~ '^[a-f0-9]{64}$'),
  expires_at timestamptz not null,
  created_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  primary key (shop_id,session_id),
  foreign key (shop_id,session_id) references public.restaurant_table_sessions(shop_id,id)
);
alter table public.restaurant_group_admissions enable row level security;
revoke all on public.restaurant_group_admissions from public,anon,authenticated;
-- Codes are only readable when freshly issued; neither owner queries nor guests see hashes.

-- Guest action limit: per secret for mutations; protects both token theft and accidental retry storms.
create table public.restaurant_guest_action_limits (
  shop_id uuid not null,
  participant_id uuid not null,
  bucket_start timestamptz not null,
  calls integer not null default 0 check(calls between 1 and 80),
  primary key(shop_id,participant_id,bucket_start),
  foreign key(shop_id,participant_id) references public.restaurant_participants(shop_id,id)
);
-- The composite FK above also serves defense in depth, independent of join codes.
alter table public.restaurant_guest_action_limits enable row level security;
revoke all on public.restaurant_guest_action_limits from public,anon,authenticated;

-- Cross-table FK for participant ownership without exposing credentials.
alter table public.restaurant_participants
  add constraint restaurant_participants_shop_id_pair unique (shop_id,id);

-- Internal helper: limits <= 40 guest modifications per minute and per participant.
-- Only service_role and definer functions can call it.
create function public.restaurant_guest_limit(p_shop uuid,p_participant uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare b timestamptz;
begin
 b := date_trunc('minute',now());
 insert into public.restaurant_guest_action_limits(shop_id,participant_id,bucket_start,calls)
 values(p_shop,p_participant,b,1)
 on conflict(shop_id,participant_id,bucket_start) do update
 set calls=public.restaurant_guest_action_limits.calls+1
 where public.restaurant_guest_action_limits.calls<40;
 if not found then raise exception 'Too many actions, try again later'; end if;
end; $$;
revoke all on function public.restaurant_guest_limit(uuid,uuid) from public,anon,authenticated;

-- Owner activates a new one-time session code (not the permanent printed QR).
-- Regenerating deliberately invalidates the old code; existing participants remain.
create function public.restaurant_issue_group_code(p_shop uuid,p_session uuid)
returns text language plpgsql security definer set search_path=''
as $$
declare v_code text; v_status text;
begin
 if auth.uid() is null or not exists (
   select 1 from public.shops s where s.id=p_shop and s.owner_id=auth.uid()
     and s.business_kind='restaurant'
 ) then raise exception 'Access denied' using errcode='42501'; end if;
 select status into v_status from public.restaurant_table_sessions
 where id=p_session and shop_id=p_shop for update;
 if v_status is distinct from 'collecting' then raise exception 'This table is not collecting choices'; end if;
 -- Eight uppercase hex characters / 32 bits; Turnstile and server action rate limiting
 -- are required at the public gateway. The code is not a password or a QR replacement.
 v_code:=upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
 insert into public.restaurant_group_admissions(shop_id,session_id,secret_digest,expires_at,created_by)
 values(p_shop,p_session,encode(sha256(convert_to(v_code,'UTF8')),'hex'),
   now()+interval '3 hours',auth.uid())
 on conflict(shop_id,session_id) do update set
 secret_digest=excluded.secret_digest,expires_at=excluded.expires_at,
 created_by=excluded.created_by,updated_at=now();
 return v_code;
end; $$;
revoke all on function public.restaurant_issue_group_code(uuid,uuid)
 from public,anon,authenticated;
grant execute on function public.restaurant_issue_group_code(uuid,uuid) to authenticated;

-- Resolve a guest by knowing BOTH the table QR and their own temporary token;
-- never accept session_id, shop_id or participant_id supplied by the browser.
create function public.restaurant_guest_resolve(
 p_qr text,p_participant_token text
) returns table(shop_id uuid,session_id uuid,participant_id uuid,is_leader boolean,ready boolean)
language sql security definer set search_path=''
as $$
 select p.shop_id,p.session_id,p.id,p.is_leader,p.ready
 from public.restaurant_participants p
 join public.restaurant_table_sessions ss
    on ss.shop_id=p.shop_id and ss.id=p.session_id and ss.status='collecting'
 join public.restaurant_tables tt
    on tt.shop_id=ss.shop_id and tt.id=ss.table_id and tt.active
 where p_qr ~ '^[a-f0-9]{64}$' and tt.qr_token=p_qr
   and p_participant_token ~ '^[a-f0-9]{64}$'
   and p.participant_token=encode(sha256(convert_to(p_participant_token,'UTF8')),'hex')
 limit 1;
$$;
revoke all on function public.restaurant_guest_resolve(text,text) from public,anon,authenticated;

-- The Edge gateway is the sole public admission route. Owner opens group first.
create function public.restaurant_guest_join(p_qr text,p_join_code text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_shop uuid;v_session uuid;v_people integer;v_count integer;
        v_secret text;v_participant uuid;
begin
 if p_qr is null or p_qr !~ '^[a-f0-9]{64}$'
    or p_join_code is null or p_join_code !~ '^[A-F0-9]{8}$' then
   raise exception 'Invalid table or group code'; end if;
 select ss.shop_id,ss.id,ss.guest_count
 into v_shop,v_session,v_people
 from public.restaurant_tables tt
 join public.restaurant_table_sessions ss on ss.shop_id=tt.shop_id
   and ss.table_id=tt.id and ss.status='collecting'
 where tt.qr_token=p_qr and tt.active
 for update of ss;
 if not found then raise exception 'Table is not accepting participants'; end if;
 if not exists (
  select 1 from public.restaurant_group_admissions a
  where a.shop_id=v_shop and a.session_id=v_session
    and a.expires_at>now()
    and a.secret_digest=encode(sha256(convert_to(p_join_code,'UTF8')),'hex')
 ) then raise exception 'Invalid or expired group code'; end if;
 select count(*) into v_count from public.restaurant_participants
  where shop_id=v_shop and session_id=v_session;
 if v_count>=v_people then raise exception 'Group participant limit reached'; end if;
 -- Secret never stored in clear; the existing participant_token field stores only its digest.
 v_secret:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
 insert into public.restaurant_participants(shop_id,session_id,participant_token)
 values(v_shop,v_session,encode(sha256(convert_to(v_secret,'UTF8')),'hex'))
 returning id into v_participant;
 return jsonb_build_object(
  'participantToken',v_secret,'participantId',v_participant,
  'groupStatus','collecting','isLeader',false,'ready',false
 );
end; $$;
revoke all on function public.restaurant_guest_join(text,text) from public,anon,authenticated;
grant execute on function public.restaurant_guest_join(text,text) to service_role;

-- Guest chooses items from the same restaurant only; prices come from the database.
create function public.restaurant_guest_choose_item(
 p_qr text,p_secret text,p_item uuid,p_quantity integer
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_shop uuid;v_session uuid;v_person uuid;v_price bigint;v_item_kind text;v_line uuid;
begin
 if p_quantity is null or p_quantity<0 or p_quantity>100 then
   raise exception 'Invalid quantity'; end if;
 select r.shop_id,r.session_id,r.participant_id into v_shop,v_session,v_person
 from public.restaurant_guest_resolve(p_qr,p_secret) r;
 if not found then raise exception 'Guest session expired'; end if;
 perform 1 from public.restaurant_table_sessions
 where id=v_session and shop_id=v_shop and status='collecting' for update;
 if not found then raise exception 'Group already submitted'; end if;
 perform public.restaurant_guest_limit(v_shop,v_person);
 select price_xaf,kind into v_price,v_item_kind from public.restaurant_menu_items
 where shop_id=v_shop and id=p_item and available;
 if not found then raise exception 'Item unavailable'; end if;
 if v_item_kind='drink' and p_quantity>0 and not exists(
   select 1 from public.restaurant_menu_items
   where shop_id=v_shop and id=p_item and drink_stock-reserved_drink_stock>=p_quantity
 ) then raise exception 'Drink unavailable'; end if;
 if p_quantity=0 then
   delete from public.restaurant_session_lines
   where shop_id=v_shop and session_id=v_session and participant_id=v_person
     and menu_item_id=p_item and status='draft';
 else
   insert into public.restaurant_session_lines(
    shop_id,session_id,participant_id,menu_item_id,quantity,unit_price_xaf
   ) values(v_shop,v_session,v_person,p_item,p_quantity,v_price)
   on conflict(shop_id,session_id,participant_id,menu_item_id)
   where status='draft' and participant_id is not null
   do update set quantity=excluded.quantity,unit_price_xaf=excluded.unit_price_xaf
   returning id into v_line;
 end if;
 update public.restaurant_participants set ready=false where id=v_person and shop_id=v_shop;
 return jsonb_build_object('saved',true,'ready',false,'itemId',p_item,'quantity',p_quantity);
end; $$;
revoke all on function public.restaurant_guest_choose_item(text,text,uuid,integer)
 from public,anon,authenticated;
grant execute on function public.restaurant_guest_choose_item(text,text,uuid,integer) to service_role;

-- First "J'ai terminé" gets leader, based on serialized session row.
create function public.restaurant_guest_mark_ready(p_qr text,p_secret text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_shop uuid;v_session uuid;v_person uuid;v_leader boolean;v_ready integer;v_total integer;
begin
 select r.shop_id,r.session_id,r.participant_id into v_shop,v_session,v_person
 from public.restaurant_guest_resolve(p_qr,p_secret) r;
 if not found then raise exception 'Guest session expired'; end if;
 perform 1 from public.restaurant_table_sessions where id=v_session
   and shop_id=v_shop and status='collecting' for update;
 if not found then raise exception 'Group already submitted'; end if;
 perform public.restaurant_guest_limit(v_shop,v_person);
 update public.restaurant_participants set ready=true where id=v_person and shop_id=v_shop;
 if not exists(select 1 from public.restaurant_participants
  where shop_id=v_shop and session_id=v_session and is_leader) then
  update public.restaurant_participants set is_leader=true
  where id=v_person and shop_id=v_shop;
 end if;
 select is_leader into v_leader from public.restaurant_participants where id=v_person;
 select count(*),count(*) filter(where ready) into v_total,v_ready
 from public.restaurant_participants where shop_id=v_shop and session_id=v_session;
 return jsonb_build_object('isLeader',v_leader,'ready',true,
   'participants',v_total,'readyParticipants',v_ready);
end; $$;
revoke all on function public.restaurant_guest_mark_ready(text,text) from public,anon,authenticated;
grant execute on function public.restaurant_guest_mark_ready(text,text) to service_role;

-- Read-only summary scoped to the current guest, no participant tokens or identities.
create function public.restaurant_guest_status(p_qr text,p_secret text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_shop uuid;v_session uuid;v_person uuid;v_ready boolean;v_leader boolean;v_data jsonb;
begin
 select r.shop_id,r.session_id,r.participant_id,r.is_leader,r.ready
 into v_shop,v_session,v_person,v_leader,v_ready
 from public.restaurant_guest_resolve(p_qr,p_secret) r;
 if not found then return null; end if;
 select jsonb_build_object(
  'isLeader',v_leader,'ready',v_ready,
  'participants',(select count(*) from public.restaurant_participants p
     where p.shop_id=v_shop and p.session_id=v_session),
  'readyParticipants',(select count(*) from public.restaurant_participants p
     where p.shop_id=v_shop and p.session_id=v_session and p.ready),
  'lines',coalesce((select jsonb_agg(jsonb_build_object(
    'itemId',l.menu_item_id,'name',m.name,'quantity',l.quantity,
    'unitPriceXaf',l.unit_price_xaf,'mine',l.participant_id=v_person
  ) order by l.created_at,l.id)
  from public.restaurant_session_lines l join public.restaurant_menu_items m
    on m.shop_id=l.shop_id and m.id=l.menu_item_id
  where l.shop_id=v_shop and l.session_id=v_session and l.status='draft'), '[]'::jsonb)
 ) into v_data;
 return v_data;
end; $$;
revoke all on function public.restaurant_guest_status(text,text) from public,anon,authenticated;
grant execute on function public.restaurant_guest_status(text,text) to service_role;

-- Explicit permissions: never grant anon/authenticated direct execution.
-- Turnstile, origin, rate and session admission proof belong at the Edge gateway.
