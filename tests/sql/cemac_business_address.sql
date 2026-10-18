-- PME registration: require a CEMAC country, commune, quartier and real address text
-- in the new validated RPC; existing rows and retail legacy remain unchanged.
\set ON_ERROR_STOP 1
begin;
insert into auth.users(id)
values ('00000000-0000-0000-0000-000000001b01');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000001b01', true);
set local role authenticated;
do $test$
declare
  shop public.shops;
begin
  begin
    perform public.create_my_business_with_address(
      'Chez Marie', 'Brazzaville', 'République du Congo', 'Moungali', 'Moukondo',
      '', 'restaurant'
    );
    raise exception 'Empty address was accepted';
  exception when raise_exception then
    if sqlerrm not like 'Physical business address is required%' then raise; end if;
  end;
  begin
    perform public.create_my_business_with_address(
      'Chez Marie', 'Brazzaville', 'République du Congo', '', 'Moukondo',
      'Avenue de la Paix, près du marché', 'restaurant'
    );
    raise exception 'Empty arrondissement was accepted';
  exception when raise_exception then
    if sqlerrm not like 'Arrondissement or commune is required%' then raise; end if;
  end;
  begin
    perform public.create_my_business_with_address(
      'Chez Marie', 'Marseille', 'France', '1er', 'Le Panier',
      'Rue de la République près du Vieux-Port', 'retail'
    );
    raise exception 'Non-CEMAC country was accepted';
  exception when raise_exception then
    if sqlerrm not like 'A supported CEMAC country is required%' then raise; end if;
  end;

  shop := public.create_my_business_with_address(
    'Chez Marie', 'Brazzaville', 'République du Congo',
    'Moungali', 'Moukondo', 'Avenue de la Paix, près du marché', 'restaurant'
  );
  if shop.owner_id <> auth.uid() or shop.name <> 'Chez Marie'
    or shop.business_kind <> 'restaurant'
    or shop.administrative_area <> 'Moungali'
    or shop.neighborhood <> 'Moukondo'
    or shop.address_line <> 'Avenue de la Paix, près du marché'
    or shop.currency <> 'XAF'
  then raise exception 'Persisted PME business address was incorrect'; end if;

  begin
    perform public.create_my_business_with_address(
      'Chez Marie', 'Brazzaville', 'République du Congo', 'Moungali',
      'Moukondo', 'Avenue de la Paix, près du marché', 'restaurant',
      'EUR'
    );
    raise exception 'Non-XAF currency was accepted';
  exception when raise_exception then
    if sqlerrm not like 'Only XAF is supported%' then raise; end if;
  end;
end $test$;
rollback;
