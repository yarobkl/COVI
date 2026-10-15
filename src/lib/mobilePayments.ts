// Paiement Mobile Money (MTN, Airtel) des commandes en ligne via OpenPay. La clé API OpenPay de la
// boutique est envoyée une fois au serveur (Supabase Vault) et n'est jamais relue ici. Les appels à
// OpenPay passent par la fonction Edge « openpay », avec la session de la boutique.
import { supabase, supabaseUrl } from './supabase'

export type MobileProvider = 'MTN' | 'AIRTEL'
export type MobilePaymentStatus =
  'requested' | 'pending' | 'success' | 'failed' | 'cancelled' | 'error'

export type OrderMobilePayment = {
  id: string
  orderId: string
  provider: MobileProvider
  phone: string
  amount: number
  status: MobilePaymentStatus
  reference: string | null
  message: string | null
  createdAt: string
}

export type OpenPaySettings = { configured: boolean; enabled: boolean; keyHint: string | null }

export const providerLabels: Record<MobileProvider, string> = {
  MTN: 'MTN MoMo',
  AIRTEL: 'Airtel Money',
}

export const mobileStatusLabels: Record<MobilePaymentStatus, string> = {
  requested: 'Demande en préparation',
  pending: 'En attente de validation par le client',
  success: 'Paiement reçu (confirmé par OpenPay)',
  failed: 'Paiement échoué',
  cancelled: 'Paiement annulé par le client',
  error: 'Demande refusée',
}

export const openPayUrl =
  import.meta.env.VITE_COVI_OPENPAY_URL || `${supabaseUrl}/functions/v1/openpay`

/** URL à coller dans le tableau de bord OpenPay de la boutique (onglet Callback URL). */
export const openPayCallbackUrl = `${openPayUrl}?action=callback`

/** Numéro congolais au format OpenPay (242 + 9 chiffres), ou null. */
export function normalizeCongoPhone(value: string): string | null {
  const digits = value.replace(/\D/g, '')
  if (/^242\d{9}$/.test(digits)) return digits
  if (/^0\d{8}$/.test(digits)) return '242' + digits
  return null
}

/** Opérateur probable d'après le préfixe (06 : MTN ; 05 ou 04 : Airtel). Toujours modifiable. */
export function guessProvider(phone: string): MobileProvider {
  const local = (normalizeCongoPhone(phone) ?? '').slice(3)
  return local.startsWith('05') || local.startsWith('04') ? 'AIRTEL' : 'MTN'
}

const db = supabase as unknown as {
  rpc: (
    name: string,
    args?: Record<string, unknown>,
  ) => PromiseLike<{ data: unknown; error: unknown }>
  from: (table: string) => {
    select: (columns: string) => {
      eq: (
        column: string,
        value: string,
      ) => {
        order: (
          column: string,
          options: { ascending: boolean },
        ) => {
          limit: (n: number) => PromiseLike<{ data: unknown; error: unknown }>
        }
      }
    }
  }
}

async function rpc<T>(request: PromiseLike<{ data: unknown; error: unknown }>): Promise<T> {
  const { data, error } = await request
  if (error) throw error
  return data as T
}

export const getOpenPaySettings = (shopId: string) =>
  rpc<OpenPaySettings>(db.rpc('get_shop_openpay', { p_shop_id: shopId }))

export const saveOpenPayKey = (shopId: string, apiKey: string) =>
  rpc<OpenPaySettings>(db.rpc('set_shop_openpay_key', { p_shop_id: shopId, p_api_key: apiKey }))

export const setOpenPayEnabled = (shopId: string, enabled: boolean) =>
  rpc<OpenPaySettings>(
    db.rpc('set_shop_openpay_enabled', { p_shop_id: shopId, p_enabled: enabled }),
  )

type PaymentRow = {
  id: string
  order_id: string
  provider: MobileProvider
  phone: string
  amount: number | string
  status: MobilePaymentStatus
  openpay_reference: string | null
  message: string | null
  created_at: string
}

/** Dernier paiement Mobile Money de chaque commande de la boutique. */
export async function listOrderPayments(shopId: string): Promise<Map<string, OrderMobilePayment>> {
  const rows = await rpc<PaymentRow[]>(
    db
      .from('public_order_payments')
      .select(
        'id, order_id, provider, phone, amount, status, openpay_reference, message, created_at',
      )
      .eq('shop_id', shopId)
      .order('created_at', { ascending: false })
      .limit(300),
  )
  const latest = new Map<string, OrderMobilePayment>()
  for (const r of rows ?? []) {
    if (latest.has(r.order_id)) continue
    latest.set(r.order_id, {
      id: r.id,
      orderId: r.order_id,
      provider: r.provider,
      phone: r.phone,
      amount: Number(r.amount),
      status: r.status,
      reference: r.openpay_reference,
      message: r.message,
      createdAt: r.created_at,
    })
  }
  return latest
}

async function callOpenPay(
  action: 'request' | 'refresh',
  body: Record<string, unknown>,
): Promise<{ paymentId: string; status: MobilePaymentStatus; reference: string | null }> {
  const { data } = await supabase.auth.getSession()
  const token = data.session?.access_token
  if (!token) throw new Error('Connectez-vous à la boutique.')
  let response: Response
  try {
    response = await fetch(`${openPayUrl}?action=${action}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
      body: JSON.stringify(body),
    })
  } catch {
    throw new Error('Pas de connexion. Réessayez quand le réseau revient.')
  }
  let answer: { error?: string } & Record<string, unknown>
  try {
    answer = await response.json()
  } catch {
    answer = {}
  }
  if (!response.ok) throw new Error(answer.error || 'OpenPay ne répond pas. Réessayez.')
  return answer as never
}

/** Envoie la demande de paiement au téléphone du client (il valide avec son code secret). */
export const requestMobilePayment = (input: {
  orderId: string
  provider: MobileProvider
  phone: string
  amount: number
}) => callOpenPay('request', input)

/** Relit le statut chez OpenPay. */
export const refreshMobilePayment = (paymentId: string) => callOpenPay('refresh', { paymentId })
