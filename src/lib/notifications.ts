// Cloche de la boutique : ce qui mérite l'attention du propriétaire à l'ouverture (commandes à
// traiter, stock bas, codes PIN ratés, ventes de test, anomalies). Tout est relu dans la base avec
// la session du propriétaire (RLS) ; seule la date de dernière lecture reste sur ce téléphone.
import type { PageId } from '../app/routes'
import { listOrders, type InboxOrder } from './publicOrders'
import { supabase } from './supabase'
import { money, plural } from './format'

export type NotificationKind = 'order' | 'stock' | 'pin' | 'test' | 'anomaly'

export type ShopNotification = {
  /** Stable : la même alerte garde le même id d'une ouverture à l'autre. */
  id: string
  kind: NotificationKind
  title: string
  detail: string
  /** Date de l'événement (ISO), pour l'ordre et le « non lu ». */
  at: string
  page: PageId
}

export type NotificationSources = {
  orders: Pick<
    InboxOrder,
    'id' | 'reference' | 'status' | 'createdAt' | 'customerName' | 'requestedTotalXaf'
  >[]
  products: {
    id: string
    name: string
    status: string
    quantity_on_hand: number
    is_unique_piece: boolean
    is_test: boolean
    updated_at: string
  }[]
  testSales: { id: string; sold_at: string; total_amount: number | string }[]
  audit: { id: number; action: string; at: string }[]
  /** Corrections de stock faites dans « Modifier le produit » (facultatif). */
  movements?: {
    id: string
    product_id: string
    reason: string
    quantity_before: number
    quantity_after: number
    created_at: string
  }[]
}

const DAY = 24 * 60 * 60 * 1000
/** Fenêtre des événements passés (PIN ratés, ventes de test, ruptures). */
export const WINDOW_DAYS = 7
/** Seuil du « stock bas » pour les articles en plusieurs exemplaires. */
export const LOW_STOCK = 2

const timeOf = (iso: string) => new Date(iso).getTime()

/** Les alertes, la plus récente d'abord. Fonction pure : testée sans réseau. */
export function buildNotifications(src: NotificationSources, now = Date.now()): ShopNotification[] {
  const out: ShopNotification[] = []
  const since = now - WINDOW_DAYS * DAY

  for (const o of src.orders) {
    if (o.status === 'new') {
      out.push({
        id: `order-new-${o.id}`,
        kind: 'order',
        title: `Nouvelle commande ${o.reference}`,
        detail: `${o.customerName} · ${money(o.requestedTotalXaf)}`,
        at: o.createdAt,
        page: 'commandes',
      })
    } else if (o.status === 'accepted' && now - timeOf(o.createdAt) > DAY) {
      out.push({
        id: `order-wait-${o.id}`,
        kind: 'anomaly',
        title: `Commande ${o.reference} pas encore encaissée`,
        detail: `Acceptée, en attente du règlement depuis plus de 24 h · ${o.customerName}`,
        at: o.createdAt,
        page: 'commandes',
      })
    }
  }

  for (const p of src.products) {
    if (p.is_unique_piece) continue
    if (p.status === 'active' && p.quantity_on_hand > 0 && p.quantity_on_hand <= LOW_STOCK) {
      out.push({
        id: `stock-low-${p.id}-${p.quantity_on_hand}`,
        kind: 'stock',
        title: `Stock bas : ${p.name}`,
        detail: `Plus que ${plural(p.quantity_on_hand, 'exemplaire')}.`,
        at: p.updated_at,
        page: 'stock',
      })
    } else if (p.status === 'sold' && timeOf(p.updated_at) >= since) {
      out.push({
        id: `stock-out-${p.id}`,
        kind: 'stock',
        title: `Épuisé : ${p.name}`,
        detail: 'Tous les exemplaires sont vendus.',
        at: p.updated_at,
        page: 'stock',
      })
    }
  }

  const testInStock = src.products.filter((p) => p.is_test && p.status === 'active')
  if (testInStock.length > 0) {
    const latest = testInStock.reduce((a, b) => (a.updated_at > b.updated_at ? a : b))
    out.push({
      id: `stock-test-${testInStock.length}-${latest.updated_at}`,
      kind: 'anomaly',
      title: `${plural(testInStock.length, 'article')} TEST dans le stock`,
      detail: 'Ils apparaissent quand vous encaissez une commande : retirez-les du stock réel.',
      at: latest.updated_at,
      page: 'stock',
    })
  }

  for (const s of src.testSales) {
    if (timeOf(s.sold_at) < since) continue
    out.push({
      id: `sale-test-${s.id}`,
      kind: 'test',
      title: 'Vente de test enregistrée',
      detail: `${money(Number(s.total_amount))} · non comptée dans le chiffre réel.`,
      at: s.sold_at,
      page: 'ventes',
    })
  }

  // PIN ratés : regroupés par jour pour ne pas noyer la liste.
  const pinDays = new Map<string, { count: number; at: string; firstId: number }>()
  // Corrections de stock : pertes, vols et erreurs de comptage (un réassort n'alerte pas).
  const names = new Map(src.products.map((p) => [p.id, p.name]))
  const reasonTitle: Record<string, [NotificationKind, string]> = {
    loss: ['stock', 'Perte déclarée'],
    theft: ['anomaly', 'Vol déclaré'],
    count_error: ['stock', 'Stock corrigé'],
  }
  for (const m of src.movements ?? []) {
    const reason = reasonTitle[m.reason]
    if (!reason || timeOf(m.created_at) < since) continue
    out.push({
      id: `move-${m.id}`,
      kind: reason[0],
      title: `${reason[1]} : ${names.get(m.product_id) ?? 'un produit'}`,
      detail: `Stock passé de ${m.quantity_before} à ${m.quantity_after}.`,
      at: m.created_at,
      page: 'stock',
    })
  }

  for (const a of src.audit) {
    if (!a.action.endsWith('pin_failed') || timeOf(a.at) < since) continue
    const day = a.at.slice(0, 10)
    const cur = pinDays.get(day)
    if (!cur) pinDays.set(day, { count: 1, at: a.at, firstId: a.id })
    else {
      cur.count += 1
      if (a.at > cur.at) cur.at = a.at
      cur.firstId = Math.min(cur.firstId, a.id)
    }
  }
  for (const [day, d] of pinDays) {
    out.push({
      id: `pin-${day}-${d.firstId}-${d.count}`,
      kind: 'pin',
      title: d.count > 1 ? `${d.count} codes PIN ratés` : 'Code PIN raté',
      detail:
        'Quelqu’un a tapé un mauvais code à la caisse. Vérifiez si c’était vous ou un caissier.',
      at: d.at,
      page: 'boutique',
    })
  }

  return out.sort((a, b) => timeOf(b.at) - timeOf(a.at))
}

