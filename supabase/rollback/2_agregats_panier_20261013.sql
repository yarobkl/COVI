-- RETOUR ARRIÈRE n° 2 : agrégats et panier (20261013100100_shop_aggregates et
-- 20261013100200_record_cart_sale). À n'exécuter qu'APRÈS le n° 1 (1_caisse_20261014.sql).
-- N'EST PAS une migration. Testé par tests/sql/rollback.sql. Le front de main n'appelle aucune
-- de ces fonctions : ce retour arrière n'est utile qu'en cas de défaut dans l'une d'elles.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -1 -f supabase/rollback/2_agregats_panier_20261013.sql
--   puis : notify pgrst, 'reload schema';
--
-- Aucune donnée touchée : seulement des fonctions. Les index couvrants créés par
-- 20261013100100 (sales_shop_sold_cover_idx, sale_items_sale_cover_idx) sont GARDÉS : ils servent
-- les mêmes requêtes que les index qu'ils ont remplacés.

drop function if exists public.record_cart_sale(uuid, jsonb, text, uuid);
drop function if exists public.shop_dashboard(uuid, text, boolean, timestamptz);
drop function if exists public.shop_monthly_sales(uuid, integer, text, boolean, timestamptz);
drop function if exists public.arrival_profitability(uuid, boolean);
drop function if exists public.arrival_cost_allocation(uuid, boolean);
drop function if exists public.shop_estimated_profit(uuid, date, date, text, boolean);
