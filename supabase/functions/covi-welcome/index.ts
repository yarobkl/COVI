import { createClient } from 'npm:@supabase/supabase-js@2.58.0'
import { dispatchWelcome } from './handler.mjs'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, x-client-info, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  })
}
const supabaseUrl = Deno.env.get('SUPABASE_URL')
const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
const resendKey = Deno.env.get('RESEND_API_KEY')
const sender = Deno.env.get('COVI_WELCOME_FROM')

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors })
  if (req.method !== 'POST') return json(405, { error: 'method-not-allowed' })
  const match = /^Bearer (\S+)$/i.exec(req.headers.get('authorization') ?? '')
  if (!match) return json(401, { error: 'unauthorized' })
  if (!supabaseUrl || !serviceRole || !resendKey || !sender)
    return json(503, { error: 'email-service-not-configured' })

  const admin = createClient(supabaseUrl, serviceRole, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  try {
    const result = await dispatchWelcome({
      token: match[1],
      getUser: async (jwt: string) => {
        const { data, error } = await admin.auth.getUser(jwt)
        return error ? null : data.user
      },
      sendMail: async (mail: { to: string[]; subject: string; text: string; html: string }, key: string) => {
        const response = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${resendKey}`,
            'Content-Type': 'application/json',
            'Idempotency-Key': key,
          },
          body: JSON.stringify({ ...mail, from: sender }),
          signal: AbortSignal.timeout(8_000),
        })
        if (!response.ok) return null
        const payload = await response.json()
        return payload && typeof payload.id === 'string' ? { id: payload.id } : null
      },
      markSent: async (user: { id: string; app_metadata?: Record<string, unknown> }, sentAt: string) => {
        const { error } = await admin.auth.admin.updateUserById(user.id, {
          app_metadata: { ...user.app_metadata, covi_welcome_email_sent_at: sentAt },
        })
        if (error) throw error
      },
    })
    return json(result.status, { status: result.reason })
  } catch {
    // The email provider and account store can fail independently. Stable
    // Idempotency-Key prevents duplicate delivery during a retry.
    return json(503, { error: 'email-delivery-unavailable' })
  }
})
