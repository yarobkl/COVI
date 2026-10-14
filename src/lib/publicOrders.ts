// Canal client COVI (QR code, liens WhatsApp / TikTok) : appels à la passerelle publique pour le
// client sans compte, et aux fonctions SQL de la boutique (migration 20261014230000).
//
// Le client ne parle qu'à la fonction Edge « public-checkout ». Le choix d'un moyen de règlement
// par le client n'est qu'une intention : seul un caissier, après vérification, confirme le
// règlement réellement reçu (confirm_public_order_payment), ce qui enregistre la vente.
import { supabase, supabaseUrl } from './supabase'

export type PaymentMethod = 'cash' | 'mobile_money' | 'card' | 'bank_transfer'
export type Fulfillment = 'pickup' | 'delivery'
export type OrderChannel = 'qr' | 'social'
export type OrderStatus = 'new' | 'accepted' | 'paid' | 'rejected'

export const paymentMethodLabels: Record<PaymentMethod, string> = {
  cash: 'Espèces',
  mobile_money: 'Mobile Money',
  card: 'Carte bancaire',
  bank_transfer: 'Virement bancaire',
}
export const paymentMethods = Object.keys(paymentMethodLabels) as PaymentMethod[]

export const statusLabels: Record<OrderStatus, string> = {
  new: 'Nouvelle demande',
  accepted: 'Acceptée — en attente du règlement',
  paid: 'Règlement confirmé — vente enregistrée',
  rejected: 'Refusée',
}

/** Clé publique Cloudflare Turnstile (publique par nature ; la clé secrète reste côté serveur). */
export const turnstileSiteKey =
  import.meta.env.VITE_COVI_TURNSTILE_SITE_KEY || '0x4AAAAAAFU8yQ48U2pGx18Z'

export const gatewayUrl =
  import.meta.env.VITE_COVI_PUBLIC_CHECKOUT_URL || `${supabaseUrl}/functions/v1/public-checkout`

// Adresses publiques ------------------------------------------------------------------------------
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/** Lien permanent de la boutique : #/commander/<jeton>?via=qr|social. */
export function orderLink(origin: string, token: string, via: OrderChannel): string {
  return `${origin}/#/commander/${token}?via=${via}`
}

export function trackingLink(origin: string, trackingToken: string): string {
  return `${origin}/#/suivi/${trackingToken}`
}

/** Page publique demandée par l'adresse, ou null pour l'application de la boutique. */
export function parsePublicHash(
  hash: string,
):
  | { kind: 'order'; token: string; channel: OrderChannel }
  | { kind: 'tracking'; trackingToken: string }
  | null {
  const order = /^#\/commander\/([0-9a-f-]{36})(?:\?via=(qr|social))?$/i.exec(hash)
  if (order && UUID.test(order[1]))
    return {
      kind: 'order',
      token: order[1].toLowerCase(),
      channel: order[2] === 'social' ? 'social' : 'qr',
    }
  const tracking = /^#\/suivi\/([0-9a-f-]{36})$/i.exec(hash)
  if (tracking && UUID.test(tracking[1]))
    return { kind: 'tracking', trackingToken: tracking[1].toLowerCase() }
  return null
}

// Passerelle publique (client sans compte) ------------------------------------------------------------
export type CatalogProduct = {
  id: string
  name: string
  category: string | null
  brand: string | null
  size: string | null
  priceXaf: number
  maxQuantity: number
}
export type PublicCatalog = {
  shopName: string
  city: string | null
  neighborhood: string | null
  message: string | null
  showCatalog: boolean
  /** Types sold by the boutique regardless of available inventory. */
  articleTypes?: string[]
  products: CatalogProduct[]
  ordersOpen: boolean
}

export type OrderLineInput =
  | { productId: string; quantity: number; proposedUnitPriceXaf?: number }
  | { description: string; quantity: number; proposedUnitPriceXaf?: number }

export type OrderRequest = {
  token: string
  operationId: string
  channel: OrderChannel
  customerName: string
  phone: string
  fulfillment: Fulfillment
  deliveryAddress?: string
  paymentMethod: PaymentMethod
  note?: string
  lines: OrderLineInput[]
  referenceImage?: string | null
  challenge: string
}

export type OrderReceipt = {
  receiptNumber: string
  confirmedAt: string
  method: PaymentMethod
  totalXaf: number
  cashierName: string | null
  lines: { label: string; quantity: number; unitPriceXaf: number }[]
}

