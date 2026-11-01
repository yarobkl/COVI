import { createWhatsAppSendHandler } from './handler.mjs'

Deno.serve(
  createWhatsAppSendHandler({
    env: {
      SUPABASE_URL: Deno.env.get('SUPABASE_URL'),
      SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      WHATSAPP_ACCESS_TOKEN: Deno.env.get('WHATSAPP_ACCESS_TOKEN') ?? '',
      WHATSAPP_GRAPH_VERSION: Deno.env.get('WHATSAPP_GRAPH_VERSION') ?? 'v23.0',
    },
  }),
)
