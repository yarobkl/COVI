-- COVI préproduction : données ENTIÈREMENT FICTIVES (aucune donnée réelle).
-- Trois établissements de démonstration : boutique, restaurant, salon. Rejouable sans doublon.
-- Les comptes de connexion (e-mail + mot de passe) sont créés à part, jamais dans ce fichier.

-- Propriétaires fictifs ---------------------------------------------------------------------------
insert into auth.users(id) values
  ('00000000-0000-0000-0000-0000000000a1'),  -- boutique
  ('00000000-0000-0000-0000-0000000000b1'),  -- restaurant
  ('00000000-0000-0000-0000-00000000f001'),  -- salon
  ('00000000-0000-0000-0000-00000000f002')   -- coiffeur du salon
on conflict do nothing;

-- Boutique ---------------------------------------------------------------------------------------
insert into public.shops(id, owner_id, name, city, country, neighborhood, currency, business_kind)
values ('10000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a1',
        'Boutique Élégance (test)', 'Brazzaville', 'République du Congo', 'Poto-Poto', 'XAF', 'retail')
on conflict do nothing;

insert into public.products(id, shop_id, name, category, size, initial_sale_price, quantity_on_hand, is_unique_piece, status)
values
  ('20000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-0000000000a1', 'Robe pagne wax', 'Robes', 'M', 18000, 5, false, 'available'),
  ('20000000-0000-0000-0000-0000000000a2', '10000000-0000-0000-0000-0000000000a1', 'Chemise lin', 'Chemises', 'L', 12500, 8, false, 'available'),
  ('20000000-0000-0000-0000-0000000000a3', '10000000-0000-0000-0000-0000000000a1', 'Sac à main cuir', 'Accessoires', null, 32000, 1, true, 'available'),
  ('20000000-0000-0000-0000-0000000000a4', '10000000-0000-0000-0000-0000000000a1', 'Boubou brodé', 'Robes', 'XL', 45000, 2, false, 'available'),
  ('20000000-0000-0000-0000-0000000000a5', '10000000-0000-0000-0000-0000000000a1', 'Sandales tressées', 'Chaussures', '39', 9000, 10, false, 'available')
on conflict do nothing;

-- Deux ventes fictives par le propriétaire (passent par la vraie fonction de caisse).
do $$
begin
  if exists (select 1 from public.sales where shop_id = '10000000-0000-0000-0000-0000000000a1') then
    return;
  end if;
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
  perform public.record_cart_sale('10000000-0000-0000-0000-0000000000a1',
    '[{"product_id":"20000000-0000-0000-0000-0000000000a1","quantity":1,"sold_unit_price":18000},
      {"product_id":"20000000-0000-0000-0000-0000000000a2","quantity":2,"sold_unit_price":12000}]',
    'cash', 'a0000000-0000-0000-0000-000000000001');
  perform public.record_cart_sale('10000000-0000-0000-0000-0000000000a1',
    '[{"product_id":"20000000-0000-0000-0000-0000000000a5","quantity":1,"sold_unit_price":9000}]',
    'mobile_money', 'a0000000-0000-0000-0000-000000000002');
end $$;

-- Restaurant -------------------------------------------------------------------------------------
insert into public.shops(id, owner_id, name, city, country, neighborhood, currency, business_kind)
values ('10000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b1',
        'Le Maquis Bantou (test)', 'Brazzaville', 'République du Congo', 'Bacongo', 'XAF', 'restaurant')
on conflict do nothing;

insert into public.restaurant_tables(id, shop_id, label, zone, capacity, pos_x, pos_y)
select ('40000000-0000-0000-0000-0000000000b' || i)::uuid, '10000000-0000-0000-0000-0000000000b1',
       'T' || i, case when i <= 4 then 'Salle' else 'Terrasse' end,
       (array[2, 4, 4, 6, 4, 8])[i], (array[10, 40, 70, 10, 40, 70])[i], (array[15, 15, 15, 60, 60, 60])[i]
from generate_series(1, 6) i
on conflict do nothing;

insert into public.restaurant_menu_items(id, shop_id, name, category, kind, price_xaf, available, drink_stock)
values
  ('60000000-0000-0000-0000-0000000000b1', '10000000-0000-0000-0000-0000000000b1', 'Poulet DG', 'Plats', 'dish', 6500, true, null),
  ('60000000-0000-0000-0000-0000000000b2', '10000000-0000-0000-0000-0000000000b1', 'Poisson braisé', 'Plats', 'dish', 7000, true, null),
  ('60000000-0000-0000-0000-0000000000b3', '10000000-0000-0000-0000-0000000000b1', 'Saka-saka', 'Accompagnements', 'dish', 2000, true, null),
  ('60000000-0000-0000-0000-0000000000b4', '10000000-0000-0000-0000-0000000000b1', 'Primus 65 cl', 'Bières', 'drink', 1500, true, 24),
  ('60000000-0000-0000-0000-0000000000b5', '10000000-0000-0000-0000-0000000000b1', 'Jus de gingembre', 'Boissons', 'drink', 1000, true, 12)
on conflict do nothing;
