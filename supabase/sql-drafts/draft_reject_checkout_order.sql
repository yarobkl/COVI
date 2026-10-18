-- COVI DRAFT ONLY: shop owner may reject a quote BEFORE payment.
-- Must be loaded after draft_checkout_manual_payment_schema.sql.
-- No inventory movement or financial entry is created by this function.
begin;

alter table public.checkout_orders
  add column if not exists rejected_by uuid references auth.users(id);
alter table public.checkout_orders
  add column if not exists rejected_at timestamptz;

create or replace function public.reject_checkout_order(
  p_shop_id uuid, p_order_id uuid
)
returns jsonb language plpgsql security definer set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_order public.checkout_orders%rowtype;
begin
  if v_actor is null then
    raise exception 'Authentification requise' using errcode = '28000';
  end if;
  if p_shop_id is null or p_order_id is null or (
    not exists (
      select 1 from public.shops s where s.id=p_shop_id and s.owner_id=v_actor
    ) and not exists (
      select 1 from public.checkout_cashiers c
      where c.shop_id=p_shop_id and c.user_id=v_actor and c.active=true
    )
  ) then
    raise exception 'Accès à cette boutique refusé' using errcode = '42501';
  end if;

  select * into v_order from public.checkout_orders o
  where o.id = p_order_id and o.shop_id = p_shop_id
  for update;
  if not found then raise exception 'Commande introuvable'; end if;

  -- Rejections are repeatable without creating a new event.
  if v_order.status = 'cancelled' and v_order.rejected_by = v_actor then
    return jsonb_build_object(
      'orderId', v_order.id, 'status', 'cancelled', 'amountXaf', v_order.amount_xaf
    );
  end if;
  if v_order.status not in ('submitted', 'approved') then
    raise exception 'Une commande encaissée, expirée ou clôturée ne peut pas être refusée';
  end if;
  if exists (select 1 from public.manual_payment_confirmations m
             where m.order_id = v_order.id and m.shop_id = p_shop_id) then
    raise exception 'Une commande déjà encaissée ne peut pas être refusée';
  end if;

  -- No reservations are performed in the current owner-only V1.
  update public.checkout_orders
  set status = 'cancelled', rejected_by = v_actor,
      rejected_at = clock_timestamp(), updated_at = clock_timestamp()
  where id = p_order_id and shop_id = p_shop_id;
  return jsonb_build_object(
    'orderId', v_order.id, 'status', 'cancelled', 'amountXaf', v_order.amount_xaf
  );
end;
$function$;

revoke all on function public.reject_checkout_order(uuid,uuid)
  from public, anon;
grant execute on function public.reject_checkout_order(uuid,uuid)
  to authenticated;
commit;
