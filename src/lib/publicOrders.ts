import { supabase } from './supabase'
import { prepareManualOrderLines, type ManualOrderLineInput } from './manualOrder'
import { validateReferencePhotoDataUri } from './orderReferencePhoto'

const gatewayUrl = new URL(
  '/functions/v1/public-checkout',
  import.meta.env.VITE_SUPABASE_URL ?? 'https://bmbwmwgfzrijglzcgjut.supabase.co',
)

async function fetchGuestGateway(url: URL, options?: RequestInit): Promise<unknown> {
  let response: Response
  try {
    response = await fetch(url, { ...options, credentials: 'omit', cache: 'no-store' })
  } catch {
    throw new Error('Connexion impossible. Réessayez lorsque le réseau est disponible.')
  }
  const data: unknown = await response.json().catch(() => null)
  if (!response.ok) {
    const message =
      data && typeof data === 'object' && 'error' in data && typeof data.error === 'string'
        ? data.error
        : 'Service de commande indisponible.'
    throw new Error(message)
  }
  return data
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const MAX_PUBLIC_AMOUNT = 2_000_000_000
type RpcResponse = { data: unknown; error: { message: string } | null }
type FuturePublicRpc = {
  rpc: (
    name:
      | 'get_checkout_public_link'
      | 'configure_checkout_public_link'
      | 'rotate_checkout_public_link'
      | 'get_checkout_pending_orders',
    args: Record<string, unknown>,
  ) => PromiseLike<RpcResponse>
}

export type OrderChannel = 'qr' | 'social'
export type ProposedPaymentMethod = 'cash' | 'mobile_money' | 'other'
export type PublicOrderLink = { publicToken: string; enabled: boolean }
export type PublicCategory = { id: string; label: string }
export type PublicCatalog = { shopName: string; categories: PublicCategory[] }
export type PublicRequest = {
  token: string
  channel: OrderChannel
  operationId: string
  lines: readonly ManualOrderLineInput[]
  phone?: string
  note?: string
  fulfillment: 'pickup' | 'delivery'
  paymentMethod?: ProposedPaymentMethod
  deliveryAddress?: string
  referenceImage?: string
}
export type RecordedPublicRequest = {
  trackingToken: string
  orderId: string
  status: 'submitted' | 'approved' | 'paid' | 'cancelled' | 'expired' | 'reserved'
  amountXaf: number
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    throw new Error('Réponse du serveur invalide.')
  return value as Record<string, unknown>
}

function rpc(): FuturePublicRpc {
  // These server RPCs are still SQL drafts. No production code calls them
  // unless VITE_COVI_CATEGORY_CHECKOUT_ENABLED is explicitly enabled.
  return supabase as unknown as FuturePublicRpc
}

async function invoke(
  name: Parameters<FuturePublicRpc['rpc']>[0],
  args: Record<string, unknown>,
): Promise<unknown> {
  const { data, error } = await rpc().rpc(name, args)
  if (error) throw new Error(error.message)
  return data
}

export function parsePublicOrderLink(value: unknown): PublicOrderLink | null {
  if (value === null) return null
  const data = record(value)
  if (
    typeof data.publicToken !== 'string' ||
    !UUID.test(data.publicToken) ||
    typeof data.enabled !== 'boolean'
  )
    throw new Error('Lien public invalide.')
  return { publicToken: data.publicToken, enabled: data.enabled }
}

export async function getPublicOrderLink(shopId: string): Promise<PublicOrderLink | null> {
  if (!UUID.test(shopId)) throw new Error('Boutique invalide.')
  return parsePublicOrderLink(await invoke('get_checkout_public_link', { p_shop_id: shopId }))
}

export async function configurePublicOrderLink(
  shopId: string,
  enabled: boolean,
): Promise<PublicOrderLink> {
  if (!UUID.test(shopId) || typeof enabled !== 'boolean')
    throw new Error('Paramètres de lien invalides.')
  const result = parsePublicOrderLink(
    await invoke('configure_checkout_public_link', {
      p_shop_id: shopId,
      p_enabled: enabled,
    }),
  )
  if (!result || result.enabled !== enabled) throw new Error('Activation du lien non confirmée.')
  return result
}

export async function rotatePublicOrderLink(shopId: string): Promise<PublicOrderLink> {
  if (!UUID.test(shopId)) throw new Error('Boutique invalide.')
  const result = parsePublicOrderLink(
    await invoke('rotate_checkout_public_link', {
      p_shop_id: shopId,
    }),
  )
  if (!result) throw new Error('Nouveau lien non confirmé.')
  return result
}

export function publicOrderUrl(
  currentUrl: string,
  publicToken: string,
  channel: OrderChannel,
): string {
  if (!UUID.test(publicToken) || !['qr', 'social'].includes(channel))
    throw new Error('Lien de commande invalide.')
  const url = new URL(currentUrl)
  if (url.protocol !== 'https:' && url.hostname !== 'localhost')
    throw new Error('Les liens de commande exigent un site sécurisé.')
  // URL hash matches the Vite SPA's routing and needs no server rewrite.
  url.search = ''
  url.hash = '/commander/' + publicToken + '?via=' + channel
  return url.toString()
}

export function parsePublicCatalog(value: unknown): PublicCatalog {
  const data = record(value)
  if (typeof data.shopName !== 'string' || !data.shopName.trim() || !Array.isArray(data.categories))
    throw new Error('Catalogue public invalide.')
  const ids = new Set<string>()
  const categories: PublicCategory[] = []
  for (const item of data.categories) {
    const c = record(item)
    if (
      typeof c.id !== 'string' ||
      !UUID.test(c.id) ||
      typeof c.label !== 'string' ||
      !c.label.trim() ||
      ids.has(c.id)
    )
      throw new Error('Catégorie publique invalide.')
    ids.add(c.id)
    categories.push({ id: c.id, label: c.label.trim() })
  }
  return { shopName: data.shopName.trim(), categories }
}

export async function getPublicCatalog(token: string): Promise<PublicCatalog> {
  if (!UUID.test(token)) throw new Error('Lien public invalide.')
  const url = new URL(gatewayUrl)
  url.searchParams.set('token', token)
  return parsePublicCatalog(await fetchGuestGateway(url))
}

function invalidControl(value: string) {
  return [...value].some((c) => {
    const code = c.codePointAt(0)
    return code !== undefined && (code < 32 || code === 127)
  })
}

export function preparePublicRequest(input: PublicRequest) {
  if (
    !UUID.test(input.token) ||
    !UUID.test(input.operationId) ||
    !['qr', 'social'].includes(input.channel) ||
    !['pickup', 'delivery'].includes(input.fulfillment) ||
    !['cash', 'mobile_money', 'other'].includes(input.paymentMethod ?? 'cash')
  )
    throw new Error('Paramètres de commande invalides.')
  if (input.lines.length < 1 || input.lines.length > 20)
    throw new Error('La demande contient entre 1 et 20 lignes.')

  const prepared = prepareManualOrderLines(input.lines)
  if (
    prepared.lines.some(
      (l) => l.quantity > 20 || l.unitPriceXaf < 1 || l.unitPriceXaf > 999_999_999,
    ) ||
    prepared.amountXaf > MAX_PUBLIC_AMOUNT
  ) {
    throw new Error('Quantité ou prix public hors limite.')
  }

  const quantityByCategory = new Map<string, number>()
  for (const line of prepared.lines) {
    const sum = (quantityByCategory.get(line.categoryId) ?? 0) + line.quantity
    if (sum > 20) throw new Error('Maximum 20 pièces par catégorie.')
    quantityByCategory.set(line.categoryId, sum)
  }

  if (input.referenceImage) validateReferencePhotoDataUri(input.referenceImage)

  const phone = input.phone?.trim() || null
  const note = input.note?.trim() || null
  const address = input.deliveryAddress?.trim() || null
  if (
    (phone && (phone.length > 32 || invalidControl(phone))) ||
    (note && (note.length > 500 || invalidControl(note))) ||
    (address && (address.length > 240 || invalidControl(address))) ||
    (input.fulfillment === 'delivery' && (!phone || !address))
  )
    throw new Error('Téléphone requis pour la livraison, ou coordonnées invalides.')

  return {
    p_token: input.token,
    p_channel: input.channel,
    p_operation_id: input.operationId,
    p_lines: prepared.lines,
    p_customer_phone: phone,
    p_customer_note: note,
    p_fulfillment: input.fulfillment,
    p_payment_method: input.paymentMethod ?? 'cash',
    p_delivery_address: input.fulfillment === 'delivery' ? address : null,
  }
}

export function parseRecordedPublicRequest(value: unknown): RecordedPublicRequest {
  const row = record(value)
  if (
    typeof row.orderId !== 'string' ||
    !UUID.test(row.orderId) ||
    typeof row.trackingToken !== 'string' ||
    !UUID.test(row.trackingToken) ||
    !['submitted', 'approved', 'paid', 'cancelled', 'expired', 'reserved'].includes(
      String(row.status),
    ) ||
    !Number.isSafeInteger(row.amountXaf) ||
    (row.amountXaf as number) < 0 ||
    (row.amountXaf as number) > MAX_PUBLIC_AMOUNT
  )
    throw new Error('Réponse de commande invalide.')
  return {
    orderId: row.orderId,
    trackingToken: row.trackingToken,
    status: row.status as RecordedPublicRequest['status'],
    amountXaf: row.amountXaf as number,
  }
}

export async function submitPublicOrder(
  input: PublicRequest & { challenge: string },
): Promise<RecordedPublicRequest> {
  const args = preparePublicRequest(input)
  if (typeof input.challenge !== 'string' || input.challenge.length < 10)
    throw new Error('Terminez la vérification anti-robot avant de continuer.')
  return parseRecordedPublicRequest(
    await fetchGuestGateway(gatewayUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        token: input.token,
        channel: input.channel,
        operationId: input.operationId,
        lines: args.p_lines,
        phone: args.p_customer_phone,
        note: args.p_customer_note,
        fulfillment: input.fulfillment,
        paymentMethod: args.p_payment_method,
        deliveryAddress: args.p_delivery_address,
        referenceImage: input.referenceImage ?? null,
        challenge: input.challenge,
      }),
    }),
  )
}

