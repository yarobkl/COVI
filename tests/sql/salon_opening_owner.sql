-- A valid COVI PME Salon may open in XAF/CEMAC with an owner's physical address.
-- Never create a shop on missing street address or a non-XAF country.
\set ON_ERROR_STOP 1
begin;
insert into auth.users(id) values ('00000000-0000-0000-0000-00000000ae29');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000ae29',true);
set local role authenticated;
do $tests$
declare v public.shops;
begin
  begin
    perform public.create_my_salon_with_address(
      'Salon Élégance', 'Brazzaville', 'République du Congo',
      'Moungali', 'Moukondo', ''
    );
    raise exception 'Salon was incorrectly created without a physical address';
  exception when raise_exception then
    if sqlerrm not like 'A descriptive physical business address is required%' then raise; end if;
  end;
  begin
    perform public.create_my_salon_with_address(
      'Salon Élégance', 'Abidjan', 'Côte d’Ivoire',
      'Cocody', 'Riviera', 'Rue du Marché, à proximité du marché', 'XOF'
    );
    raise exception 'Non-XAF salon should have been blocked';
  exception when raise_exception then
    if sqlerrm not like 'Salon currently supports CEMAC countries only%' then raise; end if;
  end;
  v := public.create_my_salon_with_address(
      'Salon Élégance', 'Brazzaville', 'République du Congo',
      'Moungali', 'Moukondo', 'Rue Mayoko, près du marché'
    );
  if v.owner_id is distinct from auth.uid() or v.business_kind <> 'salon'
     or v.currency <> 'XAF' or v.address_line <> 'Rue Mayoko, près du marché'
     or v.administrative_area <> 'Moungali'
    then raise exception 'Incorrectly created salon with address'; end if;
  insert into public.salon_services(shop_id,name,price_xaf,duration_minutes)
    values(v.id,'Tresses',5000,60);
  if (select count(*) from public.salon_services where shop_id=v.id)<>1
    then raise exception 'Salon services not available after creation'; end if;
  insert into public.salon_booking_requests(shop_id,first_name,last_name,phone,requested_at)
    values(v.id,'Marie','Test','+242060000000',now()+interval '2 days');
  if (select count(*) from public.salon_booking_requests where shop_id=v.id)<>1
    then raise exception 'Owner cannot create appointment'; end if;
  begin
    perform public.create_my_salon_with_address(
      'Salon Secondaire', 'Brazzaville', 'République du Congo',
      'Moungali', 'Moukondo', 'Rue du Marché, juste en face du stade'
    );
    raise exception 'User managed to open duplicate salon';
  exception when unique_violation then null; end;
end $tests$;
rollback;
