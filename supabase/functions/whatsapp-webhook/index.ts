import { createWhatsAppWebhookHandler } from './handler.mjs'

Deno.serve(
  createWhatsAppWebhookHandler({
    env: {
      SUPABASE_URL: Deno.env.get('SUPABASE_URL'),
      SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      WHATSAPP_VERIFY_TOKEN: Deno.env.get('WHATSAPP_VERIFY_TOKEN') ?? '',
    },
  }),
)
