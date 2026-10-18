-- Country/ISO currency guardrails for newly created shops.
-- Runs only against the CI disposable database; no real money is moved.
\set ON_ERROR_STOP 1
begin;
-- Every shop needs its own owner: production has a UNIQUE(owner_id) constraint.
insert into auth.users(id)
select ('00000000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid
from generate_series(1,14) as n;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
set local role authenticated;

do $tests$
declare
  s public.shops;
  cases text[][] := array[
    array['République du Congo','XAF'],
    array['Gabon','XAF'],
    array['Côte d’Ivoire','XOF'],
    array['Sénégal','XOF'],
    array['Burkina Faso','XOF'],
    array['Mali','XOF'],
    array['Niger','XOF'],
    array['Ghana','GHS'],
    array['Nigeria','NGN'],
    array['Guinée','GNF'],
    array['Sierra Leone','SLE'],
    array['Angola','AOA'],
    array['São Tomé-et-Príncipe','STN'],
    array['République démocratique du Congo','CDF']
  ];
  currency_pair text[];
  account_number integer := 0;
begin
  foreach currency_pair slice 1 in array cases loop
    account_number := account_number + 1;
    perform set_config(
      'request.jwt.claim.sub',
      '00000000-0000-0000-0000-' || lpad(account_number::text,12,'0'),
      true
    );
    s := public.create_my_business_with_address(
      'COVI test establishment','Capitale',currency_pair[1],
      'Centre-ville','Quartier central','Avenue principale, derrière le marché',
      'retail',currency_pair[2]
    );
    if s.country is distinct from currency_pair[1]
       or s.currency is distinct from currency_pair[2] then
      raise exception 'Incorrect country-to-currency storage for %',currency_pair[1];
    end if;
    if currency_pair[1] = 'République démocratique du Congo' then
      if s.secondary_currency is distinct from 'USD' then
        raise exception 'Missing DRC secondary USD metadata';
      end if;
    elsif s.secondary_currency is not null then
      raise exception 'USD secondary currency leaked into another market';
    end if;
  end loop;

  begin
    perform public.create_my_business_with_address(
      'COVI test','Abidjan','Côte d’Ivoire','Cocody','Riviera',
      'Avenue du marché, proche pharmacie','retail','XAF'
    );
    raise exception 'XAF incorrectly accepted for Côte d’Ivoire';
  exception when raise_exception then
    if sqlerrm not like 'Currency is not valid for the selected country%' then raise; end if;
  end;

  begin
    perform public.create_my_business_with_address(
      'COVI test','Kinshasa','République démocratique du Congo','Gombe','Gombe',
      'Boulevard principal, près du marché','retail','USD'
    );
    raise exception 'USD incorrectly accepted as DRC official base currency';
  exception when raise_exception then
    if sqlerrm not like 'Currency is not valid for the selected country%' then raise; end if;
  end;

  begin
    perform public.create_my_business_with_address(
      'COVI test','Paris','France','Paris 1','Les Halles',
      'Rue Montorgueil, en face du marché','retail','EUR'
    );
    raise exception 'Unsupported country was accepted';
  exception when raise_exception then
    if sqlerrm not like 'Unsupported African market country%' then raise; end if;
  end;

  if (select count(*) from public.shops where owner_id=auth.uid()) <> 1 then
    raise exception 'Invalid operations persisted extra shop changes';
  end if;
end $tests$;
rollback;
