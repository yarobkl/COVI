-- Restaurant: complaints about ALREADY SERVED articles. A complaint is not
-- a cancellation, reversal or proof of a refund.
create table public.restaurant_served_incidents (
 id uuid primary key default gen_random_uuid(),
 shop_id uuid not null,
 session_id uuid not null,
 line_id uuid not null,
 reported_by uuid not null references auth.users(id),
 operation_id uuid not null,
 description text not null check(length(btrim(description)) between 12 and 500),
 state text not null default 'open'
   check(state in ('open','reviewed','rejected','requires_refund_review')),
 owner_note text check(owner_note is null or length(btrim(owner_note)) between 12 and 500),
 reviewed_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 reviewed_at timestamptz,
 unique(shop_id,operation_id),
 foreign key(shop_id,session_id) references public.restaurant_table_sessions(shop_id,id),
 foreign key(shop_id,line_id) references public.restaurant_session_lines(shop_id,id),
 constraint incident_review_consistency check(
  (state='open' and reviewed_at is null and reviewed_by is null and owner_note is null)
  or (state<>'open' and reviewed_at is not null and reviewed_by is not null
      and owner_note is not null))
);
create index restaurant_incident_queue on public.restaurant_served_incidents(shop_id,state,created_at desc);
alter table public.restaurant_served_incidents enable row level security;
revoke all on public.restaurant_served_incidents from public,anon,authenticated;
grant select on public.restaurant_served_incidents to authenticated;
create policy owner_restaurant_incidents on public.restaurant_served_incidents
 for select to authenticated
 using(exists(select 1 from public.shops s where s.id=shop_id and s.owner_id=(select auth.uid())
 and s.business_kind='restaurant'));

-- All access controls are enforced by the server; users cannot access the helper.
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
    or (p_action='report_served_issue' and m.staff_role in ('waiter','kitchen','cashier'))
    or (p_action='mark_served' and m.staff_role in ('waiter','kitchen'))
    or (p_action='capture_cash' and m.staff_role='cashier')
   ));
$$;
revoke all on function public.restaurant_staff_allowed(uuid,text)
 from public,anon,authenticated;


-- Extend the private audit event dictionary, retaining cancellation and cash events.
alter table public.restaurant_staff_events drop constraint restaurant_staff_events_event_type_check;
alter table public.restaurant_staff_events add constraint restaurant_staff_events_event_type_check
 check(event_type in (
    'member_joined','member_disabled','table_opened','group_code_issued',
    'line_added','line_served','line_cancelled','table_cancelled','payment_confirmed',
    'served_issue_reported','served_issue_reviewed'
 ));

create function public.restaurant_report_served_issue(
 p_shop uuid,p_line uuid,p_description text,p_operation_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_id uuid;v_existing public.restaurant_served_incidents%rowtype;
 v_session uuid;v_state text;
begin
 if not public.restaurant_staff_allowed(p_shop,'report_served_issue') then
  raise exception 'Access denied' using errcode='42501'; end if;
 if p_operation_id is null or length(btrim(coalesce(p_description,''))) not between 12 and 500 then
  raise exception 'A valid operation and incident description are required'; end if;
 select * into v_existing from public.restaurant_served_incidents
 where shop_id=p_shop and operation_id=p_operation_id;
 if found then
  if v_existing.line_id<>p_line or v_existing.description<>btrim(p_description)
   or v_existing.reported_by<>auth.uid() then raise exception 'Operation key mismatch';end if;
  return jsonb_build_object('ticketId',v_existing.id,'state',v_existing.state);
 end if;
 select l.session_id,l.status into v_session,v_state
 from public.restaurant_session_lines l
 where l.shop_id=p_shop and l.id=p_line;
 if v_state is distinct from 'served' then
  raise exception 'Only served items may be reported';end if;
 -- Limit repeated incidents without deleting the original history.
 if (select count(*) from public.restaurant_served_incidents i
    where i.shop_id=p_shop and i.line_id=p_line and i.state='open')>=3 then
  raise exception 'Incident already awaiting owner review';end if;
 insert into public.restaurant_served_incidents(
  shop_id,session_id,line_id,reported_by,operation_id,description
 ) values(p_shop,v_session,p_line,auth.uid(),p_operation_id,btrim(p_description))
 returning id into v_id;
 insert into public.restaurant_staff_events(shop_id,actor_user_id,session_id,line_id,event_type,details)
 values(p_shop,auth.uid(),v_session,p_line,'served_issue_reported',
  jsonb_build_object('ticketId',v_id,'description',btrim(p_description)));
 return jsonb_build_object('ticketId',v_id,'state','open');
end; $$;
revoke all on function public.restaurant_report_served_issue(uuid,uuid,text,uuid)
 from public,anon;
grant execute on function public.restaurant_report_served_issue(uuid,uuid,text,uuid)
 to authenticated;

create function public.restaurant_review_served_issue(
 p_shop uuid,p_ticket uuid,p_decision text,p_note text
) returns boolean language plpgsql security definer set search_path=''
as $$
declare v_i public.restaurant_served_incidents%rowtype;
begin
 if auth.uid() is null or not exists(select 1 from public.shops s
  where s.id=p_shop and s.owner_id=auth.uid() and s.business_kind='restaurant')
 then raise exception 'Access denied' using errcode='42501';end if;
 if p_decision not in ('reviewed','rejected','requires_refund_review')
  or length(btrim(coalesce(p_note,''))) not between 12 and 500 then
  raise exception 'Decision and owner note required';end if;
 select * into v_i from public.restaurant_served_incidents
 where shop_id=p_shop and id=p_ticket for update;
 if not found then raise exception 'Incident not found';end if;
 if v_i.state<>'open' then raise exception 'Incident already reviewed';end if;
 update public.restaurant_served_incidents set
  state=p_decision,owner_note=btrim(p_note),
  reviewed_at=now(),reviewed_by=auth.uid()
 where shop_id=p_shop and id=p_ticket;
 insert into public.restaurant_staff_events(shop_id,actor_user_id,session_id,line_id,event_type,details)
 values(p_shop,auth.uid(),v_i.session_id,v_i.line_id,'served_issue_reviewed',
  jsonb_build_object('ticketId',v_i.id,'decision',p_decision,'note',btrim(p_note)));
 return true;
end; $$;
revoke all on function public.restaurant_review_served_issue(uuid,uuid,text,text)
 from public,anon;
grant execute on function public.restaurant_review_served_issue(uuid,uuid,text,text)
 to authenticated;

comment on table public.restaurant_served_incidents is
 'Operational issue only; does not change charges, cash receipts, paid state or beverage stock. Reimbursements require a separate verified cash ledger.';
