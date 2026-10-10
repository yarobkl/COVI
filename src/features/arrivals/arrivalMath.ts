// Arrivals without their interface: what has come back, the stamp of each step, the next step and
// the next readable code (BAL-004, CMD-013).
import { longDay, shortDay } from '../../lib/dates'
import { plural } from '../../lib/format'
import type { ArrivalProfit } from '../../lib/operations'
import type { Arrival, ArrivalKind } from '../../lib/types'

/** Steps of an arrival (CHECK arrivals_status_check). */
export type ArrivalStatus = 'draft' | 'ordered' | 'in_transit' | 'received'

/**
 * What an arrival has brought back: « 186 000 FCFA récupérés sur 250 000 (74 %) », then « Encore
 * 64 000 FCFA à récupérer » or, once paid back, « A rapporté 40 000 FCFA ».
 */
export function recoveryOf(cost: number, revenue: number) {
  const paid = Math.max(0, Number(cost) || 0)
  const back = Math.max(0, Number(revenue) || 0)
  return {
    cost: paid,
    revenue: back,
    percent: paid > 0 ? Math.round((back / paid) * 100) : 0,
    toRecover: Math.max(0, paid - back),
    gained: Math.max(0, back - paid),
    done: paid > 0 && back >= paid,
  }
}
export type Recovery = ReturnType<typeof recoveryOf>

/** Look of a stamp: blue (received), dashed (on the way), green (paid back), grey. */
export type StampTone = 'draft' | 'ordered' | 'transit' | 'received' | 'done'

/**
 * The stamp of an arrival: À COMMANDER, COMMANDÉ, EN ROUTE, REÇU (a bale: OUVERT), RENTABILISÉ.
 * « Brouillon » is not a shop word: a draft is an order still to place.
 */
export function stampOf(
  arrival: Pick<Arrival, 'status' | 'kind'>,
  recovery?: Pick<Recovery, 'done'>,
): { label: string; tone: StampTone } {
  switch (arrival.status as ArrivalStatus) {
    case 'received':
      return recovery?.done
        ? { label: 'Rentabilisé', tone: 'done' }
        : { label: arrival.kind === 'balloon' ? 'Ouvert' : 'Reçu', tone: 'received' }
    case 'in_transit':
      return { label: 'En route', tone: 'transit' }
    case 'ordered':
      return { label: 'Commandé', tone: 'ordered' }
    default:
      return { label: 'À commander', tone: 'draft' }
  }
}

/** The next step, with the words of its button and of its confirmation. */
export type NextStep = {
  status: ArrivalStatus
  /** Button on the line: « C’est en route ». */
  action: string
  /** Question of the confirmation. */
  question: string
  text: string
  /** Confirmation button: « Marquer en route ». */
  confirm: string
  /** Said once done. */
  done: string
}

export function nextStepOf(
  arrival: Pick<Arrival, 'status' | 'code' | 'kind'>,
  today: Date = new Date(),
): NextStep | null {
  const { code } = arrival
  switch (arrival.status as ArrivalStatus) {
    case 'draft':
      return {
        status: 'ordered',
        action: 'C’est commandé',
        question: `${code} : c’est commandé ?`,
        text: 'Indiquez-le une fois la commande payée au fournisseur.',
        confirm: 'Marquer commandé',
        done: `${code} : commandé.`,
      }
    case 'ordered':
      return {
        status: 'in_transit',
        action: 'C’est en route',
        question: `${code} est en route ?`,
        text: 'La marchandise a quitté le fournisseur et voyage vers la boutique.',
        confirm: 'Marquer en route',
        done: `${code} : en route.`,
      }
    case 'in_transit':
      return {
        status: 'received',
        action: 'C’est arrivé',
        question: `Vous avez reçu ${code} ?`,
        text: `Il sera noté reçu aujourd’hui, ${longDay(today).toLowerCase()}. Ensuite, mettez les pièces en stock.`,
        confirm: 'Confirmer la réception',
        done:
          arrival.kind === 'balloon'
            ? `${code} est arrivé. Ajoutez ses pièces à mesure que vous déballez.`
            : `${code} est arrivé. Mettez maintenant les pièces en stock.`,
      }
    default:
      return null
  }
}

/** Code prefix of a kind of arrival. */
export const codePrefix = (kind: ArrivalKind) => (kind === 'balloon' ? 'BAL' : 'CMD')

/**
 * The next readable code: `BAL-004` after BAL-003. Older random codes (CMD-3F9A2C) are ignored;
 * `skip` moves further when the code is already taken.
 */
export function nextArrivalCode(kind: ArrivalKind, codes: readonly string[], skip = 0) {
  const prefix = codePrefix(kind)
  const pattern = new RegExp(`^${prefix}-(\\d{1,4})$`)
  const highest = codes.reduce((max, code) => {
    const m = pattern.exec(code.trim().toUpperCase())
    return m ? Math.max(max, Number(m[1])) : max
  }, 0)
  return `${prefix}-${String(highest + 1 + skip).padStart(3, '0')}`
}

export type ArrivalLine = { arrival: Arrival; profit: ArrivalProfit | undefined }

/**
 * Arrivals in two parts: those still to receive (the step to do first), then those received, the
 * ones not paid back yet first. Each part keeps the newest first.
 */
export function groupArrivals(arrivals: readonly Arrival[], profits: readonly ArrivalProfit[]) {
  const byId = new Map(profits.map((p) => [p.id, p]))
  const lines = arrivals.map((arrival) => ({ arrival, profit: byId.get(arrival.id) }))
  const paidBack = (l: ArrivalLine) =>
    l.profit ? recoveryOf(l.profit.cost, l.profit.revenue).done : false
  return {
    waiting: lines.filter((l) => l.arrival.status !== 'received'),
    received: [
      ...lines.filter((l) => l.arrival.status === 'received' && !paidBack(l)),
      ...lines.filter((l) => l.arrival.status === 'received' && paidBack(l)),
    ],
  }
}

/** « Ballon BAL-003 », « Commande CMD-0412 ». */
export const arrivalName = (a: Pick<Arrival, 'kind' | 'code'>) =>
  `${a.kind === 'balloon' ? 'Ballon' : 'Commande'} ${a.code}`

/** « Chine · Fournisseur de Canton · commandé le 28 sept. » */
export function arrivalWhere(a: Arrival) {
  const parts = [a.origin_country, a.supplier_name].filter(Boolean) as string[]
  if (a.status === 'received' && a.received_date)
    parts.push(
      `${a.kind === 'balloon' ? 'ouvert' : 'reçu'} le ${shortDay(new Date(a.received_date + 'T12:00'))}`,
    )
  else if (a.order_date && a.status !== 'draft')
    parts.push(`commandé le ${shortDay(new Date(a.order_date + 'T12:00'))}`)
  return parts.join(' · ')
}

/** « 31 vendues · 19 restent » (pieces of this arrival). */
export const soldAndLeft = (p: Pick<ArrivalProfit, 'sold' | 'remaining'>) =>
  `${plural(p.sold, 'vendue')} · ${p.remaining} ${p.remaining > 1 ? 'restent' : 'reste'}`
