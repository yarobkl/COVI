-- COVI Restaurant — audited cancellation without changing already-served items.
-- Development only. No production migration or public client permissions.
alter table public.restaurant_session_lines
  drop constraint restaurant_session_lines_status_check;
alter table public.restaurant_session_lines
  add constraint restaurant_session_lines_status_check
  check (status in ('draft','ordered','served','cancelled'));

alter table public.restaurant_staff_events
  drop constraint restaurant_staff_events_event_type_check;
alter table public.restaurant_staff_events
  add constraint restaurant_staff_events_event_type_check
  check (event_type in (
    'member_joined','member_disabled','table_opened','group_code_issued',
    'line_added','line_served','line_cancelled','table_cancelled','payment_confirmed'
  ));

-- Refuse accidental public access to a correction. An employee can only
-- cancel a line if explicitly assigned to service; owner has override.
create or replace function public.restaurant_staff_allowed(p_shop uuid,p_action text)
returns boolean language sql stable security definer set search_path=''
as $$
 select exists(select 1 from public.shops s
   where s.id=p_shop and s.owner_id=auth.uid() and s.business_kind='restaurant')
 or exists(select 1 from public.restaurant_staff_members m
  join public.shops s on s.id=m.shop_id and s.business_kind='restaurant'
  where m.shop_id=p_shop and m.user_id=auth.uid() and m.active
   and (
    p_action='view_room'
    or (p_action in ('open_table','issue_group_code','staff_add_item','cancel_line','cancel_empty_table')
        and m.staff_role='waiter')
    or (p_action='mark_served' and m.staff_role in ('waiter','kitchen'))
    or (p_action='capture_cash' and m.staff_role='cashier')
   ));
$$;
revoke all on function public.restaurant_staff_allowed(uuid,text)
 from public,anon,authenticated;

