/**
 * Authenticated kitchen notification projection. This is NOT a Web Push delivery
 * channel. It preserves unseen ordered lines while a device is disconnected.
 */
export type KitchenEntry = {
  id: string
  table: string
  orderReference: string | null
  item: string
  quantity: number
  at: string
}
export type KitchenInbox = {
  events: KitchenEntry[]
  more: boolean
  lastSeenId: string
}
const cursorPattern = /^(0|[1-9][0-9]{0,18})$/
export function isKitchenCursor(value: unknown): value is string {
  if (typeof value !== 'string' || !cursorPattern.test(value)) return false
  try {
    return BigInt(value) <= 9223372036854775807n
  } catch {
    return false
  }
}
export function readKitchenInbox(raw: unknown): KitchenInbox {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw Error('File Cuisine invalide.')
  const value = raw as Partial<KitchenInbox>
  if (
    !isKitchenCursor(value.lastSeenId) ||
    typeof value.more !== 'boolean' ||
    !Array.isArray(value.events) ||
    value.events.length > 50
  )
    throw Error('File Cuisine incomplète : aucune confirmation possible.')
  const events: KitchenEntry[] = []
  let previous = BigInt(value.lastSeenId)
  for (const row of value.events) {
    if (
      !row ||
      typeof row !== 'object' ||
      !isKitchenCursor(row.id) ||
      BigInt(row.id) <= previous ||
      typeof row.table !== 'string' ||
      row.table.length > 80 ||
      typeof row.item !== 'string' ||
      row.item.length > 180 ||
      (row.orderReference !== null &&
        (typeof row.orderReference !== 'string' || row.orderReference.length > 80)) ||
      !Number.isInteger(row.quantity) ||
      row.quantity < 1 ||
      row.quantity > 100 ||
      typeof row.at !== 'string' ||
      !Number.isFinite(Date.parse(row.at))
    )
      throw Error('Événement de cuisine invalide.')
    previous = BigInt(row.id)
    events.push({
      id: row.id,
      table: row.table,
      item: row.item,
      orderReference: row.orderReference,
      quantity: row.quantity,
      at: row.at,
    })
  }
  return { events, more: value.more, lastSeenId: value.lastSeenId }
}

/** Only newly arrived events generate a browser notification; initial backlog is UI only. */
export function newlyArrivedKitchenCount(previousMax: string | null, inbox: KitchenInbox) {
  const newest = inbox.events[inbox.events.length - 1]?.id ?? inbox.lastSeenId
  if (!isKitchenCursor(newest)) return { newest: inbox.lastSeenId, count: 0 }
  if (previousMax === null) return { newest, count: 0 }
  const max = BigInt(previousMax)
  const count = inbox.events.filter((e) => BigInt(e.id) > max).length
  return {
    newest: BigInt(newest) > max ? newest : previousMax,
    count,
  }
}
