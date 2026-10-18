-- DRAFT ONLY: guard financial rows created by the category checkout.
-- This is NOT a production migration. Review on an isolated Supabase environment.
-- Depends on draft_checkout_manual_payment_schema.sql.
-- Unlike revoking UPDATE/DELETE on all sales, this does not interrupt existing
-- product-based sales or the offline synchronization workflow.
begin;

create or replace function public.covi_protect_confirmed_category_sale()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  -- A validated receipt is a financial ledger event, not an editable cart.
  -- Correction must eventually use a separate audited compensating event.
  if exists (
    select 1 from public.manual_payment_confirmations m
    where m.sale_id = old.id and m.shop_id = old.shop_id
  ) then
    raise exception 'Vente encaissée : modification directe interdite'
      using errcode = '42501';
  end if;
  return old;
end;
$function$;

revoke all on function public.covi_protect_confirmed_category_sale()
  from public, anon, authenticated;

drop trigger if exists covi_protect_confirmed_category_sale on public.sales;
create trigger covi_protect_confirmed_category_sale
before update or delete on public.sales
for each row execute function public.covi_protect_confirmed_category_sale();

commit;
