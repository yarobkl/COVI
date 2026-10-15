-- Corrections de stock et archivage, faits par le propriétaire depuis « Modifier le produit ».
--
-- La quantité d'un produit reste interdite en écriture directe (droits par colonne) : elle ne bouge
-- que par une vente (record_sale / record_cart_sale) ou par adjust_product_stock ci-dessous, qui
-- exige un motif et laisse une trace dans stock_movements (+ journal de la boutique). Les ventes
-- ne sont jamais touchées.

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  reason text not null check (reason in ('restock', 'loss', 'theft', 'count_error')),
  quantity_before integer not null check (quantity_before >= 0),
  quantity_after integer not null check (quantity_after >= 0),
  note text check (note is null or char_length(note) <= 200),
  actor_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists stock_movements_shop_created_idx
  on public.stock_movements (shop_id, created_at desc);
create index if not exists stock_movements_product_idx
  on public.stock_movements (product_id, created_at desc);

alter table public.stock_movements enable row level security;
revoke all on public.stock_movements from anon, authenticated;
grant select on public.stock_movements to authenticated;
drop policy if exists stock_movements_owner_select on public.stock_movements;
create policy stock_movements_owner_select on public.stock_movements
  for select to authenticated
  using (exists (select 1 from public.shops s
                 where s.id = stock_movements.shop_id and s.owner_id = (select auth.uid())));

/**
 * Nouvelle quantité d'un produit, avec un motif : réassort, perte/casse, vol, erreur de comptage.
 * Une pièce unique reste à 0 ou 1. 0 → « épuisé » (sold) ; plus de 0 → de nouveau en vente,
 * sauf un produit archivé qui reste archivé.
 */
create or replace function public.adjust_product_stock(
  p_product_id uuid, p_quantity integer, p_reason text, p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_product public.products%rowtype;
  v_note text := nullif(pg_catalog.btrim(p_note), '');
  v_status text;
begin
  select * into v_product from public.products where id = p_product_id for update;
  if not found then raise exception 'Product not found' using errcode = '42501'; end if;
  perform public.assert_shop_owner(v_product.shop_id);
  if p_reason is null or p_reason not in ('restock', 'loss', 'theft', 'count_error') then
    raise exception 'Invalid stock reason';
  end if;
  if p_quantity is null or p_quantity < 0 or p_quantity > 100000 then
    raise exception 'Invalid stock quantity';
  end if;
  if v_product.is_unique_piece and p_quantity > 1 then
    raise exception 'Unique piece quantity must be 1';
  end if;
  if v_note is not null and (char_length(v_note) > 200 or v_note ~ '[[:cntrl:]]') then
    raise exception 'Invalid stock note';
  end if;
  if p_quantity = v_product.quantity_on_hand then
    raise exception 'Stock unchanged';
  end if;
  if p_reason = 'restock' and p_quantity < v_product.quantity_on_hand then
    raise exception 'Restock must increase stock';
  end if;
  if p_reason in ('loss', 'theft') and p_quantity > v_product.quantity_on_hand then
    raise exception 'Loss must decrease stock';
  end if;

  v_status := case
    when v_product.status = 'archived' then 'archived'
    when p_quantity = 0 then 'sold'
    else 'active'
  end;
  update public.products
  set quantity_on_hand = p_quantity, status = v_status
  where id = v_product.id;

  insert into public.stock_movements(shop_id, product_id, reason, quantity_before,
                                     quantity_after, note, actor_id)
  values (v_product.shop_id, v_product.id, p_reason, v_product.quantity_on_hand, p_quantity,
          v_note, auth.uid());
  perform public.shop_audit(v_product.shop_id, 'stock_adjusted', v_product.id::text,
    pg_catalog.jsonb_build_object('reason', p_reason, 'before', v_product.quantity_on_hand,
                                  'after', p_quantity));
  return pg_catalog.jsonb_build_object('id', v_product.id, 'quantity_on_hand', p_quantity,
                                       'status', v_status);
end;
$$;

/** Retire un produit de la vente (archivé) ou l'y remet ; le stock n'est pas modifié. */
create or replace function public.set_product_archived(p_product_id uuid, p_archived boolean)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_product public.products%rowtype;
  v_status text;
begin
  select * into v_product from public.products where id = p_product_id for update;
  if not found then raise exception 'Product not found' using errcode = '42501'; end if;
  perform public.assert_shop_owner(v_product.shop_id);
  if p_archived is null then raise exception 'Invalid archive flag'; end if;
  v_status := case
    when p_archived then 'archived'
    when v_product.quantity_on_hand = 0 then 'sold'
    else 'active'
  end;
  if v_status <> v_product.status then
    update public.products set status = v_status where id = v_product.id;
    perform public.shop_audit(v_product.shop_id,
      case when p_archived then 'product_archived' else 'product_unarchived' end,
      v_product.id::text, '{}'::jsonb);
  end if;
  return pg_catalog.jsonb_build_object('id', v_product.id, 'status', v_status);
end;
$$;

revoke all on function public.adjust_product_stock(uuid, integer, text, text) from public, anon;
revoke all on function public.set_product_archived(uuid, boolean) from public, anon;
grant execute on function public.adjust_product_stock(uuid, integer, text, text) to authenticated;
grant execute on function public.set_product_archived(uuid, boolean) to authenticated;
