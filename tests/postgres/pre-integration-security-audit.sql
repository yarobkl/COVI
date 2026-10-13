-- COVI PRE-INTEGRATION DEFENSE-IN-DEPTH: disposable covi_ci DB ONLY.
-- Verify actual PostgreSQL privileges and RLS flags rather than searching SQL text.
-- This is NOT a substitute for testing Supabase JWT / PostgREST / role ownership.
do $audit$
declare
  v_name text;
  v_schema text;
  v_rls boolean;
  v_call text;
begin
  foreach v_name in array array[
    'stock_categories',
    'stock_movements',
    'arrival_category_items',
    'arrival_stock_postings',
    'checkout_orders',
    'checkout_order_lines',
    'manual_payment_confirmations',
    'shop_receipt_counters',
    'checkout_public_links',
    'checkout_public_rate_windows',
    'checkout_cashiers',
    'checkout_cashier_invites',
    'checkout_cashier_secrets'
  ] loop
    select c.relrowsecurity into v_rls
      from pg_catalog.pg_class c
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = v_name;
    if v_rls is distinct from true then
      raise exception 'Missing RLS for public.%', v_name;
    end if;

    if pg_catalog.has_table_privilege('anon', 'public.' || v_name, 'INSERT')
      or pg_catalog.has_table_privilege('anon', 'public.' || v_name, 'UPDATE')
      or pg_catalog.has_table_privilege('anon', 'public.' || v_name, 'DELETE')
      or pg_catalog.has_table_privilege('authenticated', 'public.' || v_name, 'INSERT')
      or pg_catalog.has_table_privilege('authenticated', 'public.' || v_name, 'UPDATE')
      or pg_catalog.has_table_privilege('authenticated', 'public.' || v_name, 'DELETE')
    then
      raise exception 'Direct client-side mutation granted for public.%', v_name;
    end if;
  end loop;

  foreach v_call in array array[
    'public.create_manual_checkout_order(uuid,uuid,jsonb,boolean,text,text,text)',
    'public.approve_manual_checkout_order(uuid,uuid)',
    'public.reject_checkout_order(uuid,uuid)',
    'public.confirm_manual_checkout_payment(uuid,uuid,uuid,text,text,text,text)',
    'public.post_arrival_category_stock(uuid,uuid,uuid,jsonb)',
    'public.get_checkout_pending_orders(uuid)',
    'public.create_checkout_cashier_invite(uuid,text)',
    'public.redeem_checkout_cashier_invite(uuid)',
    'public.set_checkout_cashier_pin(uuid,text,text)',
    'public.list_checkout_cashiers(uuid)',
    'public.get_my_checkout_cashier_shops()',
    'public.set_checkout_cashier_active(uuid,uuid,boolean)',
    'public.configure_checkout_public_link(uuid,boolean)',
    'public.rotate_checkout_public_link(uuid)',
    'public.get_checkout_public_link(uuid)'
  ] loop
    if pg_catalog.has_function_privilege('anon', v_call, 'EXECUTE') then
      raise exception 'Guest has privileged RPC access: %', v_call;
    end if;
    if not pg_catalog.has_function_privilege('authenticated', v_call, 'EXECUTE') then
      raise exception 'Owner cannot call protected RPC: %', v_call;
    end if;
  end loop;

  -- The public link is NOT sufficient to send orders directly via PostgREST.
  -- Only a server gateway using service_role may call these two entrypoints.
  foreach v_call in array array[
    'public.get_checkout_public_catalog(uuid)',
    'public.submit_checkout_public_order(uuid,text,uuid,jsonb,text,text,text,text,text)'
  ] loop
    if pg_catalog.has_function_privilege('anon', v_call, 'EXECUTE')
      or pg_catalog.has_function_privilege('authenticated', v_call, 'EXECUTE') then
      raise exception 'Browser can bypass server gateway: %', v_call;
    end if;
    if not pg_catalog.has_function_privilege('service_role', v_call, 'EXECUTE') then
      raise exception 'Gateway role has no EXECUTE privilege: %', v_call;
    end if;
  end loop;

  -- Privileged mutations use carefully audited functions, with an empty
  -- search_path to prevent callers controlling their object resolution.
  foreach v_call in array array[
    'public.create_manual_checkout_order(uuid,uuid,jsonb,boolean,text,text,text)',
    'public.approve_manual_checkout_order(uuid,uuid)',
    'public.reject_checkout_order(uuid,uuid)',
    'public.confirm_manual_checkout_payment(uuid,uuid,uuid,text,text,text)',
    'public.post_arrival_category_stock(uuid,uuid,uuid,jsonb)',
    'public.submit_checkout_public_order(uuid,text,uuid,jsonb,text,text,text,text,text)'
  ] loop
    if not exists(
      select 1 from pg_catalog.pg_proc p
      where p.oid = pg_catalog.to_regprocedure(v_call)
        and p.prosecdef
        and exists (
          select 1
          from pg_catalog.unnest(coalesce(p.proconfig, array[]::text[])) as cfg(setting)
          where pg_catalog.split_part(cfg.setting, '=', 1) = 'search_path'
            -- PostgreSQL stores SET search_path = '' as search_path="".
            -- Both empty-string representations must be accepted, but never
            -- a nonempty schema or untrusted path.
            and pg_catalog.btrim(
              pg_catalog.substr(cfg.setting, pg_catalog.length('search_path=') + 1),
              pg_catalog.chr(34)
            ) = ''
        )
    ) then
      raise exception 'Unsafe SECURITY DEFINER/search_path setup: %', v_call;
    end if;
  end loop;
end;
$audit$;

select 'PASS: Client roles cannot mutate draft tables directly; sensitive RPCs reject anon; RLS enabled' as result;
