import webpush from 'npm:web-push@3.6.7'
import { createKitchenPushDispatcher } from './dispatcher.mjs'

// Disabled by default. Enable ONLY after VAPID secrets, cron bearer secret,
// staged migrations and tenant isolation have been verified.
const config = {
  enabled: Deno.env.get('COVI_KITCHEN_PUSH_ENABLED'),
  secret: Deno.env.get('COVI_KITCHEN_PUSH_DISPATCH_SECRET'),
  publicKey: Deno.env.get('COVI_KITCHEN_VAPID_PUBLIC_KEY'),
  privateKey: Deno.env.get('COVI_KITCHEN_VAPID_PRIVATE_KEY'),
  subject: Deno.env.get('COVI_KITCHEN_VAPID_SUBJECT'),
  serviceKey: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),
}
const base = Deno.env.get('SUPABASE_URL')
const rpc = async (name: string, args: Record<string, unknown>): Promise<unknown> => {
  if (!base || !config.serviceKey) throw Error('Database service not configured')
  const response = await fetch(base + '/rest/v1/rpc/' + name, {
    method: 'POST',
    headers: {
      'apikey': config.serviceKey,
      'authorization': 'Bearer ' + config.serviceKey,
      'content-type': 'application/json',
    },
    body: JSON.stringify(args),
  })
  if (!response.ok) throw Error('Kitchen push RPC unavailable')
  return response.json()
}
const sendPush = async (
  subscription: { endpoint: string; keys: { p256dh: string; auth: string } },
  payload: string,
): Promise<void> => {
  webpush.setVapidDetails(config.subject, config.publicKey, config.privateKey)
  await webpush.sendNotification(subscription, payload, { TTL: 120, urgency: 'high' })
}
Deno.serve(createKitchenPushDispatcher(config, { rpc, sendPush }))
