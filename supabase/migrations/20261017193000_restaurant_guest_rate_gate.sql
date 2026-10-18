-- COVI restaurant: durable public gateway quotas, intentionally in a separate
-- transaction from the actual guest action so FAILED PIN guesses are also counted.
-- Caller passes keyed HMAC of the source; never raw IP or device identifier.
create table public.restaurant_guest_gateway_limits (
  scope text not null check(scope in ('source','qr')),
  operation text not null check(operation in ('join','guest')),
  fingerprint text not null check(fingerprint ~ '^[a-f0-9]{64}$'),
  bucket bigint not null,
  calls integer not null check(calls between 1 and 5000),
  primary key(scope,operation,fingerprint,bucket)
);
alter table public.restaurant_guest_gateway_limits enable row level security;
revoke all on public.restaurant_guest_gateway_limits from public,anon,authenticated;

create function public.restaurant_guest_rate_gate(
 p_source_hmac text,p_qr_hmac text,p_operation text
) returns boolean language plpgsql security definer set search_path=''
as $$
declare
 v_bucket bigint;
 v_current integer;
 v_scope text;
 v_key text;
 v_max integer;
begin
 if p_operation not in ('join','guest')
    or p_source_hmac is null or p_qr_hmac is null
    or p_source_hmac !~ '^[a-f0-9]{64}$'
    or p_qr_hmac !~ '^[a-f0-9]{64}$' then return false; end if;
 v_bucket:=floor(extract(epoch from now())/900)::bigint;
 -- Both rows are counted even for failed codes/credentials. A concurrent
 -- request is serialized on the same unique tuple, never overshoots.
 for v_scope,v_key,v_max in
   select 'qr',p_qr_hmac,case when p_operation='join' then 80 else 5000 end
   union all
   select 'source',p_source_hmac,case when p_operation='join' then 12 else 2000 end
 loop
  insert into public.restaurant_guest_gateway_limits(scope,operation,fingerprint,bucket,calls)
  values(v_scope,p_operation,v_key,v_bucket,1)
  on conflict(scope,operation,fingerprint,bucket) do update
   set calls=public.restaurant_guest_gateway_limits.calls+1
   where public.restaurant_guest_gateway_limits.calls<v_max
  returning calls into v_current;
  if not found then return false; end if;
 end loop;
 return true;
end; $$;
revoke all on function public.restaurant_guest_rate_gate(text,text,text)
 from public,anon,authenticated;
grant execute on function public.restaurant_guest_rate_gate(text,text,text)
 to service_role;

comment on table public.restaurant_guest_gateway_limits is
 'HMAC fingerprints only; cleanup old buckets periodically with restricted maintenance job.';
