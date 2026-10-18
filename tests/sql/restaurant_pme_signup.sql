-- A valid COVI PME Restaurant may open in XAF/CEMAC with an owner's physical address.
-- Never create a shop on missing street address or a non-XAF country.
\set ON_ERROR_STOP 1
begin;
insert into auth.users(id) values ('00000000-0000-0000-0000-00000000ae22');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000ae22',true);
set local role authenticated;
do $tests$
declare v public.shops;
begin
  begin
    perform public.create_my_restaurant_with_address(
      'Chez Macaron Food', 'Brazzaville', 'République du Congo',
      'Moungali', 'Moukondo', ''
    );
    raise exception 'Restaurant was incorrectly created without a physical address';
  exception when raise_exception then
    if sqlerrm not like 'A descriptive physical business address is required%' then raise; end if;
  end;
  begin
    perform public.create_my_restaurant_with_address(
      'Chez Macaron Food', 'Abidjan', 'Côte d’Ivoire',
      'Cocody', 'Riviera', 'Rue du Marché, à proximité du marché', 'XOF'
    );
    raise exception 'Non-XAF restaurant should have been blocked';
  exception when raise_exception then
    if sqlerrm not like 'Restaurant cash register currently supports CEMAC countries only%' then raise; end if;
  end;
  v := public.create_my_restaurant_with_address(
      'Chez Macaron Food', 'Brazzaville', 'République du Congo',
      'Moungali', 'Moukondo', 'Rue Mayoko, près du marché'
    );
  if v.owner_id is distinct from auth.uid() or v.business_kind <> 'restaurant'
     or v.currency <> 'XAF' or v.address_line <> 'Rue Mayoko, près du marché'
     or v.administrative_area <> 'Moungali'
    then raise exception 'Incorrectly created restaurant with address'; end if;
  insert into public.restaurant_tables(shop_id,label,capacity)
    values(v.id,'Table 1',4);
  insert into public.restaurant_menu_items(shop_id,name,category,kind,price_xaf)
    values(v.id,'Poulet braisé','Plats','dish',7500);
  if (select count(*) from public.restaurant_tables where shop_id=v.id)<>1 or
     (select count(*) from public.restaurant_menu_items where shop_id=v.id)<>1
    then raise exception 'Restaurant cannot access its room or menu'; end if;
  begin
    perform public.create_my_restaurant_with_address(
      'Second Restaurant', 'Brazzaville', 'République du Congo',
      'Moungali', 'Moukondo', 'Rue du Marché, juste en face du stade'
    );
    raise exception 'User managed to open duplicate restaurant';
  exception when unique_violation then null; end;
end $tests$;
rollback;
