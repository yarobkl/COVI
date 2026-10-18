-- Read-only guest follow-up during/after submission, for network recovery.
-- Expires as soon as the shared bill is closed; old bearer tokens cannot access the next group.
create or replace function public.restaurant_guest_status(p_qr text,p_secret text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_shop uuid;v_session uuid;v_person uuid;v_ready boolean;v_leader boolean;
        v_reference text;v_state text;v_data jsonb;
begin
 if p_qr is null or p_qr !~ '^[a-f0-9]{64}$'
    or p_secret is null or p_secret !~ '^[a-f0-9]{64}$' then return null; end if;
 select ss.shop_id,ss.id,p.id,p.is_leader,p.ready,ss.order_reference,ss.status
 into v_shop,v_session,v_person,v_leader,v_ready,v_reference,v_state
 from public.restaurant_participants p
 join public.restaurant_table_sessions ss on ss.shop_id=p.shop_id and ss.id=p.session_id
 join public.restaurant_tables tt on tt.shop_id=ss.shop_id and tt.id=ss.table_id
 where tt.qr_token=p_qr and tt.active
   and ss.status in ('collecting','submitted')
   and p.participant_token=encode(sha256(convert_to(p_secret,'UTF8')),'hex');
 if not found then return null; end if;
 select jsonb_build_object(
  'groupStatus',v_state,'orderReference',v_reference,
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
  where l.shop_id=v_shop and l.session_id=v_session
   and (v_state='collecting' and l.status='draft'
        or v_state='submitted' and l.status in ('ordered','served'))), '[]'::jsonb)
 ) into v_data;
 return v_data;
end; $$;
revoke all on function public.restaurant_guest_status(text,text) from public,anon,authenticated;
grant execute on function public.restaurant_guest_status(text,text) to service_role;