-- An ordered but NOT served line may be cancelled. History remains immutable:
-- price snapshot, quantity, staff identity and reason are preserved.
create function public.restaurant_cancel_order_line(
 p_shop uuid,p_line uuid,p_reason text
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare
 v_session uuid;
 v_row public.restaurant_session_lines%rowtype;
 v_state text;
 v_item_kind text;
 v_total bigint;
 v_paid bigint;
 v_remaining bigint;
 v_closed boolean:=false;
begin
 if not public.restaurant_staff_allowed(p_shop,'cancel_line') then
  raise exception 'Access denied' using errcode='42501';
 end if;
 if length(btrim(coalesce(p_reason,''))) not between 5 and 240 then
  raise exception 'Cancellation reason required (5-240 characters)';
 end if;

 select l.session_id into v_session from public.restaurant_session_lines l
  where l.shop_id=p_shop and l.id=p_line;
 if not found then raise exception 'Line not found'; end if;

 -- Identical lock order as the cash RPC and mark_served: session, then line.
 select status into v_state from public.restaurant_table_sessions
  where id=v_session and shop_id=p_shop for update;
 if v_state is distinct from 'submitted' then
  raise exception 'Only an active submitted order can be corrected';
 end if;
 select * into v_row from public.restaurant_session_lines
  where shop_id=p_shop and session_id=v_session and id=p_line for update;
 if v_row.status is distinct from 'ordered' then
  raise exception 'Only an unserved ordered line can be cancelled';
 end if;

 select coalesce(sum(quantity::bigint*unit_price_xaf),0)
  into v_total from public.restaurant_session_lines
  where shop_id=p_shop and session_id=v_session and status in ('ordered','served');
 select coalesce(sum(amount_xaf),0)
  into v_paid from public.restaurant_cash_payments
  where shop_id=p_shop and session_id=v_session;
 v_remaining:=v_total-v_row.quantity::bigint*v_row.unit_price_xaf;

 -- No change can make already received cash exceed the corrected bill.
 -- Also do not silently "close" a partially paid table from a waiter account.
 if v_remaining<v_paid or (v_paid>0 and v_remaining=v_paid) then
  raise exception 'Cancellation requires cashier reconciliation: payment already recorded';
 end if;
 select m.kind into v_item_kind from public.restaurant_menu_items m
  where m.shop_id=p_shop and m.id=v_row.menu_item_id;
 if v_item_kind='drink' then
  update public.restaurant_menu_items
  set reserved_drink_stock=reserved_drink_stock-v_row.quantity
  where shop_id=p_shop and id=v_row.menu_item_id
    and reserved_drink_stock>=v_row.quantity;
  if not found then raise exception 'Reserved drink stock is inconsistent'; end if;
 end if;

 update public.restaurant_session_lines set status='cancelled'
 where shop_id=p_shop and session_id=v_session and id=p_line;
 insert into public.restaurant_staff_events(
   shop_id,actor_user_id,session_id,line_id,event_type,details)
 values(p_shop,auth.uid(),v_session,p_line,'line_cancelled',
   jsonb_build_object('reason',btrim(p_reason),'quantity',v_row.quantity,
    'unitPriceXaf',v_row.unit_price_xaf,'itemId',v_row.menu_item_id));

 -- A completely cancelled meal with zero collected payments can be released.
 if v_remaining=0 and v_paid=0 then
  update public.restaurant_table_sessions
   set status='closed_cancelled',closed_at=now()
   where shop_id=p_shop and id=v_session;
  v_closed:=true;
  insert into public.restaurant_staff_events(shop_id,actor_user_id,session_id,event_type,details)
   values(p_shop,auth.uid(),v_session,'table_cancelled',
   jsonb_build_object('reason','all_ordered_lines_cancelled'));
 end if;
 return jsonb_build_object('cancelled',true,'tableReleased',v_closed,
  'remainingToBillXaf',v_remaining);
end; $$;
revoke all on function public.restaurant_cancel_order_line(uuid,uuid,text)
 from public,anon;
grant execute on function public.restaurant_cancel_order_line(uuid,uuid,text)
 to authenticated;

-- A table which has not sent ANY order may be released without a payment.
-- Keep its session and draft lines for audit; do not burn an order number.
alter table public.restaurant_table_sessions
  drop constraint session_order_state;
alter table public.restaurant_table_sessions
  add constraint session_order_state check (
    (status='collecting' and order_number is null and submitted_at is null)
    or (status='closed_cancelled' and order_number is null and submitted_at is null)
    or (status in ('submitted','closed_paid')
        and order_number is not null and submitted_at is not null)
    or (status='closed_cancelled' and order_number is not null and submitted_at is not null)
  );

create function public.restaurant_cancel_empty_table(
 p_shop uuid,p_session uuid,p_reason text
) returns boolean language plpgsql security definer set search_path=''
as $$
declare v_status text;
begin
 if not public.restaurant_staff_allowed(p_shop,'cancel_empty_table') then
  raise exception 'Access denied' using errcode='42501'; end if;
 if length(btrim(coalesce(p_reason,''))) not between 5 and 240 then
  raise exception 'Cancellation reason required (5-240 characters)'; end if;
 select status into v_status from public.restaurant_table_sessions
  where shop_id=p_shop and id=p_session for update;
 if v_status is distinct from 'collecting' then
  raise exception 'Cannot cancel a table with submitted order'; end if;
 -- All guest credentials expire because the session is no longer collecting.
 update public.restaurant_table_sessions
  set status='closed_cancelled',closed_at=now()
  where shop_id=p_shop and id=p_session;
 insert into public.restaurant_staff_events(shop_id,actor_user_id,session_id,event_type,details)
 values(p_shop,auth.uid(),p_session,'table_cancelled',
  jsonb_build_object('reason',btrim(p_reason),'stage','before_submission'));
 return true;
end; $$;
revoke all on function public.restaurant_cancel_empty_table(uuid,uuid,text)
 from public,anon;
grant execute on function public.restaurant_cancel_empty_table(uuid,uuid,text)
 to authenticated;
