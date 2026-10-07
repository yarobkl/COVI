do $test$
declare
 u uuid:=gen_random_uuid(); stranger uuid:=gen_random_uuid(); shop uuid; shop_again uuid;
 china uuid; balloon uuid; india uuid; robe uuid; jean uuid; chemise uuid; article uuid;
 piece uuid; operation uuid; sale uuid; duplicate uuid; r record; j integer;
 total numeric; n integer; rejected boolean; report jsonb;
begin
 begin
  insert into auth.users(id) values(u),(stranger);
  perform set_config('request.jwt.claim.sub',u::text,true);
  execute 'set local role authenticated';
  select id into shop from public.create_my_shop('TEST COVI trois mois','Brazzaville','Congo','XAF');
  select id into shop_again from public.create_my_shop('TEST doublon','Brazzaville','Congo','XAF');
  if shop<>shop_again then raise exception 'FAIL shop persistence'; end if;
  insert into public.arrivals(shop_id,code,kind,origin_country,supplier_name,order_date,global_cost,status)
  values(shop,'TEST-CHN','supplier_order','Chine','Fournisseur fictif','2026-07-01',620000,'draft') returning id into china;
  update public.arrivals set status='ordered' where id=china;
  update public.arrivals set status='in_transit' where id=china;
  update public.arrivals set status='received',received_date='2026-07-05' where id=china;
  insert into public.arrivals(shop_id,code,kind,origin_country,global_cost,status,received_date)
  values(shop,'TEST-BAL','balloon','Congo',250000,'received','2026-07-18') returning id into balloon;
  insert into public.arrivals(shop_id,code,kind,origin_country,global_cost,status,received_date)
  values(shop,'TEST-IND','supplier_order','Inde',360000,'received','2026-08-15') returning id into india;
  insert into public.products(shop_id,arrival_id,name,category,initial_sale_price,quantity_on_hand)
  values(shop,china,'TEST Robe A','Robes',18000,20) returning id into robe;
  insert into public.products(shop_id,arrival_id,name,category,initial_sale_price,quantity_on_hand)
  values(shop,china,'TEST Jean B','Jeans',22000,15) returning id into jean;
  insert into public.products(shop_id,arrival_id,name,category,initial_sale_price,quantity_on_hand)
  values(shop,china,'TEST Chemise C','Chemises',12000,30) returning id into chemise;
  insert into public.products(shop_id,arrival_id,name,category,initial_sale_price,quantity_on_hand)
  values(shop,india,'TEST Article D','Vêtements',20000,40) returning id into article;
  for j in 1..50 loop
   insert into public.products(shop_id,arrival_id,name,category,initial_sale_price,quantity_on_hand,is_unique_piece)
   values(shop,balloon,'TEST Pièce ballon '||j,'Lot mixte',15000,1,true);
  end loop;
  for r in select * from (values
    (7,'robe',8,18000),(7,'jean',5,22000),(7,'chemise',10,12000),(7,'balloon',12,10000),
    (8,'robe',7,18000),(8,'jean',5,22000),(8,'chemise',10,12000),(8,'balloon',22,15000),(8,'article',15,20000),
    (9,'robe',5,18000),(9,'jean',4,22000),(9,'chemise',8,12000),(9,'balloon',12,15000),(9,'article',20,20000)
  ) as plan(month,product,qty,price) loop
   for j in 1..r.qty loop
    if r.product='balloon' then
     select id into piece from public.products where arrival_id=balloon and status='active' order by name limit 1;
    else piece:=case r.product when 'robe' then robe when 'jean' then jean when 'chemise' then chemise else article end; end if;
    operation:=gen_random_uuid();
    sale:=public.record_sale(shop,piece,1,r.price,(array['cash','mobile_money','card','bank_transfer','other'])[1+(j%5)],operation);
    duplicate:=public.record_sale(shop,piece,1,r.price,'cash',operation);
    if duplicate<>sale then raise exception 'FAIL idempotence'; end if;
    update public.sales set sold_at=make_date(2026,r.month,28)::timestamptz where id=sale;
   end loop;
  end loop;
  select sum(total_amount),count(*) into total,n from public.sales where shop_id=shop;
  if total<>2334000 or n<>143 then raise exception 'FAIL sales totals % %',total,n; end if;
  if (select count(*) from public.sale_items i join public.sales s on s.id=i.sale_id where s.shop_id=shop)<>143 then raise exception 'FAIL history'; end if;
  if (select sum(quantity_on_hand) from public.products where shop_id=shop)<>12 then raise exception 'FAIL remaining stock'; end if;
  if (select status from public.products where id=robe)<>'sold' then raise exception 'FAIL sold status'; end if;
  if (select sum(s.total_amount) from public.sales s join public.sale_items i on i.sale_id=s.id join public.products p on p.id=i.product_id where p.arrival_id=balloon)<>630000 then raise exception 'FAIL balloon profitability'; end if;
  rejected:=false; begin perform public.record_sale(shop,jean,2,22000,'cash',gen_random_uuid()); exception when others then rejected:=true; end;
  if not rejected then raise exception 'FAIL oversell'; end if;
  rejected:=false; begin perform public.record_sale(shop,jean,0,22000,'cash',gen_random_uuid()); exception when others then rejected:=true; end;
  if not rejected then raise exception 'FAIL zero quantity'; end if;
  rejected:=false; begin perform public.record_sale(shop,jean,1,-1,'cash',gen_random_uuid()); exception when others then rejected:=true; end;
  if not rejected then raise exception 'FAIL negative price'; end if;
  rejected:=false; begin perform public.record_sale(shop,jean,1,22000,'cash',null); exception when others then rejected:=true; end;
  if not rejected then raise exception 'FAIL missing operation'; end if;
  insert into public.shop_expenses(shop_id,category,label,amount,expense_date,recurring) values
   (shop,'Loyer','TEST juillet',110000,'2026-07-01',true),
   (shop,'Loyer','TEST août',130000,'2026-08-01',true),
   (shop,'Loyer','TEST septembre',140000,'2026-09-01',true);
  if (select sum(amount) from public.shop_expenses where shop_id=shop)<>380000 then raise exception 'FAIL expenses'; end if;
  if (select sum(global_cost) from public.arrivals where shop_id=shop)<>1230000 then raise exception 'FAIL arrival investment'; end if;
  if (select sum(total_amount) from public.sales where shop_id=shop and extract(month from sold_at)=7)<>494000 then raise exception 'FAIL July sales'; end if;
  if (select sum(total_amount) from public.sales where shop_id=shop and extract(month from sold_at)=8)<>986000 then raise exception 'FAIL August sales'; end if;
  if (select sum(total_amount) from public.sales where shop_id=shop and extract(month from sold_at)=9)<>854000 then raise exception 'FAIL September sales'; end if;
  if (select sum(total_amount) from public.sales where shop_id=shop)-(select sum(global_cost) from public.arrivals where shop_id=shop)-(select sum(amount) from public.shop_expenses where shop_id=shop)<>724000 then raise exception 'FAIL estimated result'; end if;
  insert into public.shop_expenses(shop_id,category,label,amount) values(shop,'Autre','TEST modification suppression',5000) returning id into operation;
  update public.shop_expenses set amount=6000 where id=operation;
  if (select amount from public.shop_expenses where id=operation)<>6000 then raise exception 'FAIL expense update'; end if;
  delete from public.shop_expenses where id=operation;
  if exists(select 1 from public.shop_expenses where id=operation) then raise exception 'FAIL expense deletion'; end if;
  select id into piece from public.products where arrival_id=balloon and status='active' limit 1;
  rejected:=false; begin perform public.record_sale(shop,piece,2,15000,'cash',gen_random_uuid()); exception when others then rejected:=true; end;
  if not rejected then raise exception 'FAIL unique quantity'; end if;
  update public.shops set name='TEST boutique renommée',city='Pointe-Noire' where id=shop;
  if (select name from public.shops where id=shop)<>'TEST boutique renommée' then raise exception 'FAIL settings'; end if;
  perform set_config('request.jwt.claim.sub',stranger::text,true);
  if exists(select 1 from public.products where shop_id=shop) or exists(select 1 from public.sales where shop_id=shop) then raise exception 'FAIL RLS isolation'; end if;
  rejected:=false; begin perform public.record_sale(shop,jean,1,22000,'cash',gen_random_uuid()); exception when others then rejected:=true; end;
  if not rejected then raise exception 'FAIL unauthorized sale'; end if;
  report:=jsonb_build_object('status','PASS','scope','live PostgreSQL and RLS; browser and OAuth not tested','months',3,'sales',143,'sale_lines',143,'revenue_xaf',2334000,'arrival_cost_xaf',1230000,'expenses_xaf',380000,'estimated_result_xaf',724000,'remaining_units',12,'balloon_sales_xaf',630000,'balloon_recovery_percent',252,'checks',jsonb_build_array('shop creation and recovery','arrival status lifecycle','supplier quantities','unique balloon pieces','5 payment methods','143 real RPC calls plus 143 idempotent retries','stock deductions','sold status and preserved history','oversell rejected','invalid quantity rejected','negative price rejected','missing idempotency key rejected','expenses','settings','RLS read isolation','unauthorized sale rejected'),'fixtures','rolled back');
  raise exception using errcode='P0999',message='ROLLBACK_TEST_FIXTURES';
 exception when sqlstate 'P0999' then null;
 end;
 perform set_config('covi.test_report',report::text,false);
end $test$;
select current_setting('covi.test_report')::jsonb as test_report;