export type PendingPublicOrder = {
  orderId: string
  channel: OrderChannel
  status: 'submitted' | 'approved'
  amountXaf: number
  customerPhone: string | null
  customerNote: string | null
  customerDeliveryAddress: string | null
  referenceImagePath: string | null
  fulfillment: 'pickup' | 'delivery'
  paymentMethod: ProposedPaymentMethod
  createdAt: string
  lines: Array<{ label: string; quantity: number; lineTotalXaf: number }>
}

export function parsePendingPublicOrders(value: unknown): PendingPublicOrder[] {
  if (!Array.isArray(value) || value.length > 30)
    throw new Error('Liste des commandes reçues invalide.')
  return value.map((item) => {
    const row = record(item)
    if (
      typeof row.orderId !== 'string' ||
      !UUID.test(row.orderId) ||
      (row.channel !== 'qr' && row.channel !== 'social') ||
      (row.status !== 'submitted' && row.status !== 'approved') ||
      !Number.isSafeInteger(row.amountXaf) ||
      (row.amountXaf as number) < 0 ||
      (row.amountXaf as number) > MAX_PUBLIC_AMOUNT ||
      (row.fulfillment !== 'pickup' && row.fulfillment !== 'delivery') ||
      !['cash', 'mobile_money', 'other'].includes(String(row.paymentMethod ?? 'cash')) ||
      typeof row.createdAt !== 'string' ||
      !Number.isFinite(Date.parse(row.createdAt)) ||
      (row.customerPhone !== null && typeof row.customerPhone !== 'string') ||
      (row.customerNote !== null && typeof row.customerNote !== 'string') ||
      (row.customerDeliveryAddress != null && typeof row.customerDeliveryAddress !== 'string') ||
      (row.referenceImagePath != null &&
        (typeof row.referenceImagePath !== 'string' ||
          !/^[0-9a-f-]{36}\/[0-9a-f-]{36}\/reference\.jpg$/.test(row.referenceImagePath))) ||
      !Array.isArray(row.lines) ||
      row.lines.length < 1
    )
      throw new Error('Une commande reçue est invalide.')

    const lines: PendingPublicOrder['lines'] = []
    let total = 0
    for (const item of row.lines) {
      const line = record(item)
      if (
        typeof line.label !== 'string' ||
        !line.label.trim() ||
        !Number.isSafeInteger(line.quantity) ||
        (line.quantity as number) <= 0 ||
        !Number.isSafeInteger(line.lineTotalXaf) ||
        (line.lineTotalXaf as number) < 0
      )
        throw new Error('Lignes de commande invalides.')
      total += line.lineTotalXaf as number
      if (!Number.isSafeInteger(total)) throw new Error('Total de demande invalide.')
      lines.push({
        label: line.label.trim(),
        quantity: line.quantity as number,
        lineTotalXaf: line.lineTotalXaf as number,
      })
    }
    if (total !== row.amountXaf) throw new Error('Montant de demande incohérent.')
    return {
      orderId: row.orderId,
      channel: row.channel as OrderChannel,
      status: row.status as PendingPublicOrder['status'],
      amountXaf: row.amountXaf as number,
      customerPhone: row.customerPhone as string | null,
      customerNote: row.customerNote as string | null,
      customerDeliveryAddress: (row.customerDeliveryAddress ?? null) as string | null,
      referenceImagePath: (row.referenceImagePath ?? null) as string | null,
      fulfillment: row.fulfillment as PendingPublicOrder['fulfillment'],
      paymentMethod: (row.paymentMethod ?? 'cash') as ProposedPaymentMethod,
      createdAt: row.createdAt,
      lines,
    }
  })
}

