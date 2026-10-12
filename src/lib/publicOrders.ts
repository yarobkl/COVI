import { supabase } from './supabase'
import { prepareManualOrderLines, type ManualOrderLineInput } from './manualOrder'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const MAX_PUBLIC_AMOUNT = 2_000_000_000
type RpcResponse = { data: unknown; error: { message: string } | null }
type FuturePublicRpc = {
  rpc: (
    name: 'get_checkout_public_link' | 'configure_checkout_public_link' |
      'rotate_checkout_public_link' | 'get_checkout_public_catalog' |
      'submit_checkout_public_order',
    args: Record<string, unknown>
  ) => PromiseLike<RpcResponse>
}

export type OrderChannel = 'qr' | 'social'
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
}
export type RecordedPublicRequest = {
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
  if (typeof data.publicToken !== 'string' || !UUID.test(data.publicToken) ||
      typeof data.enabled !== 'boolean')
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
  const result = parsePublicOrderLink(await invoke('configure_checkout_public_link', {
    p_shop_id: shopId,
    p_enabled: enabled,
  }))
  if (!result || result.enabled !== enabled) throw new Error('Activation du lien non confirmée.')
  return result
}

export async function rotatePublicOrderLink(shopId: string): Promise<PublicOrderLink> {
  if (!UUID.test(shopId)) throw new Error('Boutique invalide.')
  const result = parsePublicOrderLink(await invoke('rotate_checkout_public_link', {
    p_shop_id: shopId,
  }))
  if (!result) throw new Error('Nouveau lien non confirmé.')
  return result
}

export function publicOrderUrl(
  currentUrl: string,
  publicToken: string,
  channel: OrderChannel,
): string {
  if (!UUID.test(publicToken) || !['qr','social'].includes(channel))
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
  if (typeof data.shopName !== 'string' || !data.shopName.trim() ||
      !Array.isArray(data.categories)) throw new Error('Catalogue public invalide.')
  const ids = new Set<string>()
  const categories: PublicCategory[] = []
  for (const item of data.categories) {
    const c = record(item)
    if (typeof c.id !== 'string' || !UUID.test(c.id) ||
        typeof c.label !== 'string' || !c.label.trim() || ids.has(c.id))
      throw new Error('Catégorie publique invalide.')
    ids.add(c.id)
    categories.push({ id: c.id, label: c.label.trim() })
  }
  return { shopName: data.shopName.trim(), categories }
}

export async function getPublicCatalog(token: string): Promise<PublicCatalog> {
  if (!UUID.test(token)) throw new Error('Lien public invalide.')
  return parsePublicCatalog(await invoke('get_checkout_public_catalog', {
    p_token: token,
  }))
}

function invalidControl(value: string) {
  return [...value].some(c => {
    const code = c.codePointAt(0)
    return code !== undefined && (code < 32 || code === 127)
  })
}

export function preparePublicRequest(input: PublicRequest) {
  if (!UUID.test(input.token) || !UUID.test(input.operationId) ||
      !['qr','social'].includes(input.channel) ||
      !['pickup','delivery'].includes(input.fulfillment))
    throw new Error('Paramètres de commande invalides.')
  if (input.lines.length < 1 || input.lines.length > 20)
    throw new Error('La demande contient entre 1 et 20 lignes.')

  const prepared = prepareManualOrderLines(input.lines)
  if (prepared.lines.some(l => l.quantity > 20 || l.unitPriceXaf < 1 ||
      l.unitPriceXaf > 999_999_999) ||
      prepared.amountXaf > MAX_PUBLIC_AMOUNT) {
    throw new Error('Quantité ou prix public hors limite.')
  }

  const quantityByCategory = new Map<string, number>()
  for (const line of prepared.lines) {
    const sum = (quantityByCategory.get(line.categoryId) ?? 0) + line.quantity
    if (sum > 20) throw new Error('Maximum 20 pièces par catégorie.')
    quantityByCategory.set(line.categoryId, sum)
  }

  const phone = input.phone?.trim() || null
  const note = input.note?.trim() || null
  if ((phone && (phone.length > 32 || invalidControl(phone))) ||
      (note && (note.length > 500 || invalidControl(note))) ||
      (input.fulfillment === 'delivery' && !phone))
    throw new Error('Téléphone requis pour la livraison, ou coordonnées invalides.')

  return {
    p_token: input.token,
    p_channel: input.channel,
    p_operation_id: input.operationId,
    p_lines: prepared.lines,
    p_customer_phone: phone,
    p_customer_note: note,
    p_fulfillment: input.fulfillment,
  }
}

export function parseRecordedPublicRequest(value: unknown): RecordedPublicRequest {
  const row = record(value)
  if (typeof row.orderId !== 'string' || !UUID.test(row.orderId) ||
      !['submitted','approved','paid','cancelled','expired','reserved'].includes(String(row.status)) ||
      !Number.isSafeInteger(row.amountXaf) ||
      (row.amountXaf as number) < 0 || (row.amountXaf as number) > MAX_PUBLIC_AMOUNT)
    throw new Error('Réponse de commande invalide.')
  return {
    orderId: row.orderId,
    status: row.status as RecordedPublicRequest['status'],
    amountXaf: row.amountXaf as number,
  }
}

export async function submitPublicOrder(input: PublicRequest): Promise<RecordedPublicRequest> {
  const args = preparePublicRequest(input)
  return parseRecordedPublicRequest(await invoke('submit_checkout_public_order', args))
}
