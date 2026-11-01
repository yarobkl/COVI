import { supabase } from './supabase'

/** Queue a WhatsApp event without blocking the checkout when the integration is not configured yet. */
export async function queueWhatsAppEvent(args: {
  shopId: string
  eventType: string
  idempotencyKey: string
  payload?: Record<string, unknown>
  templateName?: string
}) {
  const { error } = await supabase.functions.invoke('whatsapp-dispatch', {
    body: {
      shop_id: args.shopId,
      event_type: args.eventType,
      idempotency_key: args.idempotencyKey,
      payload: args.payload ?? {},
      template_name: args.templateName,
    },
  })
  // Notification delivery must never make a sale or order fail.
  return !error
}
