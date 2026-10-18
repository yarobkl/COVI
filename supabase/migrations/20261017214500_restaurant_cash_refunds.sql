-- Restaurant cash refunds: append-only evidence for actual cash returned to client.
-- Owner attestation only. Never infer a refund from an incident-review decision.
-- This migration is for disposable CI / non-production branch ONLY.
-- Enable strict tenant composite FK before creating the refund register.
alter table public.restaurant_served_incidents add constraint restaurant_incident_shop_id_key unique(shop_id,id);
create table public.restaurant_cash_refunds (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  session_id uuid not null,
  line_id uuid not null,
  incident_id uuid not null,
  operation_id uuid not null,
  amount_xaf bigint not null check(amount_xaf>0),
  method text not null default 'cash' check(method='cash'),
  reason text not null check(length(btrim(reason)) between 12 and 500),
  confirmed_by uuid not null references auth.users(id),
  confirmed_at timestamptz not null default now(),
  unique(shop_id,operation_id),
  unique(shop_id,incident_id),
  foreign key(shop_id,session_id) references public.restaurant_table_sessions(shop_id,id),
  foreign key(shop_id,line_id) references public.restaurant_session_lines(shop_id,id),
  foreign key(shop_id,incident_id) references public.restaurant_served_incidents(shop_id,id)
);
-- Existing incident PK is id; add composite tenant key for a strict cross-tenant FK.
create index restaurant_refunds_session on public.restaurant_cash_refunds(shop_id,session_id);
create index restaurant_refunds_line on public.restaurant_cash_refunds(shop_id,line_id);
alter table public.restaurant_cash_refunds enable row level security;
revoke all on public.restaurant_cash_refunds from public,anon,authenticated;
grant select on public.restaurant_cash_refunds to authenticated;
create policy owner_restaurant_refunds on public.restaurant_cash_refunds
 for select to authenticated using(
  exists(select 1 from public.shops s
    where s.id=shop_id and s.owner_id=(select auth.uid())
      and s.business_kind='restaurant')
 );

alter table public.restaurant_staff_events drop constraint restaurant_staff_events_event_type_check;
alter table public.restaurant_staff_events add constraint restaurant_staff_events_event_type_check
 check(event_type in (
  'member_joined','member_disabled','table_opened','group_code_issued',
  'line_added','line_served','line_cancelled','table_cancelled','payment_confirmed',
  'served_issue_reported','served_issue_reviewed','cash_refund_confirmed'
 ));