export type PublicOrderStatus = {
  shopName: string
  reference: string
  status: OrderStatus
  createdAt: string
  fulfillment: Fulfillment
  paymentMethod: PaymentMethod
  amountXaf: number
  lines: { label: string; quantity: number; unitPriceXaf: number | null }[]
  rejectReason: string | null
  receipt: OrderReceipt | null
}

export class GatewayError extends Error {
  status: number
  constructor(message: string, status: number) {
    super(message)
    this.status = status
  }
}

async function gateway<T>(init: RequestInit & { query?: string }): Promise<T> {
  let response: Response
  try {
    response = await fetch(gatewayUrl + (init.query ?? ''), {
      method: init.method ?? 'GET',
      headers: init.body ? { 'content-type': 'application/json' } : undefined,
      body: init.body,
    })
  } catch {
    throw new GatewayError('Pas de connexion. Vérifiez internet et réessayez.', 0)
  }
  let data: unknown
  try {
    data = await response.json()
  } catch {
    data = null
  }
  if (!response.ok) {
    const message =
      data && typeof data === 'object' && typeof (data as { error?: unknown }).error === 'string'
        ? (data as { error: string }).error
        : 'Service momentanément indisponible. Réessayez.'
    throw new GatewayError(message, response.status)
  }
  return data as T
}

export const fetchCatalog = (token: string) =>
  gateway<PublicCatalog>({ query: `?token=${encodeURIComponent(token)}` }).then((c) => ({
    ...c,
    products: (c.products ?? []).map((p) => ({ ...p, priceXaf: Number(p.priceXaf) })),
  }))

export const submitOrder = (request: OrderRequest) =>
  gateway<{
    reference: string
    status: OrderStatus
    amountXaf: number
    trackingToken: string
    photoSaved: boolean | null
  }>({ method: 'POST', body: JSON.stringify(request) })

export const fetchOrderStatus = (trackingToken: string) =>
  gateway<PublicOrderStatus>({ query: `?tracking=${encodeURIComponent(trackingToken)}` })

/**
 * Photo de référence (capture de statut WhatsApp, live TikTok) : réduite dans le navigateur en
 * JPEG de 1 024 px au plus et 280 Ko au plus. Les métadonnées (position GPS…) disparaissent.
 */
export async function compressReferencePhoto(file: File): Promise<string> {
  if (!file.type.startsWith('image/')) throw new Error('Choisissez une image.')
  if (file.size > 15_000_000) throw new Error('Image trop lourde (15 Mo au plus).')
  const bitmap = await createImageBitmap(file)
  let side = 1024
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const scale = Math.min(1, side / Math.max(bitmap.width, bitmap.height))
    const canvas = document.createElement('canvas')
    canvas.width = Math.max(1, Math.round(bitmap.width * scale))
    canvas.height = Math.max(1, Math.round(bitmap.height * scale))
    const context = canvas.getContext('2d')
    if (!context) throw new Error('Image illisible.')
    context.drawImage(bitmap, 0, 0, canvas.width, canvas.height)
    const dataUrl = canvas.toDataURL('image/jpeg', 0.72)
    if (dataUrl.length * 0.75 < 280_000) return dataUrl
    side = Math.round(side * 0.75)
  }
  throw new Error('Image trop lourde.')
}

// Boutique : canal et commandes reçues ---------------------------------------------------------------
async function rpc<T>(request: PromiseLike<{ data: unknown; error: unknown }>): Promise<T> {
  const { data, error } = await request
  if (error) throw error
  return data as T
}

export type OrderChannelSettings = {
  token: string
  enabled: boolean
  showCatalog: boolean
  articleTypes?: string[]
  message: string | null
}

export type InboxLine = {
  id: string
  productId: string | null
  description: string | null
  productName: string | null
  quantity: number
  listedUnitPriceXaf: number | null
  proposedUnitPriceXaf: number | null
  currentPriceXaf: number | null
  availableQuantity: number | null
}

export type InboxOrder = {
  id: string
  reference: string
  status: OrderStatus
  channel: OrderChannel
  createdAt: string
  customerName: string
  customerPhone: string
  fulfillment: Fulfillment
  deliveryAddress: string | null
  paymentMethod: PaymentMethod
  note: string | null
  referenceImagePath: string | null
  requestedTotalXaf: number
  saleId: string | null
  paidMethod: PaymentMethod | null
  paymentReference: string | null
  confirmedAt: string | null
  cashierName: string | null
  rejectReason: string | null
  lines: InboxLine[]
}

