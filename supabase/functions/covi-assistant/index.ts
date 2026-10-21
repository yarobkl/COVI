import { createAssistantHandler } from './handler.mjs'

// Le secret Gemini doit vivre exclusivement dans Supabase Edge Secrets.
// La fonction est protégée par verify_jwt=true + authentification et contrôles propriétaire.
// Active si GEMINI_API_KEY est présente ; arrêt d'urgence via COVI_AI_ENABLED=false.
Deno.serve(
  createAssistantHandler({
    SUPABASE_URL: Deno.env.get('SUPABASE_URL'),
    SUPABASE_ANON_KEY:
      Deno.env.get('COVI_PUBLISHABLE_KEY') || Deno.env.get('SUPABASE_ANON_KEY'),
    GEMINI_API_KEY: Deno.env.get('GEMINI_API_KEY'),
    GEMINI_MODEL: Deno.env.get('GEMINI_MODEL') || 'gemini-2.5-flash',
    COVI_AI_ENABLED: Deno.env.get('COVI_AI_ENABLED'),
    COVI_AI_ALLOWED_ORIGINS:
      Deno.env.get('COVI_AI_ALLOWED_ORIGINS') || 'https://covi-snowy.vercel.app',
  }),
)