-- Read-only authoritative eligibility, with lock-free preview. The write RPC recomputes
-- everything after acquiring the session lock; this preview is not authorization.
create function public.restaurant_cash_refund_quote(p_shop uuid,p_incident uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_i public.restaurant_served_incidents%rowtype;
 v_state text; v_line_value bigint;v_paid bigint;v_all_refunds bigint;v_line_refunds bigint;
 v_done uuid;v_possible bigint;v_ref text;
begin
 if auth.uid() is null or not exists(select 1 from public.shops s
   where s.id=p_shop and s.owner_id=auth.uid() and s.business_kind='restaurant')
 then raise exception 'Access denied' using errcode='42501';end if;
 select * into v_i from public.restaurant_served_incidents i
  where i.shop_id=p_shop and i.id=p_incident;
 if not found then raise exception 'Incident not found';end if;
 select ss.status,ss.order_reference into v_state,v_ref
  from public.restaurant_table_sessions ss
  where ss.shop_id=p_shop and ss.id=v_i.session_id;
 select l.quantity::bigint*l.unit_price_xaf into v_line_value
  from public.restaurant_session_lines l
  where l.shop_id=p_shop and l.id=v_i.line_id and l.session_id=v_i.session_id and l.status='served';
 if v_line_value is null then raise exception 'Incident line is not served';end if;
 select coalesce(sum(p.amount_xaf),0) into v_paid from public.restaurant_cash_payments p
  where p.shop_id=p_shop and p.session_id=v_i.session_id and p.method='cash';
 select coalesce(sum(r.amount_xaf),0) into v_all_refunds from public.restaurant_cash_refunds r
  where r.shop_id=p_shop and r.session_id=v_i.session_id;
 select coalesce(sum(r.amount_xaf),0) into v_line_refunds from public.restaurant_cash_refunds r
  where r.shop_id=p_shop and r.line_id=v_i.line_id;
 select r.id into v_done from public.restaurant_cash_refunds r
  where r.shop_id=p_shop and r.incident_id=v_i.id;
 v_possible:=greatest(0,least(v_line_value-v_line_refunds,v_paid-v_all_refunds));
 return jsonb_build_object(
  'incidentId',v_i.id,'orderReference',v_ref,'state',v_i.state,
  'paidXaf',v_paid::text,'refundedXaf',v_all_refunds::text,
  'linePriceXaf',v_line_value::text,'lineRefundedXaf',v_line_refunds::text,
  'maximumXaf',case when v_state='closed_paid' and v_i.state='requires_refund_review'
    and v_done is null then v_possible::text else '0' end,
  'alreadyRefunded',v_done is not null,'method','cash'
 );
end; $$;
revoke all on function public.restaurant_cash_refund_quote(uuid,uuid) from public,anon;
grant execute on function public.restaurant_cash_refund_quote(uuid,uuid) to authenticated;

-- Actual physical payout is explicitly attested by the owner. All checks and insertion
-- occur under the same locked SESSION, so parallel refunds never exceed gross receipts
-- or the ORIGINAL price snapshot of the served item.
create function public.restaurant_confirm_cash_refund(
 p_shop uuid,p_incident uuid,p_amount bigint,p_reason text,
 p_operation_id uuid,p_cash_handed_over boolean
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_i public.restaurant_served_incidents%rowtype;
 v_session_state text;v_line_price bigint;v_paid bigint;v_session_refunds bigint;
 v_line_refunds bigint;v_existing public.restaurant_cash_refunds%rowtype;v_refund_id uuid;
begin
 if auth.uid() is null or not exists(select 1 from public.shops s
  where s.id=p_shop and s.owner_id=auth.uid() and s.business_kind='restaurant')
 then raise exception 'Access denied' using errcode='42501';end if;
 if p_operation_id is null or p_incident is null or p_amount is null
  or p_amount<=0 or p_amount>999999999999
  or p_cash_handed_over is distinct from true
  or length(btrim(coalesce(p_reason,''))) not between 12 and 500 then
  raise exception 'Confirmed physical cash payout, amount and reason required';end if;
 -- Resolve session, then serialize ALL refunds/payments/corrections of this table.
 select * into v_i from public.restaurant_served_incidents
  where shop_id=p_shop and id=p_incident;
 if not found then raise exception 'Incident not found';end if;
 select status into v_session_state from public.restaurant_table_sessions
  where shop_id=p_shop and id=v_i.session_id for update;
 if not found then raise exception 'Session not found';end if;

 select * into v_existing from public.restaurant_cash_refunds r
  where r.shop_id=p_shop and r.operation_id=p_operation_id;
 if found then
  if v_existing.incident_id<>p_incident or v_existing.amount_xaf<>p_amount
   or v_existing.reason<>btrim(p_reason) or v_existing.confirmed_by<>auth.uid()
  then raise exception 'Operation key mismatch';end if;
  return jsonb_build_object('refundId',v_existing.id,'amountXaf',v_existing.amount_xaf::text,
   'confirmed',true,'alreadyRecorded',true);
 end if;
 -- Lock ticket while enforcing only one real refund per approved incident.
 select * into v_i from public.restaurant_served_incidents i
  where i.shop_id=p_shop and i.id=p_incident for update;
 if v_i.state<>'requires_refund_review' or v_session_state<>'closed_paid' then
  raise exception 'Refund not approved or original bill not fully settled';end if;
 if exists(select 1 from public.restaurant_cash_refunds r
  where r.shop_id=p_shop and r.incident_id=p_incident) then
  raise exception 'This incident already has a cash refund';end if;

 select l.quantity::bigint*l.unit_price_xaf into v_line_price
  from public.restaurant_session_lines l
  where l.id=v_i.line_id and l.shop_id=p_shop and l.session_id=v_i.session_id
    and l.status='served';
 if v_line_price is null then raise exception 'Item was not served';end if;
 select coalesce(sum(p.amount_xaf),0) into v_paid
  from public.restaurant_cash_payments p
  where p.shop_id=p_shop and p.session_id=v_i.session_id and p.method='cash';
 select coalesce(sum(r.amount_xaf),0) into v_session_refunds
  from public.restaurant_cash_refunds r
  where r.shop_id=p_shop and r.session_id=v_i.session_id;
 select coalesce(sum(r.amount_xaf),0) into v_line_refunds
  from public.restaurant_cash_refunds r
  where r.shop_id=p_shop and r.line_id=v_i.line_id;
 if p_amount>v_paid-v_session_refunds or p_amount>v_line_price-v_line_refunds then
  raise exception 'Cash refund exceeds amount previously collected or line price';end if;

 insert into public.restaurant_cash_refunds(shop_id,session_id,line_id,incident_id,
  operation_id,amount_xaf,reason,confirmed_by)
 values(p_shop,v_i.session_id,v_i.line_id,v_i.id,p_operation_id,p_amount,btrim(p_reason),auth.uid())
 returning id into v_refund_id;
 insert into public.restaurant_staff_events(shop_id,actor_user_id,session_id,line_id,event_type,details)
 values(p_shop,auth.uid(),v_i.session_id,v_i.line_id,'cash_refund_confirmed',
  jsonb_build_object('refundId',v_refund_id,'incidentId',v_i.id,
  'amountXaf',p_amount,'method','cash','operationId',p_operation_id));
 -- Original receipt and physical stock NEVER change. Refund exists only in
 -- separate cash-out ledger; net cash = cash payments - cash refunds.
 return jsonb_build_object('refundId',v_refund_id,'amountXaf',p_amount::text,
  'confirmed',true,'alreadyRecorded',false);
end; $$;
revoke all on function public.restaurant_confirm_cash_refund(uuid,uuid,bigint,text,uuid,boolean)
 from public,anon;
grant execute on function public.restaurant_confirm_cash_refund(uuid,uuid,bigint,text,uuid,boolean)
 to authenticated;

comment on table public.restaurant_cash_refunds is
 'Immutable physical cash-out register. CASH only; not digital payment refunds or automatic refunds. Each row owner-attested after cash has actually been handed to a client.';