// Les fonctions SQL ne figurent pas encore dans les types générés de la base.
const db = supabase as unknown as {
  rpc: (
    name: string,
    args?: Record<string, unknown>,
  ) => PromiseLike<{ data: unknown; error: unknown }>
}

export const getOrderChannel = (shopId: string) =>
  rpc<OrderChannelSettings | null>(db.rpc('get_public_order_channel', { p_shop_id: shopId }))

export const configureOrderChannel = (
  shopId: string,
  settings: { enabled: boolean; showCatalog: boolean; message: string | null },
) =>
  rpc<OrderChannelSettings>(
    db.rpc('configure_public_order_channel', {
      p_shop_id: shopId,
      p_enabled: settings.enabled,
      p_show_catalog: settings.showCatalog,
      p_message: settings.message,
    }),
  )

/** Edit what the shop usually sells, not its quantities or individual stock items. */
export const saveOrderArticleTypes = (shopId: string, types: string[]) =>
  rpc<OrderChannelSettings>(
    db.rpc('set_public_order_article_types', {
      p_shop_id: shopId,
      p_types: types,
    }),
  )

export const rotateOrderChannel = (shopId: string) =>
  rpc<OrderChannelSettings>(db.rpc('rotate_public_order_channel', { p_shop_id: shopId }))

const num = (x: unknown) => (x == null ? null : Number(x))

export const listOrders = (shopId: string, includeClosed = false) =>
  rpc<InboxOrder[]>(
    db.rpc('list_public_orders', { p_shop_id: shopId, p_include_closed: includeClosed }),
  ).then((orders) =>
    (orders ?? []).map((o) => ({
      ...o,
      requestedTotalXaf: Number(o.requestedTotalXaf ?? 0),
      lines: o.lines.map((l) => ({
        ...l,
        listedUnitPriceXaf: num(l.listedUnitPriceXaf),
        proposedUnitPriceXaf: num(l.proposedUnitPriceXaf),
        currentPriceXaf: num(l.currentPriceXaf),
        availableQuantity: num(l.availableQuantity),
      })),
    })),
  )

export const acceptOrder = (orderId: string) =>
  rpc<string>(db.rpc('accept_public_order', { p_order_id: orderId }))

export const rejectOrder = (orderId: string, reason: string) =>
  rpc<string>(db.rpc('reject_public_order', { p_order_id: orderId, p_reason: reason }))

export const confirmOrderPayment = (args: {
  orderId: string
  paidMethod: PaymentMethod
  paymentReference: string | null
  lines: { lineId: string; productId: string; unitPriceXaf: number }[]
  tillToken: string | null
}) =>
  rpc<{ status: 'paid'; saleId: string; alreadyConfirmed: boolean }>(
    db.rpc('confirm_public_order_payment', {
      p_order_id: args.orderId,
      p_paid_method: args.paidMethod,
      p_payment_reference: args.paymentReference,
      p_payment_verified: true,
      p_lines: args.lines,
      p_till_session: args.tillToken,
    }),
  )

/** Lien temporaire (5 minutes) vers la photo de référence, pour le propriétaire seulement. */
export async function referencePhotoUrl(path: string): Promise<string | null> {
  const { data, error } = await supabase.storage
    .from('covi-order-references')
    .createSignedUrl(path, 300)
  if (error || !data) return null
  return data.signedUrl
}

/** Message d'erreur de la base dans les mots de la boutique. */
export function orderErrorMessage(error: unknown): string {
  const message =
    error && typeof error === 'object' && 'message' in error
      ? String((error as { message: unknown }).message)
      : ''
  if (message.includes('Cashier PIN required') || message.includes('Till session invalid'))
    return 'Le code PIN d’un caissier est nécessaire pour encaisser.'
  if (message.includes('Price below allowed minimum'))
    return 'Prix inférieur à la remise maximale autorisée pour ce caissier.'
  if (message.includes('Insufficient stock'))
    return 'Stock insuffisant pour un article. Vérifiez le stock avant d’encaisser.'
  if (message.includes('Product unavailable'))
    return 'Un article n’est plus disponible (vendu ou archivé).'
  if (message.includes('Duplicate product in cart'))
    return 'Le même article apparaît deux fois : regroupez les lignes.'
  if (message.includes('Every order line must be confirmed'))
    return 'Choisissez l’article du stock pour chaque ligne.'
  if (message.includes('Order already closed')) return 'Cette commande est déjà clôturée.'
  if (message.includes('Cannot mix test and real products'))
    return 'Impossible de mélanger des articles de test et des articles réels.'
  return 'L’opération n’a pas abouti. Vérifiez la connexion et réessayez.'
}