// Les colonnes récentes (is_test, operation_reference…) ne figurent pas toutes dans les types
// générés de la base.
const db = supabase as unknown as {
  from: (table: string) => {
    select: (columns: string) => QueryChain
  }
}
type QueryChain = PromiseLike<{ data: unknown; error: unknown }> & {
  eq: (column: string, value: unknown) => QueryChain
  in: (column: string, values: unknown[]) => QueryChain
  gte: (column: string, value: unknown) => QueryChain
  order: (column: string, options: { ascending: boolean }) => QueryChain
  limit: (n: number) => QueryChain
}

async function rows<T>(query: QueryChain): Promise<T[]> {
  const { data, error } = await query
  if (error) throw error
  return (data ?? []) as T[]
}

/** Relit tout ce qu'il faut pour la cloche (propriétaire de la boutique). */
export async function loadNotifications(shopId: string): Promise<ShopNotification[]> {
  const since = new Date(Date.now() - WINDOW_DAYS * DAY).toISOString()
  const [orders, products, testSales, audit, movements] = await Promise.all([
    listOrders(shopId, false),
    rows<NotificationSources['products'][number]>(
      db
        .from('products')
        .select('id, name, status, quantity_on_hand, is_unique_piece, is_test, updated_at')
        .eq('shop_id', shopId)
        .in('status', ['active', 'sold'])
        .limit(2000),
    ),
    rows<NotificationSources['testSales'][number]>(
      db
        .from('sales')
        .select('id, sold_at, total_amount')
        .eq('shop_id', shopId)
        .eq('is_test', true)
        .gte('sold_at', since)
        .order('sold_at', { ascending: false })
        .limit(50),
    ),
    rows<NotificationSources['audit'][number]>(
      db
        .from('shop_audit_log')
        .select('id, action, at')
        .eq('shop_id', shopId)
        .gte('at', since)
        .order('at', { ascending: false })
        .limit(500),
    ),
    // Absente tant que la migration des corrections de stock n'est pas passée : on l'ignore.
    rows<NonNullable<NotificationSources['movements']>[number]>(
      db
        .from('stock_movements')
        .select('id, product_id, reason, quantity_before, quantity_after, created_at')
        .eq('shop_id', shopId)
        .gte('created_at', since)
        .order('created_at', { ascending: false })
        .limit(100),
    ).catch(() => []),
  ])
  return buildNotifications({ orders, products, testSales, audit, movements })
}

const seenKey = (shopId: string) => `covi:notifications-seen:${shopId}`

/** Ids déjà vus sur ce téléphone (simple confort : vide si le stockage est indisponible). */
export function readSeen(shopId: string): Set<string> {
  try {
    const raw = localStorage.getItem(seenKey(shopId))
    const ids: unknown = raw ? JSON.parse(raw) : []
    return new Set(Array.isArray(ids) ? ids.filter((x) => typeof x === 'string') : [])
  } catch {
    return new Set()
  }
}

export function markSeen(shopId: string, ids: string[]) {
  try {
    localStorage.setItem(seenKey(shopId), JSON.stringify(ids.slice(0, 500)))
  } catch {
    // Stockage indisponible (navigation privée) : la cloche restera simplement « non lue ».
  }
}
