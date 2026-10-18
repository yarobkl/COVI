-- Integrity barrier for the multisector SaaS. A record can never be moved to another
-- shop_id (even another shop owned by the same entrepreneur).
-- Intentionally separated from RLS: database-level defense in depth.
create function public.prevent_sector_shop_reassignment()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  if new.shop_id is distinct from old.shop_id then
    raise exception 'shop_id of a business record is immutable' using errcode='23514';
  end if;
  return new;
end;
$$;
revoke all on function public.prevent_sector_shop_reassignment() from public,anon,authenticated;

create trigger immutable_shop_employee before update on public.employees
  for each row execute function public.prevent_sector_shop_reassignment();
create trigger immutable_shop_restaurant_table before update on public.restaurant_tables
  for each row execute function public.prevent_sector_shop_reassignment();
create trigger immutable_shop_restaurant_menu before update on public.restaurant_menu_items
  for each row execute function public.prevent_sector_shop_reassignment();
create trigger immutable_shop_salon_service before update on public.salon_services
  for each row execute function public.prevent_sector_shop_reassignment();
create trigger immutable_shop_salon_link before update on public.salon_booking_links
  for each row execute function public.prevent_sector_shop_reassignment();
create trigger immutable_shop_salon_request before update on public.salon_booking_requests
  for each row execute function public.prevent_sector_shop_reassignment();

-- QR tokens are durable printed identifiers, not editable catalogue fields.
create function public.prevent_sector_qr_reassignment()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  if new.qr_token is distinct from old.qr_token then
    raise exception 'Table QR token cannot be reassigned' using errcode='23514';
  end if;
  return new;
end;
$$;
revoke all on function public.prevent_sector_qr_reassignment() from public,anon,authenticated;

create trigger immutable_restaurant_qr before update on public.restaurant_tables
  for each row execute function public.prevent_sector_qr_reassignment();

create function public.prevent_salon_public_token_reassignment()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  if new.public_token is distinct from old.public_token then
    raise exception 'Salon booking link token cannot be reassigned' using errcode='23514';
  end if;
  return new;
end;
$$;
revoke all on function public.prevent_salon_public_token_reassignment() from public,anon,authenticated;
create trigger immutable_salon_qr before update on public.salon_booking_links
  for each row execute function public.prevent_salon_public_token_reassignment();
