import { createStockApiHandler } from './handler.mjs'

// API privee : tout appel exige le JWT Supabase de l'utilisateur.
// SUPABASE_ANON_KEY sert a transmettre son identite, jamais de service_role.
// En production, verifier aussi les RLS et la publication realtime avant activation.
Deno.serve(createStockApiHandler({
  SUPABASE_URL: Deno.env.get('SUPABASE_URL'),
  SUPABASE_ANON_KEY: Deno.env.get('SUPABASE_ANON_KEY'),
  COVI_STOCK_API_ORIGINS: Deno.env.get('COVI_STOCK_API_ORIGINS')
}))
