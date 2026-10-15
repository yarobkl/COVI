import { createAccountPurgeHandler } from './handler.mjs'

// Purge nocturne des comptes supprimés depuis 30 jours (voir handler.mjs). Aucun secret ici :
// SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY sont fournis par Supabase ; l'appelant (pg_cron)
// prouve son droit avec le jeton gardé dans Vault (covi_account_purge_token).
Deno.serve(
  createAccountPurgeHandler({
    SUPABASE_URL: Deno.env.get('SUPABASE_URL'),
    SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  }),
)
