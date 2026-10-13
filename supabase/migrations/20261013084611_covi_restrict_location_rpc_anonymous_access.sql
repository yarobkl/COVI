-- Supabase provisions an explicit anon function EXECUTE grant by default;
-- these account-creation RPCs are only for authenticated merchants.
revoke execute on function public.create_my_shop_with_neighborhood(
  text,text,text,text,text
) from anon;
revoke execute on function public.create_my_shop_with_location(
  text,text,text,text,text,double precision,double precision,double precision
) from anon;
