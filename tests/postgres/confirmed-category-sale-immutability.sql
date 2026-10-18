-- Disposable covi_ci ONLY. Checked-out category sales must be immutable,
-- while existing product-based sales remain writable until a separately
-- designed migration can safely harden legacy accounting.
begin;

-- Mirror current legacy permissions in this disposable fixture.
grant select, update, delete on public.sales to authenticated;
insert into public.sales (id, shop_id, payment_method, total_amount)
values ('f1111111-1111-4111-8111-111111111111',
        '11111111-1111-4111-8111-111111111111','cash',900);

select set_config('covi.test.confirmed_category_sale',
  (select sale_id::text from public.manual_payment_confirmations
   where shop_id='11111111-1111-4111-8111-111111111111'
   order by confirmed_at desc limit 1), true);

set local role authenticated;
select set_config('request.jwt.claim.sub',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);

do $tests$
declare
  v_sale_id uuid := current_setting('covi.test.confirmed_category_sale')::uuid;
  v_refused boolean := false;
begin
  if v_sale_id is null then raise exception 'Missing confirmed category sale'; end if;

  begin
    update public.sales set total_amount = total_amount + 5 where id = v_sale_id;
  exception when insufficient_privilege then v_refused := true;
  end;
  if not v_refused then
    raise exception 'Confirmed category sale amount was modified directly';
  end if;

  v_refused := false;
  begin
    delete from public.sales where id = v_sale_id;
  exception when insufficient_privilege then v_refused := true;
  end;
  if not v_refused then
    raise exception 'Confirmed category sale was deleted directly';
  end if;

  update public.sales set total_amount = 901
  where id = 'f1111111-1111-4111-8111-111111111111';
  if not found then raise exception 'Legacy sale editing unexpectedly blocked'; end if;
end;
$tests$;
rollback;

select 'PASS: Confirmed category sales immutable; legacy sale updates unaffected' as result;