export async function getPendingPublicOrders(shopId: string): Promise<PendingPublicOrder[]> {
  if (!UUID.test(shopId)) throw new Error('Boutique invalide.')
  return parsePendingPublicOrders(
    await invoke('get_checkout_pending_orders', {
      p_shop_id: shopId,
    }),
  )
}

export type GuestCheckoutStatus = {
  shopName: string
  orderId: string
  status: RecordedPublicRequest['status']
  amountXaf: number
  receipt?: {
    receiptNumber: string
    confirmedAt: string
    cashierFirstName: string
    method: 'cash' | 'mobile_money' | 'other'
    amountXaf: number
    lines: { label: string; quantity: number; lineTotalXaf: number }[]
  }
}

/** This data is available only with the per-order random tracking capability.
 * A shop's permanent public QR token is NOT sufficient to read a receipt.
 */
export function parseGuestCheckoutStatus(value: unknown): GuestCheckoutStatus {
  const data = record(value)
  if (
    typeof data.shopName !== 'string' ||
    !data.shopName.trim() ||
    typeof data.orderId !== 'string' ||
    !UUID.test(data.orderId) ||
    !['submitted', 'approved', 'reserved', 'paid', 'cancelled', 'expired'].includes(
      String(data.status),
    ) ||
    !Number.isSafeInteger(data.amountXaf) ||
    (data.amountXaf as number) < 0 ||
    (data.amountXaf as number) > MAX_PUBLIC_AMOUNT
  )
    throw new Error('Suivi de commande invalide.')

  const response: GuestCheckoutStatus = {
    shopName: data.shopName.trim(),
    orderId: data.orderId,
    status: data.status as GuestCheckoutStatus['status'],
    amountXaf: data.amountXaf as number,
  }
  if (data.status !== 'paid') {
    if ('receipt' in data) throw new Error('Reçu non autorisé avant paiement.')
    return response
  }

  const receipt = record(data.receipt)
  if (
    typeof receipt.receiptNumber !== 'string' ||
    !receipt.receiptNumber ||
    typeof receipt.confirmedAt !== 'string' ||
    !Number.isFinite(Date.parse(receipt.confirmedAt)) ||
    typeof receipt.cashierFirstName !== 'string' ||
    !receipt.cashierFirstName ||
    !['cash', 'mobile_money', 'other'].includes(String(receipt.method)) ||
    receipt.amountXaf !== data.amountXaf ||
    !Array.isArray(receipt.lines) ||
    receipt.lines.length < 1 ||
    receipt.lines.length > 40
  )
    throw new Error('Reçu de paiement invalide.')

  const lines: NonNullable<GuestCheckoutStatus['receipt']>['lines'] = []
  let total = 0
  for (const item of receipt.lines) {
    const line = record(item)
    if (
      typeof line.label !== 'string' ||
      !line.label.trim() ||
      !Number.isSafeInteger(line.quantity) ||
      (line.quantity as number) < 1 ||
      !Number.isSafeInteger(line.lineTotalXaf) ||
      (line.lineTotalXaf as number) < 0
    )
      throw new Error('Lignes du reçu invalides.')
    total += line.lineTotalXaf as number
    if (!Number.isSafeInteger(total)) throw new Error('Somme du reçu invalide.')
    lines.push({
      label: line.label.trim(),
      quantity: line.quantity as number,
      lineTotalXaf: line.lineTotalXaf as number,
    })
  }
  if (total !== data.amountXaf) throw new Error('Total du reçu incohérent.')
  response.receipt = {
    receiptNumber: receipt.receiptNumber,
    confirmedAt: receipt.confirmedAt,
    cashierFirstName: receipt.cashierFirstName,
    method: receipt.method as NonNullable<GuestCheckoutStatus['receipt']>['method'],
    amountXaf: receipt.amountXaf as number,
    lines,
  }
  return response
}

export async function getGuestCheckoutStatus(trackingToken: string): Promise<GuestCheckoutStatus> {
  if (!UUID.test(trackingToken)) throw new Error('Lien de suivi invalide.')
  const url = new URL(gatewayUrl)
  url.searchParams.set('tracking', trackingToken)
  return parseGuestCheckoutStatus(await fetchGuestGateway(url))
}
