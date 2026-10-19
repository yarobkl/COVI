-- API Stock COVI : mise a jour optimiste et diffusion temps reel.
-- Ne pas modifier directement products.quantity_on_hand : conserver la RPC existante.
create or replace function public.adjust_product_stock_if_unchanged(
  p_product_id uuid,
  p_expected_quantity integer,
  p_quantity integer,
  p_reason text,
  p_note text default null
) returns jsonb
language plpgsql security definer set search_path to ''
as $$
declare
  v_current integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_expected_quantity is null or p_expected_quantity < 0 or p_expected_quantity > 100000 then
    raise exception 'Invalid expected quantity' using errcode = '22023';
  end if;
  -- Verifier la propriete AVANT de bloquer la ligne. Le verrou couvre la comparaison
  -- puis l'ecriture effectuee par adjust_product_stock, dans la meme transaction.
  select p.quantity_on_hand into v_current
    from public.products p
    join public.shops s on s.id = p.shop_id
   where p.id = p_product_id and s.owner_id = auth.uid()
   for update of p;
  if not found then
    raise exception 'Shop not found' using errcode = '42501';
  end if;
  if v_current <> p_expected_quantity then
    raise exception 'STOCK_CONFLICT' using errcode = 'P0001';
  end if;
  return public.adjust_product_stock(p_product_id, p_quantity, p_reason, p_note);
end;
$$;

revoke all on function public.adjust_product_stock_if_unchanged(uuid, integer, integer, text, text)
  from public, anon, authenticated;
grant execute on function public.adjust_product_stock_if_unchanged(uuid, integer, integer, text, text)
  to authenticated;

-- Supabase Postgres Changes respecte la RLS en lecture sur products.
-- Une table doit explicitement faire partie de la publication supabase_realtime.
do $$
begin
  if exists (select 1 from pg_catalog.pg_publication where pubname='supabase_realtime')
     and not exists (
       select 1 from pg_catalog.pg_publication_tables
        where pubname='supabase_realtime' and schemaname='public' and tablename='products'
     ) then
    alter publication supabase_realtime add table public.products;
  end if;
end;
$$;
