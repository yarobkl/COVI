-- Shop-wide types offered to customers even at quantity 0, independent of stock.
\set ON_ERROR_STOP 1
begin;
create function pg_temp.check(p_ok boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_ok is not true then raise exception 'FAIL %',p_label; end if;
  raise notice 'ok %',p_label;
end $$;
create function pg_temp.fails(p_statement text,p_label text) returns void
language plpgsql as $$
begin
  begin execute p_statement;
  exception when others then
    raise notice 'ok % [%]',p_label,sqlerrm; return;
  end;
  raise exception 'FAIL %',p_label;
end $$;
\set shop '10000000-0000-0000-0000-0000000000c1'
\set owner '00000000-0000-0000-0000-0000000000c1'
\set intruder '00000000-0000-0000-0000-0000000000c2'
insert into auth.users(id) values (:'owner'),(:'intruder');
insert into public.shops(id,owner_id,name) values (:'shop',:'owner','Boutique sans stock');

set local role authenticated;
select set_config('request.jwt.claim.sub',:'owner',true);
select (public.configure_public_order_channel(:'shop',true,true,null))->>'token' as token \gset
select pg_temp.check(
  (public.get_public_order_channel(:'shop')->'articleTypes') ? 'Pantalon'
  and (public.get_public_order_channel(:'shop')->'articleTypes') ? 'Chemise',
  'Assortiment par défaut, même sans stock');
-- Under ordinary authentication the table remains private.
select pg_temp.check(not has_table_privilege('authenticated','public.public_order_channels','select'),
  'La table de configuration n’est pas directement lisible');
select pg_temp.check(public.get_public_order_channel(:'shop')->'articleTypes' ? 'Pantalon',
  'Le propriétaire voit son assortiment');
select set_config('request.jwt.claim.sub',:'intruder',true);
select pg_temp.fails(format('select public.set_public_order_article_types(%L,ARRAY[''Boubou''])',:'shop'),
  'Impossible de modifier le catalogue d’une autre boutique');
select set_config('request.jwt.claim.sub',:'owner',true);
select public.set_public_order_article_types(:'shop',ARRAY['Chemise','Pantalon','Boubou','Pantalon']);
select pg_temp.check(
  (public.get_public_order_channel(:'shop')->'articleTypes')::jsonb
    ='["Chemise","Pantalon","Boubou"]'::jsonb,
  'Liste éditable, doublons supprimés');
select pg_temp.fails(format('select public.set_public_order_article_types(%L,ARRAY[]::text[])',:'shop'),
  'Liste vide refusée');
reset role;

set local role service_role;
select pg_temp.check(
  (public.get_public_order_catalog(:'token')->'articleTypes')::jsonb
     ='["Chemise","Pantalon","Boubou"]'::jsonb,
  'Page client : chemise et pantalon restent visibles sans stock');
select pg_temp.check(
  jsonb_array_length(public.get_public_order_catalog(:'token')->'products')=0,
  'Aucune référence de stock inventée');
select pg_temp.check(
  public.get_public_order_catalog(gen_random_uuid()) is null,
  'Un jeton inconnu ne révèle aucun type de boutique');
reset role;
rollback;
