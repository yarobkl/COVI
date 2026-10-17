-- Salon slot security: PostgreSQL disposable test, always rollback.
\set ON_ERROR_STOP 1
begin;
insert into auth.users(id) values
 ('00000000-0000-0000-0000-0000000000e1'),
 ('00000000-0000-0000-0000-0000000000e2');
insert into public.shops(id,owner_id,name,business_kind) values
 ('10000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-0000000000e1','Salon E1','salon'),
 ('10000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-0000000000e2','Salon E2','salon');
insert into public.salon_services(id,shop_id,name,price_xaf,duration_minutes) values
 ('20000000-0000-0000-0000-0000000000e1','10000000-0000-0000-0000-0000000000e1','Tresses',15000,60);
insert into public.salon_booking_requests(id,shop_id,service_id,first_name,last_name,phone,requested_at) values
 ('30000000-0000-0000-0000-0000000000e1','10000000-0000-0000-0000-0000000000e1',
  '20000000-0000-0000-0000-0000000000e1','Ana','E1','+242061234567',now()+interval '1 day'),
 ('30000000-0000-0000-0000-0000000000e2','10000000-0000-0000-0000-0000000000e1',
  '20000000-0000-0000-0000-0000000000e1','Béa','E1','+242061234568',now()+interval '1 day 30 minutes'),
 ('30000000-0000-0000-0000-0000000000e3','10000000-0000-0000-0000-0000000000e1',
  '20000000-0000-0000-0000-0000000000e1','Céa','E1','+242061234569',now()+interval '1 day 1 hour');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000e1',true);
set local role authenticated;
do $tests$
declare s uuid:='10000000-0000-0000-0000-0000000000e1';
a uuid:='30000000-0000-0000-0000-0000000000e1';
b uuid:='30000000-0000-0000-0000-0000000000e2';
c uuid:='30000000-0000-0000-0000-0000000000e3';
begin
 if (select duration_minutes from public.salon_booking_requests where id=a)<>60 then
  raise exception 'Service duration not frozen on request'; end if;
 if public.salon_change_booking_status(s,a,'confirmed')<>'confirmed' then
  raise exception 'First slot not confirmed'; end if;
 begin
   perform public.salon_change_booking_status(s,b,'confirmed');
   raise exception 'Overlapping slot incorrectly confirmed';
 exception when raise_exception then
   if sqlerrm not like '%already confirmed%' then raise; end if;
 end;
 if public.salon_change_booking_status(s,c,'confirmed')<>'confirmed' then
  raise exception 'Adjacent booking at end should not overlap'; end if;
 if public.salon_change_booking_status(s,a,'cancelled')<>'cancelled' then
  raise exception 'Cancel should be accepted'; end if;
 if public.salon_change_booking_status(s,b,'confirmed')<>'confirmed' then
  raise exception 'Slot not free after cancellation'; end if;
 begin
   perform public.salon_change_booking_status(
     '10000000-0000-0000-0000-0000000000e2', b,'completed');
   raise exception 'Cross-salon status change accepted';
 exception when insufficient_privilege then null;
 end;
 begin
   update public.salon_booking_requests set status='completed' where id=b;
   raise exception 'Owner direct booking update accepted';
 exception when insufficient_privilege then null;
 end;
end $tests$;
rollback;
