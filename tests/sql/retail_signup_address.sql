-- Retail PME safe onboarding: owner RLS, no XOF/Restaurant and compulsory address.
\set ON_ERROR_STOP 1
begin;
insert into auth.users(id) values ('00000000-0000-0000-0000-00000000ae21');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000ae21',true);
set local role authenticated;
do $tests$
declare v public.shops;
begin
  begin
    perform public.create_my_retail_shop_with_address(
      'Chez Marie', 'Brazzaville', 'République du Congo', 'Moungali', 'Moukondo',
      ''
    );
    raise exception 'Unexpected success with no address';
  exception when raise_exception then
    if sqlerrm not like 'A descriptive physical business address is required%' then raise; end if;
  end;
  begin
    perform public.create_my_retail_shop_with_address(
      'Chez Marie', 'Brazzaville', 'République du Congo', '', 'Moukondo',
      'Avenue de la Paix, près du marché'
    );
    raise exception 'Unexpected success with no arrondissement';
  exception when raise_exception then
    if sqlerrm not like 'Administrative area is required%' then raise; end if;
  end;
  begin
    perform public.create_my_retail_shop_with_address(
      'Chez Marie', 'Abidjan', 'Côte d’Ivoire', 'Cocody', 'Riviera',
      'Avenue du Marché, près de la place', 'XOF'
    );
    raise exception 'Unsupported market was accepted';
  exception when raise_exception then
    if sqlerrm not like 'Retail cash register currently supports CEMAC countries only%' then raise; end if;
  end;
  v := public.create_my_retail_shop_with_address(
    'Chez Marie', 'Brazzaville', 'République du Congo',
    'Moungali', 'Moukondo', 'Avenue de la Paix, près du marché'
  );
  if v.owner_id is distinct from auth.uid() or
     v.currency <> 'XAF' or
     v.administrative_area <> 'Moungali' or
     v.address_line <> 'Avenue de la Paix, près du marché'
  then raise exception 'Address was not saved correctly'; end if;
  begin
    perform public.create_my_retail_shop_with_address(
      'Second Shop', 'Brazzaville', 'République du Congo',
      'Moungali', 'Moukondo', 'Avenue du Marché, près de la place'
    );
    raise exception 'One-shop-per-owner guarantee failed';
  exception when unique_violation then null; end;
  if (select count(*) from public.shops where owner_id=auth.uid()) <> 1 then
    raise exception 'Unexpected shop rows';
  end if;
end $tests$;
rollback;
